#if DEBUG
import Foundation

// DEBUG-only screenshot affordance: launch with UITEST_PRESENT=<name> to auto-open a
// management sheet for capture, since CLI automation can't tap. Parallel to UITEST_TAB
// (initial tab), UITEST_DISABLE_AUTH=1 (skip Face ID gate), UITEST_SHOW_LOCK=1.
// Pass via simctl as SIMCTL_CHILD_UITEST_PRESENT=<name>.
//
// Names — Accounts tab: spaces, space-edit, groups, group-edit, account-new,
// account-edit, anchor. Transactions tab: categories, category-edit, categorize,
// rules, rule-edit, routes, route-edit, tx-detail, tx-detail-transfer, pair-partner,
// shared, shared-detail, shared-create, budgets, budget-edit.
enum UITestHooks {
    static var presentSheet: String? {
        ProcessInfo.processInfo.environment["UITEST_PRESENT"]
    }
}
#endif
