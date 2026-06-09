import Foundation
import SwiftData
import CoreModel
import CoreLogic

struct DashboardModel {
    struct GroupBucket: Identifiable {
        let id: String
        let name: String
        let colorHex: String?
        let eur: Decimal
        let count: Int
        let kind: AccountGroupKind?
        let excluded: Bool
    }

    struct MonthBar: Identifiable {
        let id: Date
        let label: String
        let income: Decimal
        let expense: Decimal
    }

    struct CategorySlice: Identifiable {
        let id: String
        let name: String
        let colorHex: String?
        let total: Decimal
    }

    struct BudgetBar: Identifiable {
        let id: UUID
        let name: String
        let period: BudgetPeriod
        let spent: Decimal
        let amount: Decimal
        let pct: Double
        let over: Bool
    }

    var cashTotal: Decimal
    var liabilities: Decimal
    var investmentValue: Decimal
    var groups: [GroupBucket]
    var cashFlow: [MonthBar]
    var topCategories: [CategorySlice]
    var budgets: [BudgetBar]
    var hasAccounts: Bool

    var totalNetWorth: Decimal { cashTotal + investmentValue }

    static let empty = DashboardModel(
        cashTotal: 0, liabilities: 0, investmentValue: 0,
        groups: [], cashFlow: [], topCategories: [], budgets: [], hasAccounts: false
    )

    @MainActor
    static func load(scope: SpaceScope, in ctx: ModelContext, now: Date = .now) -> DashboardModel {
        guard let currentId = scope.currentId, let defaultId = scope.defaultId else { return empty }
        let allAccounts = (try? ctx.fetch(FetchDescriptor<Account>())) ?? []
        let inScope = allAccounts.filter {
            scope.includes($0) && CoreLogic.AccountStatus.isCountedInCashNetWorth($0)
        }
        if inScope.isEmpty { return empty }

        let balances = (try? CoreLogic.Accounts.computeEurBalances(inScope, in: ctx)) ?? [:]

        struct Bucket { var name: String; var color: String?; var eur: Decimal; var count: Int
                        var kind: AccountGroupKind?; var sortOrder: Int }
        var buckets: [String: Bucket] = [:]
        for a in inScope {
            let key = a.group?.id.uuidString ?? "ungrouped"
            if buckets[key] == nil {
                buckets[key] = Bucket(
                    name: a.group?.name ?? "Ungrouped", color: a.group?.color,
                    eur: 0, count: 0, kind: a.group?.kind,
                    sortOrder: a.group?.sortOrder ?? Int.max
                )
            }
            buckets[key]?.eur += balances[a.id] ?? 0
            buckets[key]?.count += 1
        }

        let groups = buckets
            .sorted { ($0.value.sortOrder, $0.value.name) < ($1.value.sortOrder, $1.value.name) }
            .map { (key, b) in
                GroupBucket(
                    id: key, name: b.name, colorHex: b.color, eur: b.eur, count: b.count,
                    kind: b.kind, excluded: b.kind == .credit || b.kind == .investment
                )
            }

        var cashTotal: Decimal = 0
        var liabilities: Decimal = 0
        for g in groups {
            if g.kind == .credit { liabilities += g.eur }
            else if g.kind == .investment { continue }
            else { cashTotal += g.eur }
        }

        // Investment value ignores `excluded` (investment accounts are typically off cash
        // net worth but still counted as investments) — same scoping as the Investments tab.
        let investmentIds = (try? CoreLogic.Investments.listAccountIdsInSpace(
            spaceId: currentId, defaultSpaceId: defaultId, in: ctx)) ?? []
        let investmentValue = (try? CoreLogic.Investments.sumLatestValue(for: investmentIds, in: ctx)) ?? 0

        let accountIds = Set(inScope.map { $0.id })
        let incomeIds = CoreLogic.Dashboard.incomeAccountIds(from: inScope)
        let flow = (try? CoreLogic.Dashboard.monthlyCashFlow(
            months: 4, accountIds: accountIds, incomeAccountIds: incomeIds, now: now, in: ctx)) ?? []
        let cashFlow = flow.map {
            MonthBar(id: $0.monthStart, label: monthFormatter.string(from: $0.monthStart),
                     income: $0.income, expense: $0.expense)
        }

        let cats = (try? ctx.fetch(FetchDescriptor<CoreModel.Category>())) ?? []
        let catById = Dictionary(uniqueKeysWithValues: cats.map { ($0.id, $0) })

        let breakdown = (try? CoreLogic.Dashboard.categoryBreakdown(
            accountIds: accountIds, now: now, in: ctx)) ?? []
        let topCategories = breakdown.prefix(5).map { slice -> CategorySlice in
            let cat = slice.categoryId.flatMap { catById[$0] }
            return CategorySlice(
                id: slice.categoryId?.uuidString ?? "uncategorized",
                name: cat?.name ?? "Uncategorized",
                colorHex: cat?.color, total: slice.total
            )
        }

        let progress = (try? CoreLogic.Budgets.activeBudgetsProgress(at: now, in: ctx)) ?? []
        let budgets = progress
            .map { p -> BudgetBar in
                let amount = p.amountEur
                let pct = amount > 0 ? (p.spentEur / amount).doubleValue * 100 : 0
                return BudgetBar(
                    id: p.budgetId,
                    name: p.categoryId.flatMap { catById[$0]?.name } ?? "—",
                    period: p.period, spent: p.spentEur, amount: amount,
                    pct: pct, over: p.spentEur > amount
                )
            }
            .sorted { $0.pct > $1.pct }
            .prefix(5)
            .map { $0 }

        return DashboardModel(
            cashTotal: cashTotal, liabilities: liabilities, investmentValue: investmentValue,
            groups: groups, cashFlow: cashFlow, topCategories: topCategories,
            budgets: budgets, hasAccounts: true
        )
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "MMM yyyy"
        return f
    }()
}
