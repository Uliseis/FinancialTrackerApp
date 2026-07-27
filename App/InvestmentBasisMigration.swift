#if DEBUG
import Foundation
import SwiftData
import CoreModel
import CoreLogic

// One-shot, gated on OFINV_MIGRATE=1, idempotent.
//
// The cutover seeded two rows per investment account: a "cost basis baseline" and a "today"
// market value. Both landed in PortfolioValuation, and the old maths read whichever was
// oldest as the P&L baseline — so the cost-basis row was being displayed as a market value
// and, worse, deleting it would have silently destroyed the only record of what was paid in.
//
// This moves each cost-basis row onto Account.costBasisOpeningEur/At, where contributions
// accumulate on top of it, and removes it from the valuation history.
enum InvestmentBasisMigration {
    static let marker = "seed: cost basis baseline"

    @MainActor
    static func runIfRequested(_ container: ModelContainer) {
        guard ProcessInfo.processInfo.environment["OFINV_MIGRATE"] == "1" else { return }
        let ctx = container.mainContext
        do { try run(in: ctx) } catch { print("[OFINV] failed: \(error)") }
    }

    @MainActor
    static func run(in ctx: ModelContext) throws {
        let valuations = try ctx.fetch(FetchDescriptor<PortfolioValuation>(
            sortBy: [SortDescriptor(\.asOf, order: .forward)]))

        var moved = 0
        for v in valuations {
            guard let note = v.notes, note.hasPrefix(marker), let account = v.account else {
                continue
            }
            // Never overwrite a basis the user has already set by hand.
            if account.costBasisOpeningEur == nil {
                try CoreLogic.Investments.setCostBasisOpening(
                    account, amountEur: v.marketValueEur, at: v.asOf, in: ctx)
            }
            try CoreLogic.Investments.deleteValuation(v, in: ctx)
            moved += 1
            print("[OFINV] \(account.displayName): opening basis \(v.marketValueEur) @ \(v.asOf)")
        }

        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        for account in accounts where account.costBasisOpeningEur != nil {
            let m = try CoreLogic.Investments.loadMetrics(for: [account], in: ctx)[account.id]
            print("""
            [OFINV] \(account.displayName): \
            value \(m?.valueEur.map { "\($0)" } ?? "—") \
            cost \(m?.costBasisEur.map { "\($0)" } ?? "—") \
            pnl \(m?.pnlEur.map { "\($0)" } ?? "—")
            """)
        }
        print("[OFINV] migrated \(moved) cost-basis rows")
    }
}
#endif
