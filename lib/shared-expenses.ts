import { and, eq, gte, inArray, isNull, lte, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  sharedExpenseGroups,
  transactions,
  type SharedExpenseGroup,
} from "@/db/schema";

const REIMBURSEMENT_WINDOW_DAYS = 60;

export interface CreateSharedExpenseInput {
  label: string;
  primaryTxId: string;
  reimbursementTxIds: string[];
}

export interface GroupNet {
  gross: number;
  reimbursed: number;
  net: number;
}

export class SharedExpenseError extends Error {
  status: number;
  constructor(message: string, status = 400) {
    super(message);
    this.status = status;
  }
}

function toMonthStart(d: Date): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1));
}

function withinWindow(a: Date, b: Date): boolean {
  return Math.abs(a.getTime() - b.getTime()) <= REIMBURSEMENT_WINDOW_DAYS * 86_400_000;
}

export async function createSharedExpenseGroup(
  input: CreateSharedExpenseInput,
): Promise<SharedExpenseGroup> {
  const label = input.label.trim();
  if (!label) throw new SharedExpenseError("label required");
  if (input.reimbursementTxIds.length === 0) {
    throw new SharedExpenseError("at least one reimbursement is required");
  }
  if (new Set(input.reimbursementTxIds).has(input.primaryTxId)) {
    throw new SharedExpenseError("primary cannot also be a reimbursement");
  }

  const primary = await db
    .select()
    .from(transactions)
    .where(eq(transactions.id, input.primaryTxId))
    .limit(1);
  if (primary.length === 0) throw new SharedExpenseError("primary not found", 404);
  const p = primary[0];
  if (p.direction !== "debit") throw new SharedExpenseError("primary must be a debit");
  if (p.isTransfer) throw new SharedExpenseError("primary is marked as transfer");
  if (p.sharedExpenseGroupId) {
    throw new SharedExpenseError("primary already belongs to a shared expense", 409);
  }
  const primaryAmount = p.amountEur ? Math.abs(Number(p.amountEur)) : null;
  if (primaryAmount == null) {
    throw new SharedExpenseError("primary has no EUR amount yet — try again after FX backfill");
  }

  const reimbursements = await db
    .select()
    .from(transactions)
    .where(inArray(transactions.id, input.reimbursementTxIds));
  if (reimbursements.length !== input.reimbursementTxIds.length) {
    throw new SharedExpenseError("one or more reimbursements not found", 404);
  }
  let reimbursedTotal = 0;
  for (const r of reimbursements) {
    if (r.direction !== "credit") {
      throw new SharedExpenseError(`reimbursement ${r.id} is not a credit`);
    }
    if (r.isTransfer) {
      throw new SharedExpenseError(`reimbursement ${r.id} is marked as transfer`);
    }
    if (r.sharedExpenseGroupId) {
      throw new SharedExpenseError(`reimbursement ${r.id} already in a group`, 409);
    }
    if (!withinWindow(r.bookedAt, p.bookedAt)) {
      throw new SharedExpenseError(
        `reimbursement ${r.id} is outside the ±${REIMBURSEMENT_WINDOW_DAYS}-day window`,
      );
    }
    if (r.amountEur == null) {
      throw new SharedExpenseError(`reimbursement ${r.id} has no EUR amount yet`);
    }
    reimbursedTotal += Math.abs(Number(r.amountEur));
  }
  if (reimbursedTotal > primaryAmount + 0.001) {
    throw new SharedExpenseError(
      `reimbursements (€${reimbursedTotal.toFixed(2)}) exceed the primary (€${primaryAmount.toFixed(2)})`,
    );
  }

  const attributionMonth = toMonthStart(p.bookedAt);
  const inserted = await db
    .insert(sharedExpenseGroups)
    .values({
      label,
      primaryTxId: p.id,
      attributionMonth: attributionMonth.toISOString().slice(0, 10),
    })
    .returning();
  const group = inserted[0];

  const memberIds = [p.id, ...reimbursements.map((r) => r.id)];
  await db
    .update(transactions)
    .set({ sharedExpenseGroupId: group.id })
    .where(inArray(transactions.id, memberIds));

  return group;
}

