#if DEBUG
import Foundation
import SwiftData
import CoreModel
import CoreLogic

// One-shot, gated on OFAUTO=1: switches both automations on the way the Settings screen
// would (recurring charges; €125 pension split from MyInvestor Investment to MyInvestor
// Pension for arrivals since 1 Aug 2026), asks for notification permission, then runs the
// automations once so the pending splits book and notify immediately.
enum AutomationBootstrap {
    @MainActor
    static func runIfRequested(_ container: ModelContainer) {
        guard ProcessInfo.processInfo.environment["OFAUTO"] == "1" else { return }
        let ctx = container.mainContext
        let accounts = (try? ctx.fetch(FetchDescriptor<Account>())) ?? []
        guard let funds = accounts.first(where: { $0.name.hasPrefix("MyInvestor Investment") }),
              let pension = accounts.first(where: { $0.name.hasPrefix("MyInvestor Pension") }) else {
            print("[OFAUTO] MyInvestor accounts not found"); return
        }
        let d = UserDefaults.standard
        d.set(true, forKey: AutomationSettings.recurringEnabledKey)
        d.set(true, forKey: AutomationSettings.pensionEnabledKey)
        d.set(funds.id.uuidString, forKey: AutomationSettings.pensionSourceKey)
        d.set(pension.id.uuidString, forKey: AutomationSettings.pensionTargetKey)
        d.set("125", forKey: AutomationSettings.pensionAmountKey)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let since = utc.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        d.set(since.timeIntervalSince1970, forKey: AutomationSettings.pensionSinceKey)
        Task { @MainActor in
            let granted = await AutomationNotifications.requestPermission()
            await AutomationRunner.run(ctx)
            print("[OFAUTO] enabled; notifications granted=\(granted); rule=\(String(describing: AutomationSettings.splitRule))")
        }
    }
}
#endif
