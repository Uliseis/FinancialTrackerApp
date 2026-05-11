import { and, eq, inArray, isNull, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  accounts,
  transactions,
  transferRoutes,
  type Account,
  type NewTransaction,
  type Transaction,
  type TransferRoute,
} from "@/db/schema";
import type { RuleField, RuleMatch } from "@/lib/rules";

export function mirrorExternalId(sourceTxId: string): string {
  return `mirror:${sourceTxId}`;
}

export function routeMatches(
  route: TransferRoute,
  tx: Pick<Transaction, "description" | "counterparty" | "accountId" | "direction">,
): boolean {
  if (!route.enabled) return false;
  if (route.sourceAccountId && route.sourceAccountId !== tx.accountId) return false;
  if (route.direction && route.direction !== tx.direction) return false;
  const field = (route.field as RuleField) ?? "description";
  const haystack = (field === "counterparty" ? tx.counterparty : tx.description) ?? "";
  const needle = route.pattern;
  if (!needle) return false;
  const kind = (route.matchType as RuleMatch) ?? "contains";
  const h = haystack.toLowerCase();
  const n = needle.toLowerCase();
  switch (kind) {
    case "equals":
      return h === n;
    case "startsWith":
      return h.startsWith(n);
    case "endsWith":
      return h.endsWith(n);
    case "regex":
      try {
        return new RegExp(needle, "i").test(haystack);
      } catch {
        return false;
      }
    case "contains":
    default:
      return h.includes(n);
  }
}

function flipDirection(d: Transaction["direction"]): Transaction["direction"] {
  return d === "debit" ? "credit" : "debit";
}

function negate(value: string | null): string | null {
  if (value == null) return null;
  if (value.startsWith("-")) return value.slice(1);
  return `-${value}`;
}

export interface CreateMirrorOptions {
  routeId?: string;
}

export async function createMirrorTransaction(
  source: Transaction,
  targetAccountId: string,
  opts: CreateMirrorOptions = {},
): Promise<{ mirrorId: string; transferGroupId: string } | null> {
  if (source.accountId === targetAccountId) return null;
  if (source.routedFromTxId) return null;

  const [target] = await db
    .select({ id: accounts.id, archived: accounts.archived })
    .from(accounts)
    .where(eq(accounts.id, targetAccountId));
  if (!target || target.archived) return null;

  const externalId = mirrorExternalId(source.id);

  const existing = await db
    .select({ id: transactions.id, transferGroupId: transactions.transferGroupId })
    .from(transactions)
    .where(
      and(
        eq(transactions.accountId, targetAccountId),
        eq(transactions.externalId, externalId),
      ),
    );

  if (existing.length > 0) {
    const groupId = existing[0].transferGroupId ?? crypto.randomUUID();
    if (!source.isTransfer || source.transferGroupId !== groupId) {
      await db
        .update(transactions)
        .set({
          isTransfer: true,
          transferGroupId: groupId,
          categorySource: source.categorySource ?? "rule",
        })
        .where(eq(transactions.id, source.id));
    }
    return { mirrorId: existing[0].id, transferGroupId: groupId };
  }

  const transferGroupId = source.transferGroupId ?? crypto.randomUUID();

  const mirrorValues: NewTransaction = {
    accountId: targetAccountId,
    externalId,
    bookedAt: source.bookedAt,
    valueAt: source.valueAt,
    amount: negate(source.amount) ?? source.amount,
    currency: source.currency,
    amountEur: negate(source.amountEur),
    direction: flipDirection(source.direction),
    description: source.description,
    counterparty: source.counterparty ?? "Routed transfer",
    isTransfer: true,
    transferGroupId,
    routedFromTxId: source.id,
    raw: {
      mirror: true,
      sourceTxId: source.id,
      ...(opts.routeId ? { routeId: opts.routeId } : {}),
    },
  };

  const inserted = await db
    .insert(transactions)
    .values(mirrorValues)
    .onConflictDoNothing({
      target: [transactions.accountId, transactions.externalId],
    })
    .returning({ id: transactions.id });

  if (inserted.length === 0) {
    const [row] = await db
      .select({ id: transactions.id })
      .from(transactions)
      .where(
        and(
          eq(transactions.accountId, targetAccountId),
          eq(transactions.externalId, externalId),
        ),
      );
    if (!row) return null;
    await db
      .update(transactions)
      .set({
        isTransfer: true,
        transferGroupId,
        categorySource: source.categorySource ?? "rule",
      })
      .where(eq(transactions.id, source.id));
    return { mirrorId: row.id, transferGroupId };
  }

  await db
    .update(transactions)
    .set({
      isTransfer: true,
      transferGroupId,
      categorySource: source.categorySource ?? "rule",
    })
    .where(eq(transactions.id, source.id));

  return { mirrorId: inserted[0].id, transferGroupId };
}

export async function removeMirrorTransaction(
  sourceTxId: string,
): Promise<{ deleted: number }> {
  const deleted = await db
    .delete(transactions)
    .where(eq(transactions.routedFromTxId, sourceTxId))
    .returning({ id: transactions.id });

  await db
    .update(transactions)
    .set({ isTransfer: false, transferGroupId: null })
    .where(eq(transactions.id, sourceTxId));

  return { deleted: deleted.length };
}

export interface ApplyRoutesOptions {
  txIds?: string[];
  sinceDays?: number;
  routeId?: string;
}

export interface ApplyRoutesResult {
  scanned: number;
  mirroredCreated: number;
}

export async function applyTransferRoutes(
  opts: ApplyRoutesOptions = {},
): Promise<ApplyRoutesResult> {
  const routes = await db
    .select()
    .from(transferRoutes)
    .where(
      opts.routeId
        ? and(eq(transferRoutes.enabled, true), eq(transferRoutes.id, opts.routeId))
        : eq(transferRoutes.enabled, true),
    )
    .orderBy(sql`${transferRoutes.priority} desc, ${transferRoutes.createdAt} asc`);

  if (routes.length === 0) return { scanned: 0, mirroredCreated: 0 };

  const since = opts.sinceDays
    ? new Date(Date.now() - opts.sinceDays * 86_400_000)
    : null;

  const conditions = [
    isNull(transactions.routedFromTxId),
    eq(transactions.isTransfer, false),
  ];
  if (opts.txIds && opts.txIds.length > 0) {
    conditions.push(inArray(transactions.id, opts.txIds));
  } else if (since) {
    conditions.push(sql`${transactions.bookedAt} >= ${since}`);
  }

  const candidates = await db
    .select()
    .from(transactions)
    .where(and(...conditions));

  let mirroredCreated = 0;
  for (const tx of candidates) {
    let matchedRoute: TransferRoute | null = null;
    for (const route of routes) {
      if (routeMatches(route, tx)) {
        matchedRoute = route;
        break;
      }
    }
    if (!matchedRoute) continue;
    if (matchedRoute.targetAccountId === tx.accountId) continue;
    const result = await createMirrorTransaction(tx, matchedRoute.targetAccountId, {
      routeId: matchedRoute.id,
    });
    if (result) mirroredCreated++;
  }

  return { scanned: candidates.length, mirroredCreated };
}

export async function listManualAccountsForRouting(): Promise<
  Pick<Account, "id" | "name" | "currency" | "institution">[]
> {
  return db
    .select({
      id: accounts.id,
      name: accounts.name,
      currency: accounts.currency,
      institution: accounts.institution,
    })
    .from(accounts)
    .where(and(eq(accounts.archived, false), isNull(accounts.connectionId)));
}
