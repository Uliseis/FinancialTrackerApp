import { eq } from "drizzle-orm";
import Papa from "papaparse";
import { db } from "@/lib/db";
import {
  accounts,
  syncRuns,
  transactions,
  type NewTransaction,
} from "@/db/schema";
import { applyRulesToTransactions } from "@/lib/categorize";
import { detectTransfers } from "@/lib/transfers";
import { backfillTransactionEurAmounts } from "@/lib/fx";
import { applyTransferRoutes } from "@/lib/transfer-routes";

export interface CsvImportResult {
  parsed: number;
  inserted: number;
  skippedTransfer: number;
  skippedDuplicate: number;
  errors: string[];
  postProcess?: {
    fxBackfilled: number;
    categorized: number;
    routedMirrors: number;
    transfersMatched: number;
  };
}

export type ImportProgressStage =
  | "parse"
  | "prepare"
  | "insert"
  | "fx"
  | "categorize"
  | "routes"
  | "transfers"
  | "done";

export interface ImportProgressEvent {
  stage: ImportProgressStage;
  message: string;
  data?: Record<string, unknown>;
}

export type ImportProgressCallback = (event: ImportProgressEvent) => void | Promise<void>;

interface RevolutCsvRow {
  Type?: string;
  "Started Date"?: string;
  "Completed Date"?: string;
  Description?: string;
  Amount?: string;
  Fee?: string;
  Balance?: string;
}

const REQUIRED_HEADERS = ["Type", "Started Date", "Completed Date", "Description", "Amount"] as const;

function slugifyDescription(input: string | undefined): string {
  if (!input) return "";
  return input
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40);
}

function getMadridOffsetMinutes(year: number, month: number, day: number, hour: number, minute: number): number {
  const utc = Date.UTC(year, month - 1, day, hour, minute);
  const fmt = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/Madrid",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });
  const parts = Object.fromEntries(
    fmt.formatToParts(new Date(utc)).map((p) => [p.type, p.value]),
  );
  const madridUtc = Date.UTC(
    Number(parts.year),
    Number(parts.month) - 1,
    Number(parts.day),
    Number(parts.hour) === 24 ? 0 : Number(parts.hour),
    Number(parts.minute),
  );
  return (madridUtc - utc) / 60_000;
}

function parseMadridLocal(raw: string | undefined): Date | null {
  if (!raw) return null;
  const m = raw.match(/^(\d{4})-(\d{2})-(\d{2})[T\s](\d{2}):(\d{2})(?::(\d{2}))?/);
  if (!m) return null;
  const [, y, mo, d, h, mi, s] = m;
  const year = Number(y);
  const month = Number(mo);
  const day = Number(d);
  const hour = Number(h);
  const minute = Number(mi);
  const second = s ? Number(s) : 0;
  const offsetMin = getMadridOffsetMinutes(year, month, day, hour, minute);
  const utcMs = Date.UTC(year, month - 1, day, hour, minute, second) - offsetMin * 60_000;
  const date = new Date(utcMs);
  return Number.isNaN(date.getTime()) ? null : date;
}

function normalizeSignedAmount(raw: string | undefined): string | null {
  if (raw == null) return null;
  const cleaned = raw.trim().replace(/,/g, "");
  if (!/^-?\d+(\.\d+)?$/.test(cleaned)) return null;
  if (!Number.isFinite(Number(cleaned))) return null;
  return cleaned;
}

