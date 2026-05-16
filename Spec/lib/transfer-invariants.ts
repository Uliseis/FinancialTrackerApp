import { sql } from "drizzle-orm";
import { db } from "@/lib/db";

export interface InvariantViolation {
  name: string;
  count: number;
  sampleIds: string[];
}

/**
 * Reads transfer-related shape invariants and reports any that are violated.
 * Pure observation — never mutates. Wire into the tail of any sync so a
 * regression (like the 2026-05-16 excluded-account nuke) shows up as a
 * loud sync error instead of silent data drift.
 */
export async function assertTransferInvariants(): Promise<InvariantViolation[]> {
  const violations: InvariantViolation[] = [];

  const check = async (
    name: string,
    query: ReturnType<typeof sql>,
  ): Promise<void> => {
    const rows = (await db.execute(query)).rows as Array<{ id: string }>;
    if (rows.length === 0) return;
    violations.push({
      name,
      count: rows.length,
      sampleIds: rows.slice(0, 5).map((r) => r.id),
    });
  };

  await check(
    "orphan_transfer_group",
    sql`SELECT t.id FROM transactions t
        WHERE t.transfer_group_id IS NOT NULL
          AND t.routed_from_tx_id IS NULL
          AND (SELECT count(*) FROM transactions x
               WHERE x.transfer_group_id = t.transfer_group_id) = 1
        LIMIT 25`,
  );

  await check(
    "mirror_with_unflagged_source",
    sql`SELECT m.id FROM transactions m
        JOIN transactions s ON s.id = m.routed_from_tx_id
        WHERE s.is_transfer = false
        LIMIT 25`,
  );

  await check(
    "dangling_transfer_flag",
    sql`SELECT id FROM transactions
        WHERE is_transfer = true
          AND transfer_group_id IS NULL
          AND routed_from_tx_id IS NULL
        LIMIT 25`,
  );

  await check(
    "cross_space_transfer_group",
    sql`SELECT t.id FROM transactions t
        JOIN accounts a ON a.id = t.account_id
        WHERE t.transfer_group_id IN (
          SELECT t2.transfer_group_id
          FROM transactions t2
          JOIN accounts a2 ON a2.id = t2.account_id
          WHERE t2.transfer_group_id IS NOT NULL
          GROUP BY t2.transfer_group_id
          HAVING count(DISTINCT a2.space_id) > 1
        )
        LIMIT 25`,
  );

  await check(
    "transfer_on_archived_account",
    sql`SELECT t.id FROM transactions t
        JOIN accounts a ON a.id = t.account_id
        WHERE t.is_transfer = true AND a.archived = true
        LIMIT 25`,
  );

  return violations;
}

export function formatInvariantViolations(violations: InvariantViolation[]): string {
  if (violations.length === 0) return "";
  return violations
    .map((v) => `${v.name}=${v.count}(${v.sampleIds.join(",")})`)
    .join("; ");
}
