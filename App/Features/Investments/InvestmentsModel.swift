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
        let latestEur: Decimal?
        let pnlEur: Decimal?
        let pnlPct: Decimal?
    }

    static let empty = InvestmentsModel(
        totalValue: 0, totalCost: nil, totalPnl: nil, totalPnlPct: nil,
        totalCash: 0, totalPositions: 0, lastUpdated: nil, rows: [], series: []
    )

    // Scoped to the default space for now (all investment accounts live there); a
    // cross-app space picker will parameterize this later.
    @MainActor
    static func load(in ctx: ModelContext) -> InvestmentsModel {
        guard let def = (try? ctx.fetch(FetchDescriptor<AccountSpace>(
            predicate: #Predicate { $0.isDefault }
        )))?.first else { return empty }
        let defId = def.id

        guard let invRows = try? CoreLogic.Investments.listAccountsInSpace(
            spaceId: defId, defaultSpaceId: defId, in: ctx
        ), !invRows.isEmpty else { return empty }

        let ids = invRows.map { $0.account.id }
        let valuations = (try? CoreLogic.Investments.listValuations(for: ids, in: ctx)) ?? []
        let legs = (try? CoreLogic.Investments.listContributionLegs(for: ids, in: ctx)) ?? []
        let metrics = CoreLogic.Investments.computeAccountMetrics(
            investmentAccountIds: ids, valuations: valuations, legs: legs
        )
        let series = CoreLogic.Investments.computePortfolioSeries(
            investmentAccountIds: ids, valuations: valuations, legs: legs
        )

        var totalValue: Decimal = 0
        var totalCost: Decimal = 0
        var totalCash: Decimal = 0
        var totalPositions: Decimal = 0
        var countedForCost = 0
        var lastUpdated: Date?
        var rows: [Row] = []
        for r in invRows {
            let m = metrics[r.account.id]
            if let v = m?.latestEur { totalValue += v }
            if let c = m?.costBasisEur { totalCost += c; countedForCost += 1 }
            if let cash = m?.latestCashEur, let pos = m?.latestPositionsEur {
                totalCash += cash; totalPositions += pos
            }
            if let la = m?.latestAsOf, lastUpdated == nil || la > lastUpdated! {
                lastUpdated = la
            }
            rows.append(Row(
                id: r.account.id, name: r.account.name, group: r.group.name,
                latestEur: m?.latestEur, pnlEur: m?.pnlEur, pnlPct: m?.pnlPct
            ))
        }
        rows.sort { $0.name < $1.name }

        let totalPnl: Decimal? = countedForCost > 0 ? totalValue - totalCost : nil
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