export async function importRevolutCsv(
  accountId: string,
  csvText: string,
  onProgress?: ImportProgressCallback,
): Promise<CsvImportResult> {
  const result: CsvImportResult = {
    parsed: 0,
    inserted: 0,
    skippedTransfer: 0,
    skippedDuplicate: 0,
    errors: [],
  };

  const emit = async (event: ImportProgressEvent) => {
    if (onProgress) await onProgress(event);
  };

  const [account] = await db.select().from(accounts).where(eq(accounts.id, accountId));
  if (!account) throw new Error(`Account ${accountId} not found`);
  if (account.archived) throw new Error("Account is archived");
  if (account.connectionId != null) {
    throw new Error("CSV import is only allowed on manual accounts (no connection)");
  }

  await emit({ stage: "parse", message: "Parsing CSV" });
  const parsed = Papa.parse<RevolutCsvRow>(csvText, {
    header: true,
    skipEmptyLines: true,
    dynamicTyping: false,
    transformHeader: (h) => h.trim(),
  });

  if (parsed.errors.length > 0) {
    for (const e of parsed.errors.slice(0, 5)) {
      result.errors.push(`csv: ${e.message} (row ${e.row ?? "?"})`);
    }
  }

  const headers = parsed.meta.fields ?? [];
  for (const required of REQUIRED_HEADERS) {
    if (!headers.includes(required)) {
      throw new Error(
        `Unrecognised CSV format — missing required column "${required}". Expected a Revolut statement export.`,
      );
    }
  }

  const rows = parsed.data;
  result.parsed = rows.length;
  await emit({ stage: "prepare", message: `Parsed ${rows.length} rows`, data: { parsed: rows.length } });

  const [run] = await db
    .insert(syncRuns)
    .values({ connector: "manual", connectionId: null })
    .returning();

  const dupCounts = new Map<string, number>();
  const toInsert: NewTransaction[] = [];

  for (let idx = 0; idx < rows.length; idx++) {
    const row = rows[idx];
    const type = (row.Type ?? "").trim().toUpperCase();
    if (type === "TRANSFER") {
      result.skippedTransfer++;
      continue;
    }

    const started = parseMadridLocal(row["Started Date"]);
    const completed = parseMadridLocal(row["Completed Date"]) ?? started;
    const amount = normalizeSignedAmount(row.Amount);
    if (!started || !amount) {
      result.errors.push(`row ${idx + 1}: missing date or amount`);
      continue;
    }

    const description = (row.Description ?? "").trim() || null;
    const descSlug = slugifyDescription(row.Description);
    const startedIso = started.toISOString();
    const signature = `${startedIso}|${amount}|${descSlug}`;
    const dupIdx = dupCounts.get(signature) ?? 0;
    dupCounts.set(signature, dupIdx + 1);

    const externalId = `revolutcsv:v1:${startedIso}:${amount}:${descSlug}:${dupIdx}`;
    const numericAmount = Number(amount);
    const direction: "debit" | "credit" = numericAmount < 0 ? "debit" : "credit";

    toInsert.push({
      accountId,
      externalId,
      bookedAt: started,
      valueAt: completed,
      amount,
      currency: account.currency,
      direction,
      description,
      counterparty: null,
      raw: { source: "revolutcsv:v1", row: row as unknown as Record<string, unknown> },
    });
  }

  const insertedIds: string[] = [];
  if (toInsert.length > 0) {
    await emit({
      stage: "insert",
      message: `Inserting ${toInsert.length} rows`,
      data: { total: toInsert.length },
    });
    const CHUNK = 200;
    for (let i = 0; i < toInsert.length; i += CHUNK) {
      const chunk = toInsert.slice(i, i + CHUNK);
      const inserted = await db
        .insert(transactions)
        .values(chunk)
        .onConflictDoNothing({
          target: [transactions.accountId, transactions.externalId],
        })
        .returning({ id: transactions.id });
      for (const row of inserted) insertedIds.push(row.id);
    }
  }
  result.inserted = insertedIds.length;
  result.skippedDuplicate = toInsert.length - result.inserted;

  let fxBackfilled = 0;
  let categorized = 0;
  let routedMirrors = 0;
  let transfersMatched = 0;

  if (insertedIds.length > 0) {
    await emit({
      stage: "fx",
      message: "Converting amounts to EUR",
      data: { inserted: result.inserted },
    });
    try {
      const fx = await backfillTransactionEurAmounts({ txIds: insertedIds });
      fxBackfilled = fx.updated;
    } catch (err) {
      result.errors.push(`fx: ${err instanceof Error ? err.message : String(err)}`);
    }
    await emit({ stage: "categorize", message: "Applying category rules" });
    try {
      const cats = await applyRulesToTransactions(insertedIds);
      categorized = cats.updated;
    } catch (err) {
      result.errors.push(`categorize: ${err instanceof Error ? err.message : String(err)}`);
    }
    await emit({ stage: "routes", message: "Applying transfer routes" });
    try {
      const routed = await applyTransferRoutes({ txIds: insertedIds });
      routedMirrors = routed.mirroredCreated;
    } catch (err) {
      result.errors.push(`routes: ${err instanceof Error ? err.message : String(err)}`);
    }
    await emit({ stage: "transfers", message: "Detecting transfers" });
    try {
      const transfers = await detectTransfers({ sinceDays: 30 });
      transfersMatched = transfers.matched;
    } catch (err) {
      result.errors.push(`transfers: ${err instanceof Error ? err.message : String(err)}`);
    }
  }
  result.postProcess = { fxBackfilled, categorized, routedMirrors, transfersMatched };

  await db
    .update(syncRuns)
    .set({
      finishedAt: new Date(),
      status: result.errors.length > 0 ? "partial" : "ok",
      insertedTransactions: result.inserted,
      error: result.errors.length > 0 ? result.errors.join("; ") : null,
      raw: {
        source: "revolutcsv:v1",
        parsed: result.parsed,
        inserted: result.inserted,
        skippedTransfer: result.skippedTransfer,
        skippedDuplicate: result.skippedDuplicate,
      },
    })
    .where(eq(syncRuns.id, run.id));

  await emit({
    stage: "done",
    message: "Import complete",
    data: { ...result } as unknown as Record<string, unknown>,
  });

  return result;
}
