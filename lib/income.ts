export const CATEGORY_KINDS = ["expense", "income", "reimbursement", "refund"] as const;

export type CategoryKind = (typeof CATEGORY_KINDS)[number];
