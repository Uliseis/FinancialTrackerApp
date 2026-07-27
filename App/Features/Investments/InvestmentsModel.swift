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
    }

    static let empty = InvestmentsModel(
        totalValue: 0, totalCost: nil, totalPnl: nil, totalPnlPct: nil,
        totalCash: 0, totalPositions: 0, lastUpdated: nil, rows: [], series: []
    )

    @MainActor
    static func load(spaceId: UUID, defaultId: UUID, in ctx: ModelContext) -> InvestmentsModel {
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
                hasCostBasis: m?.costBasisEur != nil
            ))
        }
        rows.sort { $0.name < $1.name }

        let totalPnl: Decimal? = countedForCost > 0 ? valueOfCostedAccounts - totalCost : nil
        let epsilon = Decimal(string: "0.000001")!
        let totalPnlPct: Decimal? =
            (totalPnl != nil && abs(totalCost) > epsilon) ? totalPnl! / totalCost : nil

        return InvestmentsModel(
            totalValue: totalValue,
            totalCost: countedForCost > 0 ? totalCost : nil,
            totalPnl: totalPnl,
            totalPnlPct: totalPnlPct,
            totalCash: totalCash,
            totalPositions: totalPositions,
            lastUpdated: lastUpdated,
            rows: rows,
            series: series
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
}
