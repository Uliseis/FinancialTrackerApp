import { and, eq, gte, inArray, isNotNull, or, sql } from "drizzle-orm";
import { alias } from "drizzle-orm/pg-core";
import { db } from "@/lib/db";
import { accounts, transactions } from "@/db/schema";
import { isUsableForTransfers } from "@/lib/account-status";

const DEFAULT_LOOKBACK_DAYS = 30;
const PAIR_WINDOW_DAYS = 3;
const EUR_TOLERANCE = 0.01;

interface Candidate {
  id: string;
  accountId: string;
  spaceId: string | null;
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
    sql`${transactions.sharedExpenseGroupId} is null`,
  );

  const rows = await db
    .select({
      id: transactions.id,
      accountId: transactions.accountId,
      spaceId: accounts.spaceId,
      direction: transactions.direction,
      amountEur: transactions.amountEur,
      bookedAt: transactions.bookedAt,
      isTransfer: transactions.isTransfer,
      transferGroupId: transactions.transferGroupId,
      categorySource: transactions.categorySource,
    })
    .from(transactions)
    .leftJoin(accounts, eq(transactions.accountId, accounts.id))
    .where(baseWhere);

  const candidates: Candidate[] = rows
    .filter((r) => r.amountEur != null)
    .map((r) => ({
      id: r.id,
      accountId: r.accountId,
      spaceId: r.spaceId,
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
      if (c.spaceId !== debit.spaceId) return false;
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

export interface RepairResult {
  groupsBroken: number;
  txsUnflagged: number;
  mirrorsDeleted: number;
  orphansFixed: number;
}

export async function repairTransferGroups(
  opts: { accountId?: string } = {},
): Promise<RepairResult> {
  const result: RepairResult = {
    groupsBroken: 0,
    txsUnflagged: 0,
    mirrorsDeleted: 0,
    orphansFixed: 0,
  };

  const groupIdsRows = opts.accountId
    ? await db
        .selectDistinct({ id: transactions.transferGroupId })
        .from(transactions)
        .where(
          and(
            eq(transactions.accountId, opts.accountId),
            isNotNull(transactions.transferGroupId),
          ),
        )
    : await db
        .selectDistinct({ id: transactions.transferGroupId })
        .from(transactions)
        .where(isNotNull(transactions.transferGroupId));

  const groupIds = groupIdsRows
    .map((r) => r.id)
    .filter((v): v is string => v != null);

  if (groupIds.length > 0) {
    const members = await db
      .select({
        id: transactions.id,
        groupId: transactions.transferGroupId,
        accountId: transactions.accountId,
        spaceId: accounts.spaceId,
        archived: accounts.archived,
        routedFromTxId: transactions.routedFromTxId,
      })
      .from(transactions)
      .leftJoin(accounts, eq(transactions.accountId, accounts.id))
      .where(inArray(transactions.transferGroupId, groupIds));

    const byGroup = new Map<
      string,
      Array<{
        id: string;
        accountId: string;
        spaceId: string | null;
        archived: boolean;
        routedFromTxId: string | null;
      }>
    >();
    for (const m of members) {
      if (!m.groupId) continue;
      if (!byGroup.has(m.groupId)) byGroup.set(m.groupId, []);
      byGroup.get(m.groupId)!.push({
        id: m.id,
        accountId: m.accountId,
        spaceId: m.spaceId,
        archived: m.archived ?? false,
        routedFromTxId: m.routedFromTxId,
      });
    }

    const txsToUnflag: string[] = [];
    const orphansToReset: string[] = [];
    for (const [, group] of byGroup) {
      const spaces = new Set(group.map((g) => g.spaceId));
      const anyBad = group.some((g) => g.archived);
      const hasMirror = group.some((g) => g.routedFromTxId != null);
      if (spaces.size > 1 || anyBad) {
        for (const m of group) txsToUnflag.push(m.id);
        result.groupsBroken += 1;
        continue;
      }
      if (group.length < 2 && !hasMirror) {
        for (const m of group) orphansToReset.push(m.id);
        result.orphansFixed += 1;
      }
    }

    if (txsToUnflag.length > 0) {
      const unflagged = await db
        .update(transactions)
        .set({ isTransfer: false, transferGroupId: null })
        .where(inArray(transactions.id, txsToUnflag))
        .returning({ id: transactions.id });
      result.txsUnflagged += unflagged.length;
    }
    if (orphansToReset.length > 0) {
      const reset = await db
        .update(transactions)
        .set({ isTransfer: false, transferGroupId: null })
        .where(inArray(transactions.id, orphansToReset))
        .returning({ id: transactions.id });
      result.txsUnflagged += reset.length;
    }
  }

  const sourceTx = alias(transactions, "source_tx");
  const sourceAcc = alias(accounts, "source_acc");
  const mirrorConditions = [isNotNull(transactions.routedFromTxId)];
  if (opts.accountId) {
    mirrorConditions.push(
      or(
        eq(transactions.accountId, opts.accountId),
        eq(sourceTx.accountId, opts.accountId),
      )!,
    );
  }

  const mirrors = await db
    .select({
      mirrorId: transactions.id,
      sourceId: sourceTx.id,
      mirrorSpace: accounts.spaceId,
      mirrorArchived: accounts.archived,
      sourceSpace: sourceAcc.spaceId,
      sourceArchived: sourceAcc.archived,
    })
    .from(transactions)
    .leftJoin(accounts, eq(transactions.accountId, accounts.id))
    .leftJoin(sourceTx, eq(sourceTx.id, transactions.routedFromTxId))
    .leftJoin(sourceAcc, eq(sourceAcc.id, sourceTx.accountId))
    .where(and(...mirrorConditions));

  const mirrorIdsToDelete: string[] = [];
  const sourceIdsToReset: string[] = [];
  for (const m of mirrors) {
    if (!m.sourceId) continue;
    const mirrorAcc = {
      excluded: false,
      archived: m.mirrorArchived ?? false,
    };
    const srcAcc = {
      excluded: false,
      archived: m.sourceArchived ?? false,
    };
    const crossSpace = m.mirrorSpace !== m.sourceSpace;
    if (crossSpace || !isUsableForTransfers(mirrorAcc) || !isUsableForTransfers(srcAcc)) {
      mirrorIdsToDelete.push(m.mirrorId);
      sourceIdsToReset.push(m.sourceId);
    }
  }

  if (mirrorIdsToDelete.length > 0) {
    const deleted = await db
      .delete(transactions)
      .where(inArray(transactions.id, mirrorIdsToDelete))
      .returning({ id: transactions.id });
    result.mirrorsDeleted += deleted.length;
    await db
      .update(transactions)
      .set({ isTransfer: false, transferGroupId: null })
      .where(inArray(transactions.id, sourceIdsToReset));
  }

  return result;
}
