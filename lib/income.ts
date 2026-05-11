import type { Category, Transaction } from "@/db/schema";

export const INCOME_KIND = "income" as const;
export const EXPENSE_KIND = "expense" as const;
export const REIMBURSEMENT_KIND = "reimbursement" as const;
export const REFUND_KIND = "refund" as const;

export const CATEGORY_KINDS = [
  EXPENSE_KIND,
  INCOME_KIND,
  REIMBURSEMENT_KIND,
  REFUND_KIND,
] as const;

export type CategoryKind = (typeof CATEGORY_KINDS)[number];

export function isIncomeCredit(
  tx: Pick<Transaction, "direction" | "isTransfer" | "sharedExpenseGroupId" | "categoryId">,
  category: Pick<Category, "kind"> | null | undefined,
): boolean {
  if (tx.direction !== "credit") return false;
  if (tx.isTransfer) return false;
  if (tx.sharedExpenseGroupId) return false;
  if (!tx.categoryId) return true;
  return category?.kind === INCOME_KIND;
}
