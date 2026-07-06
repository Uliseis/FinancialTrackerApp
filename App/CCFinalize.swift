#if DEBUG
import Foundation
import SwiftData
import CoreModel
import CoreLogic

// One-shot, gated on OFCC_FINALIZE=1, idempotent.
// (1) Re-anchors the Credit Card to its true current Revolut balance (−558.80 as of now),
//     since the old anchor (−732.73 @ 2026-05-12) had drifted.
// (2) Adds high-confidence category rules for recurring uncategorized merchants (low
//     priority so they never override existing rules) and re-runs categorization.
enum CCFinalize {
    static let creditCardId = UUID(uuidString: "038A3B64-DBA8-4BB3-923D-DB1B29AC1384")!

    // pattern → category name (categories already exist, used by current rules)
    static let newRules: [(String, String)] = [
        ("Amazon", "Shopping"),
        ("Iberia", "Travel"),
        ("Booking.com", "Travel"),
        ("WiBLE", "Transport"),
        ("EMT Madrid", "Transport"),
        ("Supermercado Lourdes", "Groceries"),
        ("Fruteria Lourdes", "Groceries"),
        ("Tesco", "Groceries"),
    ]

    @MainActor
    static func runIfRequested(_ container: ModelContainer) {
        guard ProcessInfo.processInfo.environment["OFCC_FINALIZE"] == "1" else { return }
        let ctx = container.mainContext
        let ccId = creditCardId

        if let cc = try? ctx.fetch(FetchDescriptor<Account>(
                predicate: #Predicate { $0.id == ccId })).first {
            try? CoreLogic.Accounts.setAnchor(cc, balance: Decimal(string: "-558.80")!, at: .now, in: ctx)
            print("[CCFinal] re-anchored CC to -558.80")
        }

        let existing = (try? ctx.fetch(FetchDescriptor<CategoryRule>())) ?? []
        let existingPatterns = Set(existing.map { $0.pattern })
        var created = 0
        for (pattern, catName) in newRules where !existingPatterns.contains(pattern) {
            guard let cat = try? ctx.fetch(FetchDescriptor<CoreModel.Category>(
                predicate: #Predicate { $0.name == catName })).first else {
                print("[CCFinal] category '\(catName)' not found; skip \(pattern)"); continue
            }
            _ = try? CoreLogic.CategoryRules.create(
                pattern: pattern, category: cat, field: .description,
                matchType: .contains, priority: -1000, in: ctx)
            created += 1
        }
        let cats = (try? CoreLogic.Categorize.applyRulesToTransactions(in: ctx))?.updated ?? 0
        print("[CCFinal] rulesCreated=\(created) recategorized=\(cats)")
        try? ctx.save()
    }
}
#endif
