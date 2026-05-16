import { and, eq, gte, lt, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import { budgets, transactions, type Budget } from "@/db/schema";

export type Period = "week" | "month" | "year";
export interface PeriodRange {
  start: Date;
  end: Date;
}

function parseAnchor(startsOn: string | Date): Date {
  if (startsOn instanceof Date) return startsOn;
  const d = new Date(startsOn + "T00:00:00Z");
  return d;
}

function addPeriods(anchor: Date, period: Period, count: number): Date {
  const d = new Date(anchor);
  if (period === "week") {
    d.setUTCDate(d.getUTCDate() + count * 7);
  } else if (period === "month") {
    d.setUTCMonth(d.getUTCMonth() + count);
  } else {
    d.setUTCFullYear(d.getUTCFullYear() + count);
  }
  return d;
}

export function periodAt(
  startsOn: string | Date,
  period: Period,
  at: Date,
): PeriodRange {
  const anchor = parseAnchor(startsOn);
  if (at < anchor) {
    return { start: anchor, end: addPeriods(anchor, period, 1) };
  }
  let lo = 0;
  let hi = 1;
  while (addPeriods(anchor, period, hi) <= at) {
    lo = hi;
    hi *= 2;
    if (hi > 10_000) break;
  }
  while (lo + 1 < hi) {
    const mid = Math.floor((lo + hi) / 2);
    if (addPeriods(anchor, period, mid) <= at) lo = mid;
    else hi = mid;
  }
  return {
    start: addPeriods(anchor, period, lo),
    end: addPeriods(anchor, period, lo + 1),
  };
}

export interface BudgetProgress {
  budget: Budget;
  period: PeriodRange;
  spentEur: number;
}

export async function budgetProgress(budget: Budget, at: Date = new Date()): Promise<BudgetProgress> {
  const range = periodAt(budget.startsOn, budget.period as Period, at);
  const [{ total }] = await db
    .select({
      total: sql<string>`coalesce(sum(${transactions.amountEur}), 0)`,
    })
    .from(transactions)
    .where(
      and(
        eq(transactions.categoryId, budget.categoryId),
        eq(transactions.isTransfer, false),
        eq(transactions.direction, "debit"),
        gte(transactions.bookedAt, range.start),
        lt(transactions.bookedAt, range.end),
      ),
    );
  const spentEur = Math.abs(Number(total ?? "0"));
  return { budget, period: range, spentEur };
}

export async function activeBudgetsProgress(at: Date = new Date()): Promise<BudgetProgress[]> {
  const rows = await db.select().from(budgets).where(eq(budgets.active, true));
  return Promise.all(rows.map((b) => budgetProgress(b, at)));
}
