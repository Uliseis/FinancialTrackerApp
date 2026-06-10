#if DEBUG
import Foundation

// DEBUG-only screenshot affordance: launch with UITEST_PRESENT=<name> to auto-open a
// management sheet for capture, since CLI automation can't tap. Parallel to UITEST_TAB
// (initial tab), UITEST_DISABLE_AUTH=1 (skip Face ID gate), UITEST_SHOW_LOCK=1.
// Pass via simctl as SIMCTL_CHILD_UITEST_PRESENT=<name>.
//
// Names — Accounts tab: account-new, account-edit, anchor. Transactions tab:
// categorize, tx-detail, tx-detail-transfer, pair-partner, shared-create.
// Settings tab (pushes): connections, spaces, space-edit, groups, group-edit,
// categories, category-edit, rules, rule-edit, routes, route-edit, shared,
// shared-detail, budgets, budget-edit (the *-edit variants also auto-open the
// editor sheet inside the pushed screen).
enum UITestHooks {
    static var presentSheet: String? {
        ProcessInfo.processInfo.environment["UITEST_PRESENT"]
    }
}
#endif
