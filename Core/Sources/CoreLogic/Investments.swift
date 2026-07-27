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

        // A leg is either capital (money in, or capital handed back) or a distribution —
        // rent, dividends, coupons. The difference matters: a €250 payout from a property
        // doesn't reduce what you have invested in it, it IS the return. Netting the two
        // would make a yielding asset look like it was being sold off a slice at a time.
        public struct ContributionLeg: Equatable, Sendable {
            public let accountId: UUID
            public let bookedAt: Date
            public let netEur: Decimal
            public let isDistribution: Bool

            public init(
                accountId: UUID, bookedAt: Date, netEur: Decimal, isDistribution: Bool = false
            ) {
                self.accountId = accountId
                self.bookedAt = bookedAt
                self.netEur = netEur
                self.isDistribution = isDistribution
            }
        }

        // Both sides of an investment account are an anchor plus every leg booked after it —
        // the same shape as Account.balanceAnchor for cash. Cost basis anchors on
        // costBasisOpeningEur, market value on the newest snapshot. A deposit therefore lifts
        // value and cost by the identical amount and leaves P&L alone, which is the whole
        // point: paying money in is not a loss.
        public struct AccountMetrics: Equatable, Sendable {
            public let accountId: UUID
            public let latestAsOf: Date?
            // Snapshot (or live) figure, before contributions booked after it.
            public let anchorValueEur: Decimal?
            // anchorValueEur + contributions since. What the UI shows.
            public let valueEur: Decimal?
            public let latestCashEur: Decimal?
            public let latestPositionsEur: Decimal?
            // Paid in since the value anchor — the part the snapshot can't know about.
            public let contributionsSinceValueEur: Decimal
            public let costBasisEur: Decimal?
            public let pnlEur: Decimal?
            public let pnlPct: Decimal?
            // Gross money ever put in, before anything was handed back. The denominator for
            // return on an asset that has already repaid some capital.
            public let capitalInEur: Decimal?
            public let capitalReturnedEur: Decimal
            // Rent, dividends, coupons — realised return that never touched cost basis.
            public let distributionsEur: Decimal
            // True when the value came from a live feed rather than a typed snapshot.
            public let isLive: Bool

            // Everything the asset has produced: what it's worth, plus what it has already
            // paid out and handed back, less what went in. Correct before, during and after
            // an exit — a sold holding worth nothing still shows what it made.
            public var totalReturnEur: Decimal? {
                guard let value = valueEur, let capitalIn = capitalInEur else { return nil }
                return value + capitalReturnedEur + distributionsEur - capitalIn
            }

            public var totalReturnPct: Decimal? {
                guard let r = totalReturnEur, let capitalIn = capitalInEur,
                      capitalIn > Decimal(string: "0.000001")! else { return nil }
                return r / capitalIn
            }

            public var isStale: Bool {
                guard !isLive, let latestAsOf else { return false }
                return Date.now.timeIntervalSince(latestAsOf) > 45 * 86_400
            }
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
            // No transferGroup requirement: an unpaired leg is still money that left one
            // account and landed here. Requiring the pair silently dropped contributions.
            // isTransfer stays, so interest/dividends booked on the account read as return,
            // not as new money paid in.
            let candidates = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate {
                    $0.isTransfer == true && $0.amountEur != nil
                },
                sortBy: [SortDescriptor(\.bookedAt, order: .forward)]
            ))
            return candidates.compactMap { tx in
                guard let accId = tx.account?.id, idSet.contains(accId) else { return nil }
                guard let eur = tx.amountEur else { return nil }
                return ContributionLeg(
                    accountId: accId, bookedAt: tx.bookedAt, netEur: eur,
                    isDistribution: isDistribution(tx))
            }
        }

        // Categorising the payout as income is what marks it a distribution — no new field to
        // learn, and a rule can do it automatically. Route mirrors carry no category of their
        // own, so the originating bank row is consulted too.
        static func isDistribution(_ tx: Transaction) -> Bool {
            tx.category?.kind == "income" || tx.routedFromTx?.category?.kind == "income"
        }

        public static func basis(for account: Account) -> AccountBasis {
            AccountBasis(
                accountId: account.id,
                costBasisOpeningEur: account.costBasisOpeningEur,
                costBasisOpeningAt: account.costBasisOpeningAt,
                isLiveValued: account.liveValueSource?.isEmpty == false
            )
        }

        @MainActor
        public static func loadMetrics(
            for accounts: [Account],
            in ctx: ModelContext
        ) throws -> [UUID: AccountMetrics] {
            let ids = accounts.map(\.id)
            return computeAccountMetrics(
                bases: accounts.map(basis(for:)),
                valuations: try listValuations(for: ids, in: ctx),
                legs: try listContributionLegs(for: ids, in: ctx)
            )
        }

        // Net worth's investment slice. Uses the same snapshot + contributions-since figure the
        // Investments tab shows, so the two can't disagree.
        @MainActor
        public static func sumLatestValue(
            for accounts: [Account],
            in ctx: ModelContext
        ) throws -> Decimal {
            if accounts.isEmpty { return 0 }
            return try loadMetrics(for: accounts, in: ctx)
                .values.reduce(Decimal(0)) { $0 + ($1.valueEur ?? 0) }
        }

        // MARK: - Pure compute

        // The per-account inputs computeAccountMetrics needs from Account, so the maths stays
        // pure and testable without a ModelContext.
        public struct AccountBasis: Equatable, Sendable {
            public let accountId: UUID
            public let costBasisOpeningEur: Decimal?
            public let costBasisOpeningAt: Date?
            public let isLiveValued: Bool

            public init(
                accountId: UUID,
                costBasisOpeningEur: Decimal? = nil,
                costBasisOpeningAt: Date? = nil,
                isLiveValued: Bool = false
            ) {
                self.accountId = accountId
                self.costBasisOpeningEur = costBasisOpeningEur
                self.costBasisOpeningAt = costBasisOpeningAt
                self.isLiveValued = isLiveValued
            }
        }

        public static func computeAccountMetrics(
            bases: [AccountBasis],
            valuations: [PortfolioValuation],
            legs: [ContributionLeg]
        ) -> [UUID: AccountMetrics] {
            var byAccount: [UUID: [PortfolioValuation]] = [:]
            for v in valuations {
                guard let id = v.account?.id else { continue }
                byAccount[id, default: []].append(v)
            }

            var out: [UUID: AccountMetrics] = [:]
            for basis in bases {
                let accId = basis.accountId
                let list = byAccount[accId] ?? []
                let latest = list.last

                // Cost basis: opening figure plus every capital leg after it. With no opening
                // date the account's whole ledger counts, which is right for one opened
                // inside the data. Distributions are tallied separately — they are return,
                // not a withdrawal of capital.
                // Without an opening figure there is no cost basis at all: deriving one from
                // the legs alone would silently omit whatever the account held before the
                // ledger starts, and quietly report that gap as profit.
                var capitalIn: Decimal? = basis.costBasisOpeningEur
                var capitalReturned: Decimal = 0
                var distributions: Decimal = 0
                for leg in legs where leg.accountId == accId {
                    if let since = basis.costBasisOpeningAt, leg.bookedAt <= since { continue }
                    if leg.isDistribution {
                        distributions += abs(leg.netEur)
                    } else if leg.netEur < 0 {
                        capitalReturned += -leg.netEur
                    } else if let running = capitalIn {
                        capitalIn = running + leg.netEur
                    }
                }
                let costBasis: Decimal? = capitalIn.map { $0 - capitalReturned }

                guard let latest else {
                    out[accId] = AccountMetrics(
                        accountId: accId, latestAsOf: nil,
                        anchorValueEur: nil, valueEur: nil,
                        latestCashEur: nil, latestPositionsEur: nil,
                        contributionsSinceValueEur: 0,
                        costBasisEur: costBasis, pnlEur: nil, pnlPct: nil,
                        capitalInEur: capitalIn, capitalReturnedEur: capitalReturned,
                        distributionsEur: distributions,
                        isLive: basis.isLiveValued
                    )
                    continue
                }

                // Strict >: the snapshot already reflects same-instant moves.
                // A live-valued account is current by definition — adding legs would
                // double-count money the feed already sees. Distributions are skipped: a
                // property paying rent is not worth less afterwards.
                var sinceValue: Decimal = 0
                if !basis.isLiveValued {
                    for leg in legs where leg.accountId == accId
                        && leg.bookedAt > latest.asOf && !leg.isDistribution {
                        sinceValue += leg.netEur
                    }
                }

                let anchor = latest.marketValueEur
                let value = anchor + sinceValue
                let latestCash = latest.cashValueEur
                let latestPositions: Decimal? = latestCash.map { max(0, value - $0) }
                let pnl: Decimal? = costBasis.map { value - $0 }
                let epsilon = Decimal(string: "0.000001")!
                // Against cost basis normally, but once capital has been handed back that can
                // reach zero or go negative and the ratio stops meaning anything; gross
                // capital in is the stable denominator there.
                let pnlPct: Decimal? = {
                    guard let pnl else { return nil }
                    if let costBasis, costBasis > epsilon { return pnl / costBasis }
                    if let capitalIn, capitalIn > epsilon { return pnl / capitalIn }
                    return nil
                }()

                out[accId] = AccountMetrics(
                    accountId: accId,
                    latestAsOf: latest.asOf,
                    anchorValueEur: anchor,
                    valueEur: value,
                    latestCashEur: latestCash,
                    latestPositionsEur: latestPositions,
                    contributionsSinceValueEur: sinceValue,
                    costBasisEur: costBasis,
                    pnlEur: pnl,
                    pnlPct: pnlPct,
                    capitalInEur: capitalIn,
                    capitalReturnedEur: capitalReturned,
                    distributionsEur: distributions,
                    isLive: basis.isLiveValued
                )
            }
            return out
        }

        public static func computePortfolioSeries(
            bases: [AccountBasis],
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

            // Deposit days are plotted too, so paying money in visibly steps the line rather
            // than staying flat until the next snapshot.
            let firstSnapshot = valuations.map(\.asOf).min()!
            var dateSet = Set(valuations.map { cal.startOfDay(for: $0.asOf) })
            for leg in legs where leg.bookedAt > firstSnapshot {
                dateSet.insert(cal.startOfDay(for: leg.bookedAt))
            }
            let dates = dateSet.sorted()

            var out: [PortfolioSeriesPoint] = []
            for d in dates {
                let endOfDay = cal.date(byAdding: .day, value: 1, to: d)!
                var marketValue: Decimal = 0
                var cashTotal: Decimal = 0
                var costBasisTotal: Decimal = 0
                for basis in bases {
                    let accId = basis.accountId
                    guard let list = byAccount[accId], let first = list.first,
                          first.asOf < endOfDay else { continue }
                    var anchor: Decimal = 0
                    var anchorAt = first.asOf
                    var cash: Decimal = 0
                    for v in list {
                        if v.asOf < endOfDay {
                            anchor = v.marketValueEur
                            anchorAt = v.asOf
                            cash = v.cashValueEur ?? 0
                        } else { break }
                    }
                    var sinceValue: Decimal = 0
                    if !basis.isLiveValued {
                        for leg in legs where leg.accountId == accId
                            && leg.bookedAt > anchorAt && leg.bookedAt < endOfDay {
                            sinceValue += leg.netEur
                        }
                    }
                    marketValue += anchor + sinceValue
                    cashTotal += cash

                    if let opening = basis.costBasisOpeningEur {
                        var contrib: Decimal = 0
                        for leg in legs where leg.accountId == accId && leg.bookedAt < endOfDay {
                            if let since = basis.costBasisOpeningAt, leg.bookedAt <= since {
                                continue
                            }
                            contrib += leg.netEur
                        }
                        costBasisTotal += opening + contrib
                    }
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


        // Records "what this account is worth today". Snapshots are the only investment
        // data the app keeps (Instrument/Holding/Price were deliberately not ported), so
        // without a way to add one the displayed value silently ages — contributions after
        // the last snapshot never show up.
        // Same-day re-entry overwrites rather than stacking, so correcting a typo doesn't
        // leave two snapshots fighting over the same point on the chart.
        @MainActor
        @discardableResult
        public static func recordValuation(
            account: Account,
            marketValueEur: Decimal,
            cashValueEur: Decimal? = nil,
            asOf: Date = .now,
            notes: String? = nil,
            in ctx: ModelContext,
            now: Date = .now
        ) throws -> PortfolioValuation {
            let accountId = account.id
            let day = dayStart(asOf)
            let nextDay = day.addingTimeInterval(86_400)
            let existing = try ctx.fetch(FetchDescriptor<PortfolioValuation>(
                predicate: #Predicate {
                    $0.account?.id == accountId && $0.asOf >= day && $0.asOf < nextDay
                }
            )).first

            if let existing {
                existing.marketValueEur = marketValueEur
                existing.cashValueEur = cashValueEur
                existing.notes = notes
                existing.asOf = asOf
                existing.updatedAt = now
                try ctx.saveTouchingChanges()
                return existing
            }

            let valuation = PortfolioValuation(
                account: account,
                asOf: asOf,
                marketValueEur: marketValueEur,
                cashValueEur: cashValueEur,
                notes: notes,
                createdAt: now
            )
            ctx.insert(valuation)
            try ctx.saveTouchingChanges()
            return valuation
        }


        // The money-in anchor. Everything transferred in after `at` is added automatically,
        // so this is only ever set once, for whatever was already in the account before the
        // ledger starts.
        @MainActor
        public static func setCostBasisOpening(
            _ account: Account, amountEur: Decimal?, at date: Date?, in ctx: ModelContext
        ) throws {
            account.costBasisOpeningEur = amountEur
            account.costBasisOpeningAt = amountEur == nil ? nil : date
            try ctx.saveTouchingChanges()
        }

        @MainActor
        public static func setLiveSource(
            _ account: Account, source: String?, quantity: Decimal?, in ctx: ModelContext
        ) throws {
            let clean = source?.trimmingCharacters(in: .whitespacesAndNewlines)
            account.liveValueSource = (clean?.isEmpty ?? true) ? nil : clean
            account.assetQuantity = account.liveValueSource == nil ? nil : quantity
            try ctx.saveTouchingChanges()
        }

        // Safe now that cost basis lives on the account: deleting a snapshot only drops a
        // market-value reading, it can't destroy the P&L baseline the way it used to.
        @MainActor
        public static func deleteValuation(_ valuation: PortfolioValuation, in ctx: ModelContext) throws {
            ctx.delete(valuation)
            try ctx.saveTouchingChanges()
        }

        private static func dayStart(_ date: Date) -> Date {
            var cal = Calendar(identifier: .iso8601)
            cal.timeZone = TimeZone(identifier: "UTC")!
            return cal.startOfDay(for: date)
        }

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
