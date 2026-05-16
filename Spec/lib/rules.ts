export const RULE_FIELDS = ["description", "counterparty"] as const;
export const RULE_MATCH_TYPES = [
  "contains",
  "equals",
  "startsWith",
  "endsWith",
  "regex",
] as const;

export type RuleField = (typeof RULE_FIELDS)[number];
export type RuleMatch = (typeof RULE_MATCH_TYPES)[number];
