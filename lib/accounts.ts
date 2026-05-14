import { and, eq, gt, gte, inArray, lt, sql } from "drizzle-orm";
import { alias } from "drizzle-orm/pg-core";
import { db } from "@/lib/db";
import { sharedExpenseGroups, transactions, type Account } from "@/db/schema";

export function isManualAccount(account: Pick<Account, "connectionId">): boolean {
  return account.connectionId == null;
}

function hasAnchor(
  a: Pick<Account, "balanceAnchor" | "balanceAnchorAt">,
): a is Pick<Account, "balanceAnchor" | "balanceAnchorAt"> & {
  balanceAnchor: string;
  balanceAnchorAt: Date;
} {
  return a.balanceAnchor != null && a.balanceAnchorAt != null;
}

export async function sumAmountEurByAccount(
  accountIds: string[],
): Promise<Map<string, number>> {
  const out = new Map<string, number>();
  if (accountIds.length === 0) return out;
  const rows = await db
    .select({
      accountId: transactions.accountId,
      total: sql<string>`coalesce(sum(${transactions.amountEur}), 0)`,
    })
    .from(transactions)
    .where(inArray(transactions.accountId, accountIds))
    .groupBy(transactions.accountId);
  for (const r of rows) out.set(r.accountId, Number(r.total));
  return out;
}

export async function sumAmountByAccountNative(
  accountIds: string[],
): Promise<Map<string, number>> {
  const out = new Map<string, number>();
  if (accountIds.length === 0) return out;
  const rows = await db
    .select({
      accountId: transactions.accountId,
      total: sql<string>`coalesce(sum(${transactions.amount}), 0)`,
    })
    .from(transactions)
    .where(inArray(transactions.accountId, accountIds))
    .groupBy(transactions.accountId);
  for (const r of rows) out.set(r.accountId, Number(r.total));
  return out;
}

async function sumSinceByAccount(
  pairs: Array<{ accountId: string; since: Date }>,
  column: "amount" | "amountEur",
): Promise<Map<string, number>> {
  const out = new Map<string, number>();
  if (pairs.length === 0) return out;
  const col = column === "amount" ? transactions.amount : transactions.amountEur;
  for (const { accountId, since } of pairs) {
    const rows = await db
      .select({
        total: sql<string>`coalesce(sum(${col}), 0)`,
      })
      .from(transactions)
      .where(and(eq(transactions.accountId, accountId), gt(transactions.bookedAt, since)));
    out.set(accountId, Number(rows[0]?.total ?? 0));
  }
  return out;
}

export interface ComputeBalanceOptions {
  rateFor: (currency: string) => Promise<number>;
}

export async function computeAccountBalancesEur(
  rows: Account[],
  opts: ComputeBalanceOptions,
): Promise<Map<string, number>> {
  const balances = new Map<string, number>();

  const manualNoAnchorIds = rows
    .filter((a) => isManualAccount(a) && !hasAnchor(a))
    .map((a) => a.id);
  const manualTxSums = await sumAmountEurByAccount(manualNoAnchorIds);

  const anchorPairs = rows
    .filter(hasAnchor)
    .map((a) => ({ accountId: a.id, since: a.balanceAnchorAt as Date }));
  const anchorTxSumsEur = await sumSinceByAccount(anchorPairs, "amountEur");

  for (const a of rows) {
    const rate = await opts.rateFor(a.currency);
    if (hasAnchor(a)) {
      const anchor = Number(a.balanceAnchor) / rate;
      const tx = anchorTxSumsEur.get(a.id) ?? 0;
      balances.set(a.id, anchor + tx);
    } else if (isManualAccount(a)) {
      const opening = a.manualOpeningBalance ? Number(a.manualOpeningBalance) / rate : 0;
      const tx = manualTxSums.get(a.id) ?? 0;
      balances.set(a.id, opening + tx);
    } else {
      balances.set(a.id, a.balance ? Number(a.balance) / rate : 0);
    }
  }
  return balances;
}

