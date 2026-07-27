#if DEBUG
import Foundation
import SwiftData
import CoreModel
import CoreLogic

// One-shot, gated on OFPENSION_BACKFILL=1, idempotent.
//
// Money arrives at MyInvestor as one bank transfer and is then split: a fixed €125 to the
// pension wrapper, the rest into funds. Only the arrival has a bank row, and the route sends
// all of it to the investment account, so the pension's share has to be booked separately.
//
// Only splits AFTER the 13 May cost-basis opening figure are backfilled. The March and April
// contributions are already inside that figure — it was taken from the real portfolio split —
// so booking them again would count them twice.
enum PensionSplitBackfill {
    static let splits: [(day: String, amount: Decimal)] = [
        ("2026-05-26", 125),
        ("2026-06-19", 125),
    ]

    @MainActor
    static func runIfRequested(_ container: ModelContainer) {
        guard ProcessInfo.processInfo.environment["OFPENSION_BACKFILL"] == "1" else { return }
        do { try run(in: container.mainContext) } catch { print("[OFPENSION] failed: \(error)") }
    }

    @MainActor
    static func run(in ctx: ModelContext) throws {
        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        guard let funds = accounts.first(where: { $0.name.hasPrefix("MyInvestor Investment") }),
              let pension = accounts.first(where: { $0.name.contains("Pension") }) else {
            print("[OFPENSION] accounts not found")
            return
        }

        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = TimeZone(identifier: "UTC")

        let existing = pension.transactions.filter {
            $0.externalId.hasPrefix(CoreLogic.Transfers.internalPrefix)
        }

        for split in splits {
            guard let day = parser.date(from: split.day) else { continue }
            // Idempotent on (day, amount): the generated externalIds are random, so re-running
            // would otherwise double the contribution.
            let already = existing.contains {
                cal.isDate($0.bookedAt, inSameDayAs: day) && abs($0.amountEur ?? 0) == split.amount
            }
            if already {
                print("[OFPENSION] \(split.day) already booked, skipping")
                continue
            }
            try CoreLogic.Transfers.createInternalTransfer(
                from: funds, to: pension, amountEur: split.amount, bookedAt: day,
                note: "Pension contribution", in: ctx)
            print("[OFPENSION] booked \(split.amount) on \(split.day)")
        }

        for account in [funds, pension] {
            let m = try CoreLogic.Investments.loadMetrics(for: [account], in: ctx)[account.id]
            print("""
            [OFPENSION] \(account.displayName): \
            value \(m?.valueEur.map { "\($0)" } ?? "—") \
            cost \(m?.costBasisEur.map { "\($0)" } ?? "—")
            """)
        }
    }
}
#endif
