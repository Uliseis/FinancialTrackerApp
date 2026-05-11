import { and, eq, gte, isNull, lte, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import { fxRates, transactions } from "@/db/schema";

const ECB_90D = "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist-90d.xml";
const ECB_FULL = "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist.xml";

export interface EcbRate {
  date: string;
  currency: string;
  rate: string;
}

function parseEcbXml(xml: string): EcbRate[] {
  const out: EcbRate[] = [];
  const dayRegex = /<Cube\s+time="([^"]+)">([\s\S]*?)<\/Cube>/g;
  const ccyRegex = /<Cube\s+currency="([^"]+)"\s+rate="([^"]+)"\s*\/>/g;
  let dayMatch: RegExpExecArray | null;
  while ((dayMatch = dayRegex.exec(xml)) !== null) {
    const date = dayMatch[1];
    const inner = dayMatch[2];
    let ccyMatch: RegExpExecArray | null;
    ccyRegex.lastIndex = 0;
    while ((ccyMatch = ccyRegex.exec(inner)) !== null) {
      out.push({ date, currency: ccyMatch[1], rate: ccyMatch[2] });
    }
  }
  return out;
}

async function fetchEcb(url: string): Promise<EcbRate[]> {
  const res = await fetch(url, { cache: "no-store" });
  if (!res.ok) throw new Error(`ECB fetch failed: ${res.status}`);
  const xml = await res.text();
  return parseEcbXml(xml);
}

export async function syncFxRates(
  opts: { full?: boolean } = {},
): Promise<{ inserted: number; daysCovered: number }> {
  const rows = await fetchEcb(opts.full ? ECB_FULL : ECB_90D);
  if (rows.length === 0) return { inserted: 0, daysCovered: 0 };

  let inserted = 0;
  const chunkSize = 500;
  for (let i = 0; i < rows.length; i += chunkSize) {
    const chunk = rows.slice(i, i + chunkSize);
    const result = await db
      .insert(fxRates)
      .values(chunk.map((r) => ({ date: r.date, currency: r.currency, rate: r.rate })))
      .onConflictDoNothing({ target: [fxRates.date, fxRates.currency] })
      .returning({ id: fxRates.id });
    inserted += result.length;
  }

  const days = new Set(rows.map((r) => r.date));
  return { inserted, daysCovered: days.size };
}

function toIsoDate(d: Date | string): string {
  if (typeof d === "string") {
    return d.length > 10 ? d.slice(0, 10) : d;
  }
  return d.toISOString().slice(0, 10);
}

export async function getRate(date: Date | string, currency: string): Promise<number | null> {
  const ccy = currency.toUpperCase();
  if (ccy === "EUR") return 1;
  const iso = toIsoDate(date);

  const exact = await db
    .select({ rate: fxRates.rate })
    .from(fxRates)
    .where(and(eq(fxRates.currency, ccy), eq(fxRates.date, iso)))
    .limit(1);
  if (exact[0]) return Number(exact[0].rate);

  const prior = await db
    .select({ rate: fxRates.rate, date: fxRates.date })
    .from(fxRates)
    .where(and(eq(fxRates.currency, ccy), lte(fxRates.date, iso)))
    .orderBy(sql`${fxRates.date} desc`)
    .limit(1);
  if (prior[0]) return Number(prior[0].rate);

  return null;
}

export async function toEur(
  amount: number | string,
  currency: string,
  date: Date | string,
): Promise<{ amountEur: number; rate: number } | null> {
  const rate = await getRate(date, currency);
  if (rate == null) return null;
  const amt = typeof amount === "string" ? Number(amount) : amount;
  return { amountEur: amt / rate, rate };
}

export async function backfillTransactionEurAmounts(opts: {
  limit?: number;
  sinceDays?: number;
} = {}): Promise<{ updated: number; skipped: number }> {
  const where = opts.sinceDays
    ? and(
        isNull(transactions.amountEur),
        gte(
          transactions.bookedAt,
          new Date(Date.now() - opts.sinceDays * 86_400_000),
        ),
      )
    : isNull(transactions.amountEur);

  const rows = await db
    .select({
      id: transactions.id,
      amount: transactions.amount,
      currency: transactions.currency,
      bookedAt: transactions.bookedAt,
    })
    .from(transactions)
    .where(where)
    .limit(opts.limit ?? 10_000);

  let updated = 0;
  let skipped = 0;
  for (const r of rows) {
    const conv = await toEur(r.amount, r.currency, r.bookedAt);
    if (!conv) {
      skipped++;
      continue;
    }
    await db
      .update(transactions)
      .set({
        amountEur: conv.amountEur.toFixed(2),
        fxRateUsed: conv.rate.toFixed(8),
      })
      .where(eq(transactions.id, r.id));
    updated++;
  }
  return { updated, skipped };
}
