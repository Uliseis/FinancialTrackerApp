import Foundation
import SwiftData
import CoreModel
import CoreLogic

struct InvestmentsModel {
    var totalValue: Decimal
    var totalCost: Decimal?
    var totalPnl: Decimal?
    var totalPnlPct: Decimal?
    var totalCash: Decimal
    var totalPositions: Decimal
    var lastUpdated: Date?
    var rows: [Row]
    var series: [CoreLogic.Investments.PortfolioSeriesPoint]
    var periodGain: PeriodGain?
    // Where the recorded history begins; lifetime profit includes whatever was made before it.
    var firstReadingAt: Date?

    struct PeriodGain {
        let from: Date
        let gainEur: Decimal
        let gainPct: Decimal?
        let netContributionsEur: Decimal
    }

    struct Row: Identifiable {
        let id: UUID
        let name: String
        let group: String
        let valueEur: Decimal?
        let pnlEur: Decimal?
        let pnlPct: Decimal?
        let contributionsSinceValueEur: Decimal
        let isLive: Bool
        let isStale: Bool
        let hasCostBasis: Bool
        let periodGainEur: Decimal?
        let periodGainPct: Decimal?
    }

    static let empty = InvestmentsModel(
        totalValue: 0, totalCost: nil, totalPnl: nil, totalPnlPct: nil,
        totalCash: 0, totalPositions: 0, lastUpdated: nil, rows: [], series: [], periodGain: nil,
        firstReadingAt: nil
    )

    @MainActor
    static func load(
        spaceId: UUID, defaultId: UUID, period: CoreLogic.Investments.Period, in ctx: ModelContext
    ) -> InvestmentsModel {
        guard let invRows = try? CoreLogic.Investments.listAccountsInSpace(
            spaceId: spaceId, defaultSpaceId: defaultId, in: ctx
        ), !invRows.isEmpty else { return empty }

        let accounts = invRows.map(\.account)
        let ids = accounts.map(\.id)
        let bases = accounts.map(CoreLogic.Investments.basis(for:))
        let valuations = (try? CoreLogic.Investments.listValuations(for: ids, in: ctx)) ?? []
        let legs = (try? CoreLogic.Investments.listContributionLegs(for: ids, in: ctx)) ?? []
        let metrics = CoreLogic.Investments.computeAccountMetrics(
            bases: bases, valuations: valuations, legs: legs
        )
        let series = CoreLogic.Investments.computePortfolioSeries(
            bases: bases, valuations: valuations, legs: legs
        )
        // "All" stays lifetime profit against cost basis; the other periods are the market
        // change inside the window, which is what makes them differ from each other.
        let returns = CoreLogic.Investments.periodStartDate(period).map {
            CoreLogic.Investments.computePeriodReturns(
                bases: bases, valuations: valuations, legs: legs, metrics: metrics, periodStart: $0)
        }

        var totalValue: Decimal = 0
        var totalCost: Decimal = 0
        var totalCash: Decimal = 0
        var totalPositions: Decimal = 0
        var countedForCost = 0
        var lastUpdated: Date?
        var rows: [Row] = []
        // Value counted against cost, not the portfolio total: an account with no cost basis
        // (an asset whose entry price was never recorded) would otherwise have its entire
        // value reported as profit.
        var valueOfCostedAccounts: Decimal = 0
        for r in invRows {
            let m = metrics[r.account.id]
            if let v = m?.valueEur { totalValue += v }
            if let c = m?.costBasisEur {
                totalCost += c
                countedForCost += 1
                valueOfCostedAccounts += m?.valueEur ?? 0
            }
            totalCash += m?.latestCashEur ?? 0
            totalPositions += m?.latestPositionsEur ?? 0
            if let la = m?.latestAsOf, lastUpdated == nil || la > lastUpdated! {
                lastUpdated = la
            }
            rows.append(Row(
                id: r.account.id, name: r.account.displayName, group: r.group.name,
                valueEur: m?.valueEur, pnlEur: m?.pnlEur, pnlPct: m?.pnlPct,
                contributionsSinceValueEur: m?.contributionsSinceValueEur ?? 0,
                isLive: m?.isLive ?? false, isStale: m?.isStale ?? false,
                hasCostBasis: m?.costBasisEur != nil,
                periodGainEur: returns?[r.account.id]?.gainEur,
                periodGainPct: returns?[r.account.id]?.gainPct
            ))
        }
        rows.sort { $0.name < $1.name }

        let totalPnl: Decimal? = countedForCost > 0 ? valueOfCostedAccounts - totalCost : nil
        let epsilon = Decimal(string: "0.000001")!
        let totalPnlPct: Decimal? =
            (totalPnl != nil && abs(totalCost) > epsilon) ? totalPnl! / totalCost : nil

        let periodGain: PeriodGain? = returns.flatMap { byId in
            let all = Array(byId.values)
            guard let from = all.map(\.from).min() else { return nil }
            let gain = all.reduce(Decimal(0)) { $0 + $1.gainEur }
            let start = all.reduce(Decimal(0)) { $0 + $1.startValueEur }
            let contributions = all.reduce(Decimal(0)) { $0 + $1.netContributionsEur }
            return PeriodGain(
                from: from, gainEur: gain,
                gainPct: CoreLogic.Investments.dietz(gain: gain, start: start, contributions: contributions),
                netContributionsEur: contributions)
        }

        return InvestmentsModel(
            totalValue: totalValue,
            totalCost: countedForCost > 0 ? totalCost : nil,
            totalPnl: totalPnl,
            totalPnlPct: totalPnlPct,
            totalCash: totalCash,
            totalPositions: totalPositions,
            lastUpdated: lastUpdated,
            rows: rows,
            series: series,
            periodGain: periodGain,
            firstReadingAt: valuations.map(\.asOf).min()
        )
    }
}

extension CoreLogic.Investments.Period {
    var label: String {
        switch self {
        case .ytd: "YTD"
        case .oneYear: "1Y"
        case .threeYears: "3Y"
        case .all: "All"
        }
    }

    var longLabel: String {
        switch self {
        case .ytd: "Year to date"
        case .oneYear: "Past year"
        case .threeYears: "Past 3 years"
        case .all: "All-time"
        }
    }
}
