/**
 * Named predicates for `accounts.archived` / `accounts.excluded`.
 *
 * Why this module exists: those two flags have very different meanings, and
 * conflating them caused a real production regression (the May-16 2026 sync
 * deleted 280 transfer-route mirrors because `repairTransferGroups` treated
 * `excluded` as "broken"). Use these predicates in any in-memory code path
 * that needs to gate on account state.
 *
 * Semantics:
 *   archived = the account is dead. No reads, no writes, no transfer pairing.
 *   excluded = the account is alive but off cash net-worth (used today on
 *              the 5 investment accounts and on the roommate's Abanca account
 *              so they don't double-count). Transfer pairs and routes
 *              targeting these accounts are still valid.
 */
export interface AccountStatusFields {
  archived: boolean;
  excluded: boolean;
}

/**
 * True when this account can be a leg in a transfer pair or the target of a
 * transfer route. `excluded` does NOT disqualify — the user keeps tracking
 * the flows, just hides them from the cash net-worth roll-up.
 */
export function isUsableForTransfers(
  a: AccountStatusFields | null | undefined,
): boolean {
  return !!a && !a.archived;
}

/**
 * True when this account's balance contributes to the dashboard's cash
 * net-worth total. Both flags disqualify. Investment-kind groups are also
 * excluded from cash net worth, but that's enforced in the dashboard at the
 * group-kind level, not on this predicate.
 */
export function isCountedInCashNetWorth(
  a: AccountStatusFields | null | undefined,
): boolean {
  return !!a && !a.archived && !a.excluded;
}
