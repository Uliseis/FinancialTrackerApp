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
            in ctx: ModelContext
        ) throws -> [MonthlyFlow] {
            let buckets = (0..<months).map { monthStart(now, offset: -($0)) }
            let bucketSet = Set(buckets)
            var income: [Date: Decimal] = [:]
            var directExpense: [Date: Decimal] = [:]
            var groupNet: [Date: Decimal] = [:]

            if !accountIds.isEmpty {
                let txs = try ctx.fetch(FetchDescriptor<Transaction>())
                for tx in txs {
                    guard let aid = tx.account?.id, accountIds.contains(aid) else { continue }
                    if tx.isTransfer || tx.sharedExpenseGroup != nil { continue }
                    let m = monthStart(tx.bookedAt)
                    guard bucketSet.contains(m) else { continue }
                    switch tx.direction {
                    case .debit:
                        directExpense[m, default: 0] += tx.amountEur ?? 0
                    case .credit:
                        let isIncomeCat = tx.category == nil || tx.category?.kind == "income"
                        if isIncomeCat && incomeAccountIds.contains(aid) {
                            income[m, default: 0] += tx.amountEur ?? 0
                        }
                    }
                }

                let groups = try ctx.fetch(FetchDescriptor<SharedExpenseGroup>())
                for g in groups {
                    let m = monthStart(g.attributionMonth)
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
                    expense: abs(directExpense[m] ?? 0) + (groupNet[m] ?? 0)
                )
            }
        }

        // This month's debit spend per category, sorted by total descending.
        @MainActor
        public static func categoryBreakdown(
            accountIds: Set<UUID>,
            now: Date,
            in ctx: ModelContext
        ) throws -> [CategorySpend] {
            if accountIds.isEmpty { return [] }
            let start = monthStart(now)
            let end = monthStart(now, offset: 1)
            var totals: [UUID?: Decimal] = [:]

            let txs = try ctx.fetch(FetchDescriptor<Transaction>())
            for tx in txs {
                guard let aid = tx.account?.id, accountIds.contains(aid) else { continue }
                if tx.isTransfer || tx.sharedExpenseGroup != nil { continue }
                if tx.direction != .debit { continue }
                if tx.bookedAt < start || tx.bookedAt >= end { continue }
                totals[tx.category?.id, default: 0] += abs(tx.amountEur ?? 0)
            }

            let groups = try ctx.fetch(FetchDescriptor<SharedExpenseGroup>())
            for g in groups {
                guard monthStart(g.attributionMonth) == start else { continue }
                var net: Decimal = 0
                for member in g.members {
                    guard let aid = member.account?.id, accountIds.contains(aid) else { continue }
                    net += -(member.amountEur ?? 0)
                }
                if net == 0 { continue }
                totals[g.primaryTx?.category?.id, default: 0] += net
            }

            return totals
                .map { CategorySpend(categoryId: $0.key, total: $0.value) }
                .sorted { $0.total > $1.total }
        }
    }
}
