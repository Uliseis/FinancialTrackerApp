import Foundation
import SwiftData
import CoreModel

extension CoreLogic {
    // Ports the dashboard aggregations from Spec/app/(app)/page.tsx:
    //  - monthlyCashFlow: income vs expense per month; expenses exclude transfers
    //    and shared-expense-member legs, but ADD each group's net (gross − reimbursed)
    //    via attributionMonth.
    //  - categoryBreakdown: this-month debit spend per category, same SEG treatment,
    //    net attributed to the group's primary tx category.
    public enum Dashboard {
        public struct MonthlyFlow: Equatable, Sendable {
            public let monthStart: Date
            public let income: Decimal
            public let expense: Decimal
        }

        public struct CategorySpend: Equatable, Sendable {
            public let categoryId: UUID?
            public let total: Decimal
        }

        // monthStart(d, offset) — first instant (UTC) of d's month shifted by `offset` months.
        public static func monthStart(_ date: Date, offset: Int = 0) -> Date {
            var cal = Calendar(identifier: .iso8601)
            cal.timeZone = TimeZone(identifier: "UTC")!
            let comps = cal.dateComponents([.year, .month], from: date)
            let base = cal.date(from: comps) ?? date
            return cal.date(byAdding: .month, value: offset, to: base) ?? base
        }

        public static let maxCycleStartDay = 28

        public struct Cycle: Equatable, Sendable {
            public let startDay: Int
            // Salaries due on a weekend arrive the Friday before, so the month starts then too.
            public let startsEarlyOnWeekends: Bool

            public init(startDay: Int = 1, startsEarlyOnWeekends: Bool = true) {
                self.startDay = min(max(startDay, 1), maxCycleStartDay)
                self.startsEarlyOnWeekends = startsEarlyOnWeekends
            }

            public static let calendarMonth = Cycle(startDay: 1)
        }

        private static var utc: Calendar {
            var cal = Calendar(identifier: .iso8601)
            cal.timeZone = TimeZone(identifier: "UTC")!
            return cal
        }

        // Where the budgeting month that is named after `monthIndex` (months since year 0)
        // begins. Day 1 is always the calendar month.
        static func cycleBoundary(monthIndex: Int, cycle: Cycle) -> Date {
            let cal = utc
            let year = Int((Double(monthIndex) / 12).rounded(.down))
            let month = monthIndex - year * 12 + 1
            let d = cal.date(from: DateComponents(year: year, month: month, day: cycle.startDay))!
            guard cycle.startDay != 1, cycle.startsEarlyOnWeekends else { return d }
            switch cal.component(.weekday, from: d) {
            case 7: return cal.date(byAdding: .day, value: -1, to: d)!
            case 1: return cal.date(byAdding: .day, value: -2, to: d)!
            default: return d
            }
        }

        static func monthIndex(_ date: Date) -> Int {
            let c = utc.dateComponents([.year, .month], from: date)
            return c.year! * 12 + c.month! - 1
        }

        // First instant (UTC) of the budgeting month containing `date`, shifted by `offset`.
        // A month is named after the month it starts in.
        public static func cycleStart(_ date: Date, cycle: Cycle, offset: Int = 0) -> Date {
            var k = monthIndex(date) + 1
            while cycleBoundary(monthIndex: k, cycle: cycle) > date { k -= 1 }
            return cycleBoundary(monthIndex: k + offset, cycle: cycle)
        }

        // attributionMonth is stored as a calendar month. Left at its default (the primary's
        // own month) the group follows the primary into its cycle; a month someone picked by
        // hand maps to the cycle named after it.
        static func cycleStart(of group: SharedExpenseGroup, cycle: Cycle) -> Date {
            if let primary = group.primaryTx,
               monthStart(primary.bookedAt) == monthStart(group.attributionMonth) {
                return cycleStart(primary.bookedAt, cycle: cycle)
            }
            return cycleBoundary(monthIndex: monthIndex(group.attributionMonth), cycle: cycle)
        }

        // Income is only credited from non-liability accounts (group.kind != .credit;
        // ungrouped counts as income-eligible — parity with the leftJoin null kind).
        public static func incomeAccountIds(from accounts: [Account]) -> Set<UUID> {
            Set(accounts.filter { $0.group?.kind != .credit }.map { $0.id })
        }

