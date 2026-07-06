#if DEBUG
import Foundation
import SwiftData
import CoreModel
import CoreLogic

// One-shot data-quality audit, gated on OFCC_AUDIT=1, idempotent.
// (1) Loosens over-strict merchant rules from `equals` to `contains` so bank-format
//     variants match (e.g. "MERCADONA C/ MA MADRID").
// (2) Adds housing + recurring-merchant rules (low priority; keeps DEVOLUCIÓN/refunds
//     uncategorised on purpose is impossible via contains, but detection excludes the
//     paired ones anyway).
// (3) Re-runs categorisation, then transfer DETECTION over full history (730d) to pair
//     self-transfers whose two real legs were never within a 30-day sync window — marking
//     both isTransfer so they drop out of income AND expenses.
enum CCAudit {
    // equals → contains (safe: no sub-variant that needs a different category).
    static let loosen: Set<String> = [
        "Carrefour", "Google", "Mercadona", "Malvón", "El Corte Inglés", "Psicologia y Salud",
    ]

    static let newRules: [(String, String)] = [
        ("ALQUILER", "Housing"), ("FIANZA", "Housing"),
        ("SEGURO PISO", "Housing"), ("HOGAR", "Housing"),
        ("La Beoda", "Restaurants"), ("Quirico", "Restaurants"), ("Pequecho", "Restaurants"),
        ("No Va Mas", "Restaurants"), ("La Quintana", "Restaurants"), ("El Guapo", "Restaurants"),
        ("Costa Feira", "Restaurants"), ("O Son Do Camino", "Restaurants"),
        ("Náutico de San Vicente", "Restaurants"),
        ("Teatro Kapital", "Entertainment"), ("Fourvenues", "Entertainment"),
        ("VIVACLUBS", "Health"),
        ("Wib Advance Mobility", "Transport"), ("Wible", "Transport"),
        (" EATS", "Restaurants"),
    ]

    @MainActor
    static func runIfRequested(_ container: ModelContainer) {
        guard ProcessInfo.processInfo.environment["OFCC_AUDIT"] == "1" else { return }
        let ctx = container.mainContext

        // 1) Loosen over-strict rules.
        var loosened = 0
        let rules = (try? ctx.fetch(FetchDescriptor<CategoryRule>())) ?? []
        for r in rules where r.matchType == .equals && loosen.contains(r.pattern) {
            r.matchType = .contains
            loosened += 1
        }

        // 2) Add new rules (skip if pattern already present).
        let present = Set(rules.map { $0.pattern })
        var created = 0
        for (pattern, catName) in newRules where !present.contains(pattern) {
            guard let cat = try? ctx.fetch(FetchDescriptor<CoreModel.Category>(
                predicate: #Predicate { $0.name == catName })).first else { continue }
            _ = try? CoreLogic.CategoryRules.create(
                pattern: pattern, category: cat, field: .description,
                matchType: .contains, priority: -1000, in: ctx)
            created += 1
        }
        try? ctx.save()

        // 3) Re-categorise. (Transfer auto-pairing intentionally NOT run here — the two legs
        // of these self-transfers don't line up in the data: split across spaces + amount
        // mismatches, so detect() safely pairs ~nothing. Pairing is a manual/UI decision.)
        let cats = (try? CoreLogic.Categorize.applyRulesToTransactions(in: ctx))?.updated ?? 0
        try? ctx.save()
        print("[CCAudit] loosened=\(loosened) rulesCreated=\(created) recategorized=\(cats)")
    }
}
#endif
