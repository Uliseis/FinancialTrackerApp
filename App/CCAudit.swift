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

        // 3) Re-categorise. (General transfer auto-pairing intentionally NOT run — most
        // self-transfer legs don't line up in the data, so detect() safely pairs ~nothing.)
        let cats = (try? CoreLogic.Categorize.applyRulesToTransactions(in: ctx))?.updated ?? 0

        // 4) Safe route: "Savings Vault topup" (defunct Revolut vault) is provably one-legged
        // (17 debits on main Revolut, no matching credit) and all pre-date the savings anchor,
        // so mirrors land pre-anchor and don't disturb the (correct) savings balance. Routing
        // marks the topups as transfers → out of expenses. Guarded so it's created once.
        let vaultId = UUID(uuidString: "7C65A2D3-E137-43C8-B5BB-C4658AD81B45")! // Revolut Savings (Instant Access)
        let vaultPattern = "Savings Vault topup"
        let already = ((try? ctx.fetchCount(FetchDescriptor<TransferRoute>(
            predicate: #Predicate { $0.pattern == vaultPattern }))) ?? 0) > 0
        let savings = (try? ctx.fetch(FetchDescriptor<Account>(
            predicate: #Predicate { $0.id == vaultId })))?.first
        if !already, let savings {
            _ = try? CoreLogic.TransferRoutes.createRoute(
                pattern: vaultPattern, target: savings, field: .description,
                matchType: .contains, direction: .debit, in: ctx)
        }
        try? ctx.save()
        print("[CCAudit] loosened=\(loosened) rulesCreated=\(created) recategorized=\(cats) vaultRoute=\(!already)")
    }
}
#endif