export async function computeAccountNativeBalances(
  rows: Account[],
): Promise<Map<string, number>> {
  const out = new Map<string, number>();

  const manualNoAnchorIds = rows
    .filter((a) => isManualAccount(a) && !hasAnchor(a))
    .map((a) => a.id);
  const manualTxSums = await sumAmountByAccountNative(manualNoAnchorIds);

  const anchorPairs = rows
    .filter(hasAnchor)
    .map((a) => ({ accountId: a.id, since: a.balanceAnchorAt as Date }));
  const anchorTxSumsNative = await sumSinceByAccount(anchorPairs, "amount");

  for (const a of rows) {
    if (hasAnchor(a)) {
      const anchor = Number(a.balanceAnchor);
      const tx = anchorTxSumsNative.get(a.id) ?? 0;
      out.set(a.id, anchor + tx);
    } else if (isManualAccount(a)) {
      const opening = a.manualOpeningBalance ? Number(a.manualOpeningBalance) : 0;
      const tx = manualTxSums.get(a.id) ?? 0;
      out.set(a.id, opening + tx);
    } else if (a.balance != null) {
      out.set(a.id, Number(a.balance));
    }
  }
  return out;
}

export async function computeMonthlyExpenseEurByAccount(
  accountIds: string[],
  monthStart: Date,
  monthEnd: Date,
): Promise<Map<string, number>> {
  const out = new Map<string, number>();
  if (accountIds.length === 0) return out;

  const startDate = monthStart.toISOString().slice(0, 10);

  const directRows = await db
    .select({
      accountId: transactions.accountId,
      total: sql<string>`coalesce(sum(${transactions.amountEur}), 0)`,
    })
    .from(transactions)
    .where(
      and(
        inArray(transactions.accountId, accountIds),
        eq(transactions.direction, "debit"),
        eq(transactions.isTransfer, false),
        sql`${transactions.sharedExpenseGroupId} is null`,
        gte(transactions.bookedAt, monthStart),
        lt(transactions.bookedAt, monthEnd),
      ),
    )
    .groupBy(transactions.accountId);

  for (const r of directRows) {
    out.set(r.accountId, Math.abs(Number(r.total)));
  }

  const primaryTx = alias(transactions, "primary_tx");
  const groupRows = await db
    .select({
      primaryAccountId: primaryTx.accountId,
      net: sql<string>`coalesce(sum(-${transactions.amountEur}), 0)`,
    })
    .from(sharedExpenseGroups)
    .leftJoin(transactions, eq(transactions.sharedExpenseGroupId, sharedExpenseGroups.id))
    .leftJoin(primaryTx, eq(primaryTx.id, sharedExpenseGroups.primaryTxId))
    .where(
      and(
        eq(sharedExpenseGroups.attributionMonth, startDate),
        inArray(transactions.accountId, accountIds),
      ),
    )
    .groupBy(primaryTx.accountId);

  for (const r of groupRows) {
    if (!r.primaryAccountId) continue;
    out.set(r.primaryAccountId, (out.get(r.primaryAccountId) ?? 0) + Number(r.net));
  }

  return out;
}

export async function computeBalanceDrifts(
  rows: Account[],
): Promise<Map<string, number>> {
  const out = new Map<string, number>();
  const anchorPairs = rows
    .filter((a) => a.connectionId != null && a.balanceAnchor != null && a.balanceAnchorAt != null && a.balance != null)
    .map((a) => ({
      id: a.id,
      bank: Number(a.balance),
      anchor: Number(a.balanceAnchor),
      since: a.balanceAnchorAt as Date,
    }));
  for (const p of anchorPairs) {
    const [row] = await db
      .select({ total: sql<string>`coalesce(sum(${transactions.amount}), 0)` })
      .from(transactions)
      .where(and(eq(transactions.accountId, p.id), gt(transactions.bookedAt, p.since)));
    const computed = p.anchor + Number(row?.total ?? 0);
    out.set(p.id, p.bank - computed);
  }
  return out;
}

export async function computeManualAccountNativeBalances(
  rows: Account[],
): Promise<Map<string, number>> {
  const all = await computeAccountNativeBalances(rows);
  const out = new Map<string, number>();
  for (const a of rows) {
    if (isManualAccount(a) && all.has(a.id)) out.set(a.id, all.get(a.id)!);
  }
  return out;
}
