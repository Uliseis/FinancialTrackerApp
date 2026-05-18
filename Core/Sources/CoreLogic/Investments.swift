import Foundation
import SwiftData
import CoreModel

extension CoreLogic {
    public enum Investments {
        public enum Period: String, CaseIterable, Sendable {
            case ytd
            case oneYear = "1y"
            case threeYears = "3y"
            case all
        }

        public struct InvestmentAccountRow {
            public let account: Account
            public let group: AccountGroup
        }

        public struct ContributionLeg: Equatable, Sendable {
            public let accountId: UUID
            public let bookedAt: Date
            public let netEur: Decimal
        }

        public struct AccountMetrics: Equatable, Sendable {
            public let accountId: UUID
            public let baselineAsOf: Date?
            public let baselineEur: Decimal?
            public let latestAsOf: Date?
            public let latestEur: Decimal?
            public let latestCashEur: Decimal?
            public let latestPositionsEur: Decimal?
            public let netContributionsSinceBaselineEur: Decimal
            public let costBasisEur: Decimal?
            public let pnlEur: Decimal?
            public let pnlPct: Decimal?
        }

        public struct PortfolioSeriesPoint: Equatable, Sendable {
            public let date: Date           // UTC start-of-day
            public let marketValueEur: Decimal
            public let costBasisEur: Decimal
            public let cashEur: Decimal
            public let positionsEur: Decimal
        }

        // MARK: - DB readers

        @MainActor
        public static func listAccountsInSpace(
            spaceId: UUID,
            defaultSpaceId: UUID,
            in ctx: ModelContext
        ) throws -> [InvestmentAccountRow] {
            let accounts = try fetchAccountsInSpace(
                spaceId: spaceId, defaultSpaceId: defaultSpaceId, in: ctx
            )
            return accounts.compactMap { acc in
                guard let g = acc.group, g.kind == .investment else { return nil }
                return InvestmentAccountRow(account: acc, group: g)
            }
        }

        @MainActor
        public static func listAccountIdsInSpace(
            spaceId: UUID,
            defaultSpaceId: UUID,
            in ctx: ModelContext
        ) throws -> [UUID] {
            try listAccountsInSpace(
                spaceId: spaceId, defaultSpaceId: defaultSpaceId, in: ctx
            ).map { $0.account.id }
        }

        @MainActor
        public static func listValuations(
            for accountIds: [UUID],
            in ctx: ModelContext
        ) throws -> [PortfolioValuation] {
            if accountIds.isEmpty { return [] }
            let idSet = Set(accountIds)
            let all = try ctx.fetch(FetchDescriptor<PortfolioValuation>(
                predicate: #Predicate { $0.account != nil },
                sortBy: [SortDescriptor(\.asOf, order: .forward)]
            ))
            return all.filter { v in
                guard let id = v.account?.id else { return false }
                return idSet.contains(id)
            }
        }

