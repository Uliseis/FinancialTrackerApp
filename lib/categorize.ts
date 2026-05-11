import { and, eq, inArray, isNull, ne, or, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  categoryRules,
  transactions,
  type CategoryRule,
  type Transaction,
} from "@/db/schema";
import type { RuleField, RuleMatch } from "@/lib/rules";

function matches(rule: CategoryRule, tx: Pick<Transaction, "description" | "counterparty">): boolean {
  const field = (rule.field as RuleField) ?? "description";
  const haystack = (field === "counterparty" ? tx.counterparty : tx.description) ?? "";
  const needle = rule.pattern;
  const kind = (rule.matchType as RuleMatch) ?? "contains";
  if (!needle) return false;
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

export async function applyRulesToTransactions(
  txIds?: string[],
): Promise<{ updated: number; scanned: number }> {
  const rules = await db
    .select()
    .from(categoryRules)
    .orderBy(sql`${categoryRules.priority} desc`);
  if (rules.length === 0) return { updated: 0, scanned: 0 };

  const skipManual = ne(transactions.categorySource, "manual");
  const allowMissingSource = isNull(transactions.categorySource);
  const baseFilter = or(skipManual, allowMissingSource);

  const where = txIds && txIds.length > 0
    ? and(inArray(transactions.id, txIds), baseFilter)
    : baseFilter;

  const rows = await db
    .select({
      id: transactions.id,
      description: transactions.description,
      counterparty: transactions.counterparty,
      categoryId: transactions.categoryId,
      categorySource: transactions.categorySource,
    })
    .from(transactions)
    .where(where);

  let updated = 0;
  for (const tx of rows) {
    let matchedCategoryId: string | null = null;
    for (const rule of rules) {
      if (matches(rule, tx)) {
        matchedCategoryId = rule.categoryId;
        break;
      }
    }
    if (!matchedCategoryId) continue;
    if (tx.categoryId === matchedCategoryId && tx.categorySource === "rule") continue;
    await db
      .update(transactions)
      .set({ categoryId: matchedCategoryId, categorySource: "rule" })
      .where(eq(transactions.id, tx.id));
    updated++;
  }
  return { updated, scanned: rows.length };
}
