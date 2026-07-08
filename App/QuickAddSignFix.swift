#if DEBUG
import Foundation
import SwiftData
import CoreModel

// One-shot, gated on OFQA_SIGNFIX=1. Idempotent. Corrects quick-add debits (externalId
// "manual-tx:") that were stored with a POSITIVE amount before the signed-amount fix — flips
// amount/amountEur negative so they read as expenses. Saves via mainContext → SaveObserver push.
enum QuickAddSignFix {
    @MainActor
    static func runIfRequested(_ container: ModelContainer) {
        guard ProcessInfo.processInfo.environment["OFQA_SIGNFIX"] == "1" else { return }
        let ctx = container.mainContext
        let rows = (try? ctx.fetch(FetchDescriptor<Transaction>())) ?? []
        var fixed = 0
        for tx in rows where tx.externalId.hasPrefix("manual-tx:")
            && tx.direction == .debit && tx.amount > 0 {
            tx.amount = -tx.amount
            if let eur = tx.amountEur, eur > 0 { tx.amountEur = -eur }
            fixed += 1
        }
        try? ctx.save()
        print("[QASignFix] corrected \(fixed) manual-tx debit(s)")
    }
}
#endif
