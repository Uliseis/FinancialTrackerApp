import Foundation
import SwiftData
import CoreModel

extension CoreLogic {
    // Ports lib/budgets.ts. A budget recurs from `startsOn` by its period; `periodAt`
    // finds the active window containing `at`, and progress is the abs sum of debit
    // amountEur in that window for the budget's category (transfers excluded).
    public enum Budgets {
        public struct PeriodRange: Equatable, Sendable {
            public let start: Date
            public let end: Date
        }

        public struct Progress: Equatable, Sendable {
            public let budgetId: UUID
            public let categoryId: UUID?
            public let amountEur: Decimal
            public let period: BudgetPeriod
            public let range: PeriodRange
            public let spentEur: Decimal
        }

        public static func addPeriods(_ anchor: Date, _ period: BudgetPeriod, _ count: Int) -> Date {
            var cal = Calendar(identifier: .iso8601)
            cal.timeZone = TimeZone(identifier: "UTC")!
            switch period {
            case .week:
                return cal.date(byAdding: .day, value: count * 7, to: anchor) ?? anchor
            case .month:
                return cal.date(byAdding: .month, value: count, to: anchor) ?? anchor
            case .year:
                return cal.date(byAdding: .year, value: count, to: anchor) ?? anchor
            }
        }

        public static func periodAt(startsOn anchor: Date, period: BudgetPeriod, at: Date) -> PeriodRange {
            if at < anchor {
                return PeriodRange(start: anchor, end: addPeriods(anchor, period, 1))
            }
            var lo = 0
            var hi = 1
            while addPeriods(anchor, period, hi) <= at {
                lo = hi
                hi *= 2
                if hi > 10_000 { break }
            }
            while lo + 1 < hi {
                let mid = (lo + hi) / 2
                if addPeriods(anchor, period, mid) <= at { lo = mid } else { hi = mid }
            }
            return PeriodRange(
                start: addPeriods(anchor, period, lo),
                end: addPeriods(anchor, period, lo + 1)
            )
        }

        @MainActor
        public static func budgetProgress(
            _ budget: Budget,
            at: Date,
            in ctx: ModelContext
        ) throws -> Progress {
            let range = periodAt(startsOn: budget.startsOn, period: budget.period, at: at)
            var spent: Decimal = 0
            if let catId = budget.category?.id {
                let start = range.start
                let end = range.end
                let txs = try ctx.fetch(FetchDescriptor<Transaction>(
                    predicate: #Predicate { tx in
                        tx.category?.id == catId &&
                        tx.isTransfer == false &&
                        tx.bookedAt >= start &&
                        tx.bookedAt < end
                    }
                ))
                for tx in txs where tx.direction == .debit {
                    spent += tx.amountEur ?? 0
                }
            }
            return Progress(
                budgetId: budget.id,
                categoryId: budget.category?.id,
                amountEur: budget.amountEur,
                period: budget.period,
                range: range,
                spentEur: abs(spent)
            )
        }

        @MainActor
        public static func activeBudgetsProgress(
            at: Date,
            in ctx: ModelContext
        ) throws -> [Progress] {
            let budgets = try ctx.fetch(FetchDescriptor<Budget>(
                predicate: #Predicate { $0.active == true }
            ))
            return try budgets.map { try budgetProgress($0, at: at, in: ctx) }
        }
    }
}
