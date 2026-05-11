import { inArray, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import { transactions, type Account } from "@/db/schema";

export function isManualAccount(account: Pick<Account, "connectionId">): boolean {
  return account.connectionId == null;
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

export interface ComputeBalanceOptions {
  rateFor: (currency: string) => Promise<number>;
}

export async function computeAccountBalancesEur(
  rows: Account[],
  opts: ComputeBalanceOptions,
): Promise<Map<string, number>> {
  const balances = new Map<string, number>();
  const manualIds = rows
    .filter((a) => isManualAccount(a))
    .map((a) => a.id);
  const manualTxSums = await sumAmountEurByAccount(manualIds);

  for (const a of rows) {
    if (isManualAccount(a)) {
      const rate = await opts.rateFor(a.currency);
      const opening = a.manualOpeningBalance ? Number(a.manualOpeningBalance) / rate : 0;
      const tx = manualTxSums.get(a.id) ?? 0;
      balances.set(a.id, opening + tx);
    } else {
      const rate = await opts.rateFor(a.currency);
      balances.set(a.id, a.balance ? Number(a.balance) / rate : 0);
    }
  }
  return balances;
}

export async function computeManualAccountNativeBalances(
  rows: Account[],
): Promise<Map<string, number>> {
  const out = new Map<string, number>();
  const manualIds = rows.filter(isManualAccount).map((a) => a.id);
  if (manualIds.length === 0) return out;
  const txSums = await sumAmountByAccountNative(manualIds);
  for (const a of rows) {
    if (!isManualAccount(a)) continue;
    const opening = a.manualOpeningBalance ? Number(a.manualOpeningBalance) : 0;
    const tx = txSums.get(a.id) ?? 0;
    out.set(a.id, opening + tx);
  }
  return out;
}