        @MainActor
        public static func listContributionLegs(
            for accountIds: [UUID],
            in ctx: ModelContext
        ) throws -> [ContributionLeg] {
            if accountIds.isEmpty { return [] }
            let idSet = Set(accountIds)
            let candidates = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate {
                    $0.isTransfer == true &&
                    $0.transferGroup != nil &&
                    $0.amountEur != nil
                },
                sortBy: [SortDescriptor(\.bookedAt, order: .forward)]
            ))
            return candidates.compactMap { tx in
                guard let accId = tx.account?.id, idSet.contains(accId) else { return nil }
                guard let eur = tx.amountEur else { return nil }
                return ContributionLeg(accountId: accId, bookedAt: tx.bookedAt, netEur: eur)
            }
        }

        @MainActor
        public static func sumLatestValue(
            for accountIds: [UUID],
            in ctx: ModelContext
        ) throws -> Decimal {
            if accountIds.isEmpty { return 0 }
            let idSet = Set(accountIds)
            let valuations = try ctx.fetch(FetchDescriptor<PortfolioValuation>(
                predicate: #Predicate { $0.account != nil },
                sortBy: [SortDescriptor(\.asOf, order: .reverse)]
            ))
            var seen = Set<UUID>()
            var total: Decimal = 0
            for v in valuations {
                guard let accId = v.account?.id, idSet.contains(accId), !seen.contains(accId) else {
                    continue
                }
                seen.insert(accId)
                total += v.marketValueEur
            }
            return total
        }

        // MARK: - Pure compute

        public static func computeAccountMetrics(
            investmentAccountIds: [UUID],
            valuations: [PortfolioValuation],
            legs: [ContributionLeg]
        ) -> [UUID: AccountMetrics] {
            var byAccount: [UUID: [PortfolioValuation]] = [:]
            for v in valuations {
                guard let id = v.account?.id else { continue }
                byAccount[id, default: []].append(v)
            }

            var out: [UUID: AccountMetrics] = [:]
            for accId in investmentAccountIds {
                let list = byAccount[accId] ?? []
                if list.isEmpty {
                    out[accId] = AccountMetrics(
                        accountId: accId,
                        baselineAsOf: nil, baselineEur: nil,
                        latestAsOf: nil, latestEur: nil,
                        latestCashEur: nil, latestPositionsEur: nil,
                        netContributionsSinceBaselineEur: 0,
                        costBasisEur: nil, pnlEur: nil, pnlPct: nil
                    )
                    continue
                }
                let baseline = list.first!
                let latest = list.last!
                let baselineTime = baseline.asOf

                // Strict >: baseline already reflects same-day moves; don't double-count.
                var net: Decimal = 0
                for leg in legs where leg.accountId == accId && leg.bookedAt > baselineTime {
                    net += leg.netEur
                }

                let baselineEur = baseline.marketValueEur
                let latestEur = latest.marketValueEur
                let latestCash = latest.cashValueEur
                let latestPositions: Decimal? = latestCash.map { max(0, latestEur - $0) }
                let costBasis = baselineEur + net
                let pnl = latestEur - costBasis
                let pnlPct: Decimal? = abs(costBasis) > Decimal(string: "0.000001")! ? pnl / costBasis : nil

                out[accId] = AccountMetrics(
                    accountId: accId,
                    baselineAsOf: baseline.asOf,
                    baselineEur: baselineEur,
                    latestAsOf: latest.asOf,
                    latestEur: latestEur,
                    latestCashEur: latestCash,
                    latestPositionsEur: latestPositions,
                    netContributionsSinceBaselineEur: net,
                    costBasisEur: costBasis,
                    pnlEur: pnl,
                    pnlPct: pnlPct
                )
            }
            return out
        }

        public static func computePortfolioSeries(
            investmentAccountIds: [UUID],
            valuations: [PortfolioValuation],
            legs: [ContributionLeg]
        ) -> [PortfolioSeriesPoint] {
            if valuations.isEmpty { return [] }

            var cal = Calendar(identifier: .iso8601)
            cal.timeZone = TimeZone(identifier: "UTC")!

            var byAccount: [UUID: [PortfolioValuation]] = [:]
            for v in valuations {
                guard let id = v.account?.id else { continue }
                byAccount[id, default: []].append(v)
            }

            let dateSet = Set(valuations.map { cal.startOfDay(for: $0.asOf) })
            let dates = dateSet.sorted()

            var out: [PortfolioSeriesPoint] = []
            for d in dates {
                let endOfDay = cal.date(byAdding: .day, value: 1, to: d)!
                var marketValue: Decimal = 0
                var cashTotal: Decimal = 0
                var costBasisTotal: Decimal = 0
                for accId in investmentAccountIds {
                    guard let list = byAccount[accId], !list.isEmpty else { continue }
                    let baseline = list.first!
                    if baseline.asOf >= endOfDay { continue }
                    var mv: Decimal = 0
                    var cash: Decimal = 0
                    for v in list {
                        if v.asOf < endOfDay {
                            mv = v.marketValueEur
                            cash = v.cashValueEur ?? 0
                        } else { break }
                    }
                    marketValue += mv
                    cashTotal += cash
                    var contrib: Decimal = 0
                    for leg in legs where leg.accountId == accId {
                        if leg.bookedAt > baseline.asOf && leg.bookedAt < endOfDay {
                            contrib += leg.netEur
                        }
                    }
                    costBasisTotal += baseline.marketValueEur + contrib
                }
                let positions = max(0, marketValue - cashTotal)
                out.append(PortfolioSeriesPoint(
                    date: d,
                    marketValueEur: marketValue,
                    costBasisEur: costBasisTotal,
                    cashEur: cashTotal,
                    positionsEur: positions
                ))
            }
            return out
        }

        // MARK: - Helpers

        public static func periodStartDate(_ period: Period, now: Date = .now) -> Date? {
            var cal = Calendar(identifier: .iso8601)
            cal.timeZone = TimeZone(identifier: "UTC")!
            switch period {
            case .all:
                return nil
            case .ytd:
                let year = cal.component(.year, from: now)
                return cal.date(from: DateComponents(year: year, month: 1, day: 1))
            case .oneYear:
                return cal.date(byAdding: .year, value: -1, to: now)
            case .threeYears:
                return cal.date(byAdding: .year, value: -3, to: now)
            }
        }

        // The default space catches all accounts with no space assignment.
        // Match TS `accountInSpaceClause` semantics.
        @MainActor
        private static func fetchAccountsInSpace(
            spaceId: UUID,
            defaultSpaceId: UUID,
            in ctx: ModelContext
        ) throws -> [Account] {
            if spaceId == defaultSpaceId {
                return try ctx.fetch(FetchDescriptor<Account>(
                    predicate: #Predicate {
                        $0.archived == false && ($0.space == nil || $0.space?.id == spaceId)
                    }
                ))
            }
            return try ctx.fetch(FetchDescriptor<Account>(
                predicate: #Predicate { $0.archived == false && $0.space?.id == spaceId }
            ))
        }
    }
}
