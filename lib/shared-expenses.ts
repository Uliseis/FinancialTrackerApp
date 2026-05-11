import { and, eq, gte, inArray, isNull, lte, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  sharedExpenseGroups,
  transactions,
  type SharedExpenseGroup,
  type Transaction,
} from "@/db/schema";
import { monthStart } from "@/lib/utils";

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

function withinWindow(a: Date, b: Date): boolean {
  return Math.abs(a.getTime() - b.getTime()) <= REIMBURSEMENT_WINDOW_DAYS * 86_400_000;
}

function getPrimaryAmount(p: Transaction): number {
  if (p.amountEur == null) {
    throw new SharedExpenseError("primary has no EUR amount yet — try again after FX backfill");
  }
  return Math.abs(Number(p.amountEur));
}

function validateReimbursement(r: Transaction, primary: Transaction): number {
  if (r.direction !== "credit") {
    throw new SharedExpenseError(`tx ${r.id} is not a credit`);
  }
  if (r.isTransfer) {
    throw new SharedExpenseError(`tx ${r.id} is marked as transfer`);
  }
  if (r.sharedExpenseGroupId) {
    throw new SharedExpenseError(`tx ${r.id} already in a group`, 409);
  }
  if (!withinWindow(r.bookedAt, primary.bookedAt)) {
    throw new SharedExpenseError(
      `tx ${r.id} is outside the ±${REIMBURSEMENT_WINDOW_DAYS}-day window`,
    );
  }
  if (r.amountEur == null) {
    throw new SharedExpenseError(`tx ${r.id} has no EUR amount yet`);
  }
  return Math.abs(Number(r.amountEur));
}

function assertWithinPrimary(total: number, primaryAmount: number): void {
  if (total > primaryAmount + 0.001) {
    throw new SharedExpenseError(
      `reimbursements (€${total.toFixed(2)}) exceed primary (€${primaryAmount.toFixed(2)})`,
    );
  }
}

async function loadTxOrThrow(id: string, label: string): Promise<Transaction> {
  const [row] = await db.select().from(transactions).where(eq(transactions.id, id)).limit(1);
  if (!row) throw new SharedExpenseError(`${label} not found`, 404);
  return row;
}

async function loadTxsOrThrow(ids: string[]): Promise<Transaction[]> {
  if (ids.length === 0) return [];
  const rows = await db.select().from(transactions).where(inArray(transactions.id, ids));
  if (rows.length !== ids.length) {
    throw new SharedExpenseError("one or more transactions not found", 404);
  }
  return rows;
}

async function loadGroupOrThrow(id: string): Promise<SharedExpenseGroup> {
  const [row] = await db
    .select()
    .from(sharedExpenseGroups)
    .where(eq(sharedExpenseGroups.id, id))
    .limit(1);
  if (!row) throw new SharedExpenseError("group not found", 404);
  return row;
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

  const [primary, reimbursements] = await Promise.all([
    loadTxOrThrow(input.primaryTxId, "primary"),
    loadTxsOrThrow(input.reimbursementTxIds),
  ]);
  if (primary.direction !== "debit") throw new SharedExpenseError("primary must be a debit");
  if (primary.isTransfer) throw new SharedExpenseError("primary is marked as transfer");
  if (primary.sharedExpenseGroupId) {
    throw new SharedExpenseError("primary already belongs to a shared expense", 409);
  }
  const primaryAmount = getPrimaryAmount(primary);

  let reimbursedTotal = 0;
  for (const r of reimbursements) {
    reimbursedTotal += validateReimbursement(r, primary);
  }
  assertWithinPrimary(reimbursedTotal, primaryAmount);

  const [group] = await db
    .insert(sharedExpenseGroups)
    .values({
      label,
      primaryTxId: primary.id,
      attributionMonth: monthStart(primary.bookedAt).toISOString().slice(0, 10),
    })
    .returning();

  const memberIds = [primary.id, ...reimbursements.map((r) => r.id)];
  await db
    .update(transactions)
    .set({ sharedExpenseGroupId: group.id })
    .where(inArray(transactions.id, memberIds));

  return group;
}

export async function addReimbursements(groupId: string, txIds: string[]): Promise<void> {
  if (txIds.length === 0) return;

  const group = await loadGroupOrThrow(groupId);
  const [primary, candidates, existingMembers] = await Promise.all([
    loadTxOrThrow(group.primaryTxId, "primary"),
    loadTxsOrThrow(txIds),
    db
      .select({ amountEur: transactions.amountEur, id: transactions.id })
      .from(transactions)
      .where(eq(transactions.sharedExpenseGroupId, groupId)),
  ]);
  const primaryAmount = getPrimaryAmount(primary);

  let total = 0;
  for (const m of existingMembers) {
    if (m.id === primary.id) continue;
    total += m.amountEur ? Math.abs(Number(m.amountEur)) : 0;
  }
  for (const r of candidates) {
    total += validateReimbursement(r, primary);
  }
  assertWithinPrimary(total, primaryAmount);

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
  const group = await loadGroupOrThrow(groupId);
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

export interface GroupSummary extends GroupNet {
  id: string;
  label: string;
  primaryTxId: string;
}

export async function netForGroups(ids: string[]): Promise<Map<string, GroupSummary>> {
  if (ids.length === 0) return new Map();
  const [groups, members] = await Promise.all([
    db.select().from(sharedExpenseGroups).where(inArray(sharedExpenseGroups.id, ids)),
    db
      .select({
        groupId: transactions.sharedExpenseGroupId,
        id: transactions.id,
        amountEur: transactions.amountEur,
      })
      .from(transactions)
      .where(inArray(transactions.sharedExpenseGroupId, ids)),
  ]);

  const out = new Map<string, GroupSummary>();
  for (const g of groups) {
    out.set(g.id, {
      id: g.id,
      label: g.label,
      primaryTxId: g.primaryTxId,
      gross: 0,
      reimbursed: 0,
      net: 0,
    });
  }
  for (const m of members) {
    if (!m.groupId) continue;
    const bucket = out.get(m.groupId);
    if (!bucket) continue;
    const eur = m.amountEur ? Math.abs(Number(m.amountEur)) : 0;
    if (m.id === bucket.primaryTxId) bucket.gross = eur;
    else bucket.reimbursed += eur;
  }
  for (const g of out.values()) {
    g.net = g.gross - g.reimbursed;
  }
  return out;
}

export async function netForGroup(groupId: string): Promise<GroupNet> {
  const group = await loadGroupOrThrow(groupId);
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
  const primary = await loadTxOrThrow(primaryTxId, "primary");
  const windowMs = REIMBURSEMENT_WINDOW_DAYS * 86_400_000;
  const windowStart = new Date(primary.bookedAt.getTime() - windowMs);
  const windowEnd = new Date(primary.bookedAt.getTime() + windowMs);

  const baseFilters = and(
    eq(transactions.direction, "credit"),
    eq(transactions.isTransfer, false),
    isNull(transactions.sharedExpenseGroupId),
    gte(transactions.bookedAt, windowStart),
    lte(transactions.bookedAt, windowEnd),
  );
  const needle = "%" + query.toLowerCase() + "%";
  const filters = query
    ? and(
        baseFilters,
        sql`(lower(coalesce(${transactions.counterparty}, '')) like ${needle}
            or lower(coalesce(${transactions.description}, '')) like ${needle})`,
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