        @MainActor
        public static func monthlyCashFlow(
            months: Int,
            accountIds: Set<UUID>,
            incomeAccountIds: Set<UUID>,
            now: Date,
            cycle: Cycle = .calendarMonth,
            in ctx: ModelContext
        ) throws -> [MonthlyFlow] {
            let buckets = (0..<months).map { cycleStart(now, cycle: cycle, offset: -($0)) }
            let bucketSet = Set(buckets)
            var income: [Date: Decimal] = [:]
            var directExpense: [Date: Decimal] = [:]
            var groupNet: [Date: Decimal] = [:]

            if !accountIds.isEmpty {
                let txs = try ctx.fetch(FetchDescriptor<Transaction>())
                for tx in txs {
                    guard let aid = tx.account?.id, accountIds.contains(aid) else { continue }
                    if tx.isTransfer || tx.sharedExpenseGroup != nil { continue }
                    let m = cycleStart(tx.bookedAt, cycle: cycle)
                    guard bucketSet.contains(m) else { continue }
                    switch tx.direction {
                    case .debit:
                        directExpense[m, default: 0] += tx.amountEur ?? 0
                    case .credit:
                        // A refund categorized as spending offsets that spending, it isn't income.
                        if let kind = tx.category?.kind, kind != "income" {
                            directExpense[m, default: 0] += tx.amountEur ?? 0
                        } else if incomeAccountIds.contains(aid) {
                            income[m, default: 0] += tx.amountEur ?? 0
                        }
                    }
                }

                let groups = try ctx.fetch(FetchDescriptor<SharedExpenseGroup>())
                for g in groups {
                    let m = cycleStart(of: g, cycle: cycle)
                    guard bucketSet.contains(m) else { continue }
                    for member in g.members {
                        guard let aid = member.account?.id, accountIds.contains(aid) else { continue }
                        groupNet[m, default: 0] += -(member.amountEur ?? 0)
                    }
                }
            }

            return buckets.reversed().map { m in
                MonthlyFlow(
                    monthStart: m,
                    income: income[m] ?? 0,
                    expense: max(-(directExpense[m] ?? 0) + (groupNet[m] ?? 0), 0)
                )
            }
        }

        // This month's debit spend per category, net of refunds, sorted by total descending.
        @MainActor
        public static func categoryBreakdown(
            accountIds: Set<UUID>,
            now: Date,
            cycle: Cycle = .calendarMonth,
            in ctx: ModelContext
        ) throws -> [CategorySpend] {
            if accountIds.isEmpty { return [] }
            let start = cycleStart(now, cycle: cycle)
            let end = cycleStart(now, cycle: cycle, offset: 1)
            var totals: [UUID?: Decimal] = [:]

            let txs = try ctx.fetch(FetchDescriptor<Transaction>())
            for tx in txs {
                guard let aid = tx.account?.id, accountIds.contains(aid) else { continue }
                if tx.isTransfer || tx.sharedExpenseGroup != nil { continue }
                if tx.direction != .debit && (tx.category == nil || tx.category?.kind == "income") { continue }
                if tx.bookedAt < start || tx.bookedAt >= end { continue }
                totals[tx.category?.id, default: 0] -= tx.amountEur ?? 0
            }

            let groups = try ctx.fetch(FetchDescriptor<SharedExpenseGroup>())
            for g in groups {
                guard cycleStart(of: g, cycle: cycle) == start else { continue }
                var net: Decimal = 0
                for member in g.members {
                    guard let aid = member.account?.id, accountIds.contains(aid) else { continue }
                    net += -(member.amountEur ?? 0)
                }
                if net == 0 { continue }
                // ponytail: a multi-expense group books its whole net under the anchor's
                // category. Split proportionally by expense if category totals ever look wrong.
                totals[g.primaryTx?.category?.id, default: 0] += net
            }

            return totals
                .filter { $0.value > 0 }
                .map { CategorySpend(categoryId: $0.key, total: $0.value) }
                .sorted { $0.total > $1.total }
        }
    }
}