export async function addReimbursements(
  groupId: string,
  txIds: string[],
): Promise<void> {
  if (txIds.length === 0) return;
  const groupRows = await db
    .select()
    .from(sharedExpenseGroups)
    .where(eq(sharedExpenseGroups.id, groupId))
    .limit(1);
  if (groupRows.length === 0) throw new SharedExpenseError("group not found", 404);
  const group = groupRows[0];

  const primary = await db
    .select()
    .from(transactions)
    .where(eq(transactions.id, group.primaryTxId))
    .limit(1);
  if (primary.length === 0) throw new SharedExpenseError("primary not found", 404);
  const p = primary[0];
  const primaryAmount = p.amountEur ? Math.abs(Number(p.amountEur)) : 0;

  const candidates = await db
    .select()
    .from(transactions)
    .where(inArray(transactions.id, txIds));
  if (candidates.length !== txIds.length) {
    throw new SharedExpenseError("one or more reimbursements not found", 404);
  }
  let alreadyReimbursed = 0;
  const existingMembers = await db
    .select({ amountEur: transactions.amountEur, id: transactions.id })
    .from(transactions)
    .where(eq(transactions.sharedExpenseGroupId, groupId));
  for (const m of existingMembers) {
    if (m.id === p.id) continue;
    alreadyReimbursed += m.amountEur ? Math.abs(Number(m.amountEur)) : 0;
  }
  for (const r of candidates) {
    if (r.direction !== "credit") {
      throw new SharedExpenseError(`tx ${r.id} is not a credit`);
    }
    if (r.isTransfer) {
      throw new SharedExpenseError(`tx ${r.id} is marked as transfer`);
    }
    if (r.sharedExpenseGroupId) {
      throw new SharedExpenseError(`tx ${r.id} already in a group`, 409);
    }
    if (!withinWindow(r.bookedAt, p.bookedAt)) {
      throw new SharedExpenseError(`tx ${r.id} is outside the ±${REIMBURSEMENT_WINDOW_DAYS}-day window`);
    }
    if (r.amountEur == null) {
      throw new SharedExpenseError(`tx ${r.id} has no EUR amount yet`);
    }
    alreadyReimbursed += Math.abs(Number(r.amountEur));
  }
  if (alreadyReimbursed > primaryAmount + 0.001) {
    throw new SharedExpenseError(
      `reimbursements (€${alreadyReimbursed.toFixed(2)}) exceed primary (€${primaryAmount.toFixed(2)})`,
    );
  }

  await db
    .update(transactions)
    .set({ sharedExpenseGroupId: groupId })
    .where(inArray(transactions.id, txIds));
  await db
    .update(sharedExpenseGroups)
    .set({ updatedAt: new Date() })
    .where(eq(sharedExpenseGroups.id, groupId));
}

export async function removeReimbursement(groupId: string, txId: string): Promise<void> {
  const groupRows = await db
    .select()
    .from(sharedExpenseGroups)
    .where(eq(sharedExpenseGroups.id, groupId))
    .limit(1);
  if (groupRows.length === 0) throw new SharedExpenseError("group not found", 404);
  const group = groupRows[0];
  if (group.primaryTxId === txId) {
    throw new SharedExpenseError("cannot remove the primary — delete the group instead");
  }
  await db
    .update(transactions)
    .set({ sharedExpenseGroupId: null })
    .where(and(eq(transactions.id, txId), eq(transactions.sharedExpenseGroupId, groupId)));
  await db
    .update(sharedExpenseGroups)
    .set({ updatedAt: new Date() })
    .where(eq(sharedExpenseGroups.id, groupId));
}

export async function deleteSharedExpenseGroup(groupId: string): Promise<void> {
  await db
    .update(transactions)
    .set({ sharedExpenseGroupId: null })
    .where(eq(transactions.sharedExpenseGroupId, groupId));
  await db.delete(sharedExpenseGroups).where(eq(sharedExpenseGroups.id, groupId));
}

export async function netForGroup(groupId: string): Promise<GroupNet> {
  const groupRows = await db
    .select()
    .from(sharedExpenseGroups)
    .where(eq(sharedExpenseGroups.id, groupId))
    .limit(1);
  if (groupRows.length === 0) throw new SharedExpenseError("group not found", 404);
  const group = groupRows[0];

  const members = await db
    .select({
      id: transactions.id,
      direction: transactions.direction,
      amountEur: transactions.amountEur,
    })
    .from(transactions)
    .where(eq(transactions.sharedExpenseGroupId, groupId));

  let gross = 0;
  let reimbursed = 0;
  for (const m of members) {
    const eur = m.amountEur ? Math.abs(Number(m.amountEur)) : 0;
    if (m.id === group.primaryTxId) gross = eur;
    else reimbursed += eur;
  }
  return { gross, reimbursed, net: gross - reimbursed };
}

export async function findCandidateReimbursements(
  primaryTxId: string,
  query: string,
): Promise<
  Array<{
    id: string;
    bookedAt: Date;
    amountEur: string | null;
    counterparty: string | null;
    description: string | null;
    accountId: string;
  }>
> {
  const primary = await db
    .select()
    .from(transactions)
    .where(eq(transactions.id, primaryTxId))
    .limit(1);
  if (primary.length === 0) throw new SharedExpenseError("primary not found", 404);
  const p = primary[0];
  const windowStart = new Date(p.bookedAt.getTime() - REIMBURSEMENT_WINDOW_DAYS * 86_400_000);
  const windowEnd = new Date(p.bookedAt.getTime() + REIMBURSEMENT_WINDOW_DAYS * 86_400_000);

  const baseFilters = and(
    eq(transactions.direction, "credit"),
    eq(transactions.isTransfer, false),
    isNull(transactions.sharedExpenseGroupId),
    gte(transactions.bookedAt, windowStart),
    lte(transactions.bookedAt, windowEnd),
  );
  const filters = query
    ? and(
        baseFilters,
        sql`(lower(coalesce(${transactions.counterparty}, '')) like ${"%" + query.toLowerCase() + "%"}
            or lower(coalesce(${transactions.description}, '')) like ${"%" + query.toLowerCase() + "%"})`,
      )
    : baseFilters;

  return db
    .select({
      id: transactions.id,
      bookedAt: transactions.bookedAt,
      amountEur: transactions.amountEur,
      counterparty: transactions.counterparty,
      description: transactions.description,
      accountId: transactions.accountId,
    })
    .from(transactions)
    .where(filters)
    .orderBy(sql`${transactions.bookedAt} desc`)
    .limit(50);
}
