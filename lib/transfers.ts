import { and, eq, gte, or, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import { transactions } from "@/db/schema";

const DEFAULT_LOOKBACK_DAYS = 30;
const PAIR_WINDOW_DAYS = 3;
const EUR_TOLERANCE = 0.01;

interface Candidate {
  id: string;
  accountId: string;
  direction: "debit" | "credit";
  amountEur: number;
  bookedAt: Date;
  isTransfer: boolean;
  transferGroupId: string | null;
  categorySource: "bank" | "rule" | "manual" | null;
}

export interface DetectTransfersResult {
  scanned: number;
  matched: number;
}

export async function detectTransfers(
  opts: { sinceDays?: number; txIds?: string[] } = {},
): Promise<DetectTransfersResult> {
  const since = new Date(
    Date.now() - (opts.sinceDays ?? DEFAULT_LOOKBACK_DAYS) * 86_400_000,
  );

  const baseWhere = and(
    gte(transactions.bookedAt, since),
    sql`${transactions.amountEur} is not null`,
  );

  const rows = await db
    .select({
      id: transactions.id,
      accountId: transactions.accountId,
      direction: transactions.direction,
      amountEur: transactions.amountEur,
      bookedAt: transactions.bookedAt,
      isTransfer: transactions.isTransfer,
      transferGroupId: transactions.transferGroupId,
      categorySource: transactions.categorySource,
    })
    .from(transactions)
    .where(baseWhere);

  const candidates: Candidate[] = rows
    .filter((r) => r.amountEur != null)
    .map((r) => ({
      id: r.id,
      accountId: r.accountId,
      direction: r.direction,
      amountEur: Math.abs(Number(r.amountEur)),
      bookedAt: r.bookedAt,
      isTransfer: r.isTransfer,
      transferGroupId: r.transferGroupId,
      categorySource: r.categorySource,
    }));

  const debits = candidates.filter((c) => c.direction === "debit" && !c.isTransfer);
  const credits = candidates.filter((c) => c.direction === "credit" && !c.isTransfer);

  if (debits.length === 0 || credits.length === 0) {
    return { scanned: candidates.length, matched: 0 };
  }

  const claimed = new Set<string>();
  const pairs: Array<[Candidate, Candidate]> = [];

  for (const debit of debits) {
    if (claimed.has(debit.id) || debit.categorySource === "manual") continue;
    const partners = credits.filter((c) => {
      if (claimed.has(c.id)) return false;
      if (c.accountId === debit.accountId) return false;
      if (c.categorySource === "manual") return false;
      if (Math.abs(c.amountEur - debit.amountEur) > EUR_TOLERANCE) return false;
      const diffDays =
        Math.abs(c.bookedAt.getTime() - debit.bookedAt.getTime()) / 86_400_000;
      return diffDays <= PAIR_WINDOW_DAYS;
    });
    if (partners.length === 1) {
      const partner = partners[0];
      claimed.add(debit.id);
      claimed.add(partner.id);
      pairs.push([debit, partner]);
    }
  }

  if (pairs.length === 0) return { scanned: candidates.length, matched: 0 };

  let matched = 0;
  for (const [a, b] of pairs) {
    const groupId = a.transferGroupId ?? b.transferGroupId ?? crypto.randomUUID();
    await db
      .update(transactions)
      .set({ isTransfer: true, transferGroupId: groupId })
      .where(or(eq(transactions.id, a.id), eq(transactions.id, b.id)));
    matched += 2;
  }

  return { scanned: candidates.length, matched };
}
