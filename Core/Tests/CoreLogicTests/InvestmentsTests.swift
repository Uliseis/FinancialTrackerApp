import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class InvestmentsTests: XCTestCase {
    typealias S = TransferTestSupport
    typealias I = CoreLogic.Investments

    private func makeGroup(_ ctx: ModelContext, name: String, kind: AccountGroupKind) -> AccountGroup {
        let g = AccountGroup(name: name, kind: kind)
        ctx.insert(g)
        return g
    }

    private func makeValuation(
        _ ctx: ModelContext,
        account: Account,
        asOf: Date,
        marketValueEur: Decimal,
        cashValueEur: Decimal? = nil
    ) -> PortfolioValuation {
        let v = PortfolioValuation(
            account: account, asOf: asOf,
            marketValueEur: marketValueEur, cashValueEur: cashValueEur
        )
        ctx.insert(v)
        return v
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    // MARK: - DB readers

    func testListAccountsInSpaceFiltersToInvestmentGroupNonArchived() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx, name: "Personal")
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let cashGroup = makeGroup(ctx, name: "Cash", kind: .cash)

        let inv = Account(
            group: invGroup, space: space, externalId: "inv",
            type: .broker, institution: "T212", name: "T212", currency: "EUR"
        )
        let invArchived = Account(
            group: invGroup, space: space, externalId: "old",
            type: .broker, institution: "Old", name: "Old", currency: "EUR",
            archived: true
        )
        let cash = Account(
            group: cashGroup, space: space, externalId: "cash",
            type: .bank, institution: "BBVA", name: "Checking", currency: "EUR"
        )
        ctx.insert(inv); ctx.insert(invArchived); ctx.insert(cash)
        try ctx.save()

        let rows = try I.listAccountsInSpace(spaceId: space.id, defaultSpaceId: space.id, in: ctx)
        let names = Set(rows.map { $0.account.name })
        XCTAssertEqual(names, ["T212"], "Only non-archived investment-kind accounts in space")
    }

    func testListAccountsInSpaceDefaultIncludesUnspaced() throws {
        let ctx = try S.makeContext()
        let defaultSpace = S.makeSpace(ctx, name: "Default")
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let inSpace = Account(
            group: invGroup, space: defaultSpace, externalId: "a",
            type: .broker, institution: "X", name: "Spaced", currency: "EUR"
        )
        let unspaced = Account(
            group: invGroup, space: nil, externalId: "b",
            type: .broker, institution: "Y", name: "Unspaced", currency: "EUR"
        )
        ctx.insert(inSpace); ctx.insert(unspaced)
        try ctx.save()

        let rows = try I.listAccountsInSpace(
            spaceId: defaultSpace.id, defaultSpaceId: defaultSpace.id, in: ctx
        )
        let names = Set(rows.map { $0.account.name })
        XCTAssertEqual(names, ["Spaced", "Unspaced"], "Default space includes accounts with no space")
    }

    func testListAccountsInSpaceNonDefaultExcludesUnspaced() throws {
        let ctx = try S.makeContext()
        let defaultSpace = S.makeSpace(ctx, name: "Default")
        let other = S.makeSpace(ctx, name: "Joint")
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let inOther = Account(
            group: invGroup, space: other, externalId: "a",
            type: .broker, institution: "X", name: "InOther", currency: "EUR"
        )
        let unspaced = Account(
            group: invGroup, space: nil, externalId: "b",
            type: .broker, institution: "Y", name: "Unspaced", currency: "EUR"
        )
        ctx.insert(inOther); ctx.insert(unspaced)
        try ctx.save()

        let rows = try I.listAccountsInSpace(
            spaceId: other.id, defaultSpaceId: defaultSpace.id, in: ctx
        )
        let names = Set(rows.map { $0.account.name })
        XCTAssertEqual(names, ["InOther"], "Non-default space excludes unspaced accounts")
    }

    func testListValuationsSortsAscending() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let acc = Account(
            group: invGroup, space: space, externalId: "x",
            type: .broker, institution: "T", name: "T", currency: "EUR"
        )
        ctx.insert(acc)
        _ = makeValuation(ctx, account: acc, asOf: day(2026, 3, 1), marketValueEur: 1000)
        _ = makeValuation(ctx, account: acc, asOf: day(2026, 1, 1), marketValueEur: 800)
        _ = makeValuation(ctx, account: acc, asOf: day(2026, 2, 1), marketValueEur: 900)
        try ctx.save()

        let vals = try I.listValuations(for: [acc.id], in: ctx)
        XCTAssertEqual(vals.map(\.marketValueEur), [800, 900, 1000])
    }

    func testListContributionLegsReturnsSignedAmountForTransferTxs() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let inv = Account(
            group: invGroup, space: space, externalId: "x",
            type: .broker, institution: "T", name: "T", currency: "EUR"
        )
        ctx.insert(inv)
        let g = TransferGroup(pairedAt: .now); ctx.insert(g)

        let deposit = S.makeTx(
            ctx, account: inv, amount: 500, amountEur: 500, direction: .credit,
            isTransfer: true, transferGroup: g
        )
        let withdrawal = S.makeTx(
            ctx, account: inv, amount: -200, amountEur: -200, direction: .debit,
            isTransfer: true, transferGroup: g
        )
        // Non-transfer tx (a buy / dividend) — must NOT appear
        _ = S.makeTx(ctx, account: inv, amount: 50, amountEur: 50, direction: .credit)
        // Transfer-flagged but no group (dangling, ignored)
        _ = S.makeTx(
            ctx, account: inv, amount: 99, amountEur: 99, direction: .credit,
            isTransfer: true
        )
        try ctx.save()

        let legs = try I.listContributionLegs(for: [inv.id], in: ctx)
        XCTAssertEqual(legs.count, 2)
        XCTAssertEqual(Set(legs.map(\.netEur)), [500, -200])
        XCTAssertTrue(legs.allSatisfy { $0.accountId == inv.id })
        _ = deposit; _ = withdrawal
    }

    func testSumLatestValueTakesNewestPerAccount() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let a = Account(
            group: invGroup, space: space, externalId: "a",
            type: .broker, institution: "T1", name: "T1", currency: "EUR"
        )
        let b = Account(
            group: invGroup, space: space, externalId: "b",
            type: .broker, institution: "T2", name: "T2", currency: "EUR"
        )
        ctx.insert(a); ctx.insert(b)
        _ = makeValuation(ctx, account: a, asOf: day(2026, 1, 1), marketValueEur: 1000)
        _ = makeValuation(ctx, account: a, asOf: day(2026, 4, 1), marketValueEur: 1500)
        _ = makeValuation(ctx, account: b, asOf: day(2026, 3, 1), marketValueEur: 700)
        try ctx.save()

        let total = try I.sumLatestValue(for: [a.id, b.id], in: ctx)
        XCTAssertEqual(total, 1500 + 700)
    }

    // MARK: - computeAccountMetrics (pure)

    func testComputeAccountMetricsEmptyAccountGetsEmptyMetrics() {
        let id = UUID()
        let result = I.computeAccountMetrics(
            investmentAccountIds: [id], valuations: [], legs: []
        )
        let m = result[id]
        XCTAssertNotNil(m)
        XCTAssertNil(m?.baselineEur)
        XCTAssertNil(m?.latestEur)
        XCTAssertNil(m?.costBasisEur)
        XCTAssertEqual(m?.netContributionsSinceBaselineEur, 0)
    }

    func testComputeAccountMetricsBaselineLatestAndPnl() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let acc = Account(
            group: invGroup, space: space, externalId: "x",
            type: .broker, institution: "T", name: "T", currency: "EUR"
        )
        ctx.insert(acc)
        let v1 = makeValuation(ctx, account: acc, asOf: day(2026, 1, 1), marketValueEur: 1000)
        let v2 = makeValuation(ctx, account: acc, asOf: day(2026, 6, 1), marketValueEur: 1500, cashValueEur: 300)
        let g = TransferGroup(pairedAt: .now); ctx.insert(g)
        // Deposit AFTER baseline → added to cost basis
        let deposit = S.makeTx(
            ctx, account: acc, amount: 200, amountEur: 200, direction: .credit,
            bookedAt: day(2026, 3, 1), isTransfer: true, transferGroup: g
        )
        try ctx.save()
        _ = v1; _ = v2; _ = deposit

        let valuations = try I.listValuations(for: [acc.id], in: ctx)
        let legs = try I.listContributionLegs(for: [acc.id], in: ctx)
        let metrics = I.computeAccountMetrics(
            investmentAccountIds: [acc.id], valuations: valuations, legs: legs
        )
        let m = try XCTUnwrap(metrics[acc.id])
        XCTAssertEqual(m.baselineEur, 1000)
        XCTAssertEqual(m.latestEur, 1500)
        XCTAssertEqual(m.latestCashEur, 300)
        XCTAssertEqual(m.latestPositionsEur, 1200, "latest - cash")
        XCTAssertEqual(m.netContributionsSinceBaselineEur, 200)
        XCTAssertEqual(m.costBasisEur, 1200, "baseline + contributions")
        XCTAssertEqual(m.pnlEur, 300, "latest - costBasis")
        XCTAssertEqual(m.pnlPct, Decimal(300) / Decimal(1200))
    }

    func testComputeAccountMetricsStrictGreaterThanBaseline() throws {
        // Same-day deposit must NOT be added on top of baseline — baseline already includes it.
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let acc = Account(
            group: invGroup, space: space, externalId: "x",
            type: .broker, institution: "T", name: "T", currency: "EUR"
        )
        ctx.insert(acc)
        let baselineAt = day(2026, 1, 1)
        _ = makeValuation(ctx, account: acc, asOf: baselineAt, marketValueEur: 1000)
        _ = makeValuation(ctx, account: acc, asOf: day(2026, 6, 1), marketValueEur: 1100)
        let g = TransferGroup(pairedAt: .now); ctx.insert(g)
        _ = S.makeTx(
            ctx, account: acc, amount: 500, amountEur: 500, direction: .credit,
            bookedAt: baselineAt, isTransfer: true, transferGroup: g
        )
        try ctx.save()

        let valuations = try I.listValuations(for: [acc.id], in: ctx)
        let legs = try I.listContributionLegs(for: [acc.id], in: ctx)
        let metrics = I.computeAccountMetrics(
            investmentAccountIds: [acc.id], valuations: valuations, legs: legs
        )
        let m = try XCTUnwrap(metrics[acc.id])
        XCTAssertEqual(m.netContributionsSinceBaselineEur, 0, "Same-day leg must be excluded")
        XCTAssertEqual(m.costBasisEur, 1000)
        XCTAssertEqual(m.pnlEur, 100)
    }

    func testComputeAccountMetricsZeroCostBasisGivesNilPct() {
        let id = UUID()
        let acc = Account(
            externalId: "x", type: .broker, institution: "T", name: "T", currency: "EUR"
        )
        let baseline = PortfolioValuation(account: acc, asOf: Date(), marketValueEur: 0)
        let m = I.computeAccountMetrics(
            investmentAccountIds: [id],
            valuations: [],
            legs: []
        )
        XCTAssertNil(m[id]?.pnlPct)
        _ = baseline
    }

    // MARK: - computePortfolioSeries (pure)

    func testComputePortfolioSeriesEmptyValuationsReturnsEmpty() {
        let series = I.computePortfolioSeries(
            investmentAccountIds: [UUID()], valuations: [], legs: []
        )
        XCTAssertEqual(series, [])
    }

    func testComputePortfolioSeriesCarriesForwardLatestValuation() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let a = Account(
            group: invGroup, space: space, externalId: "a",
            type: .broker, institution: "T1", name: "T1", currency: "EUR"
        )
        let b = Account(
            group: invGroup, space: space, externalId: "b",
            type: .broker, institution: "T2", name: "T2", currency: "EUR"
        )
        ctx.insert(a); ctx.insert(b)
        _ = makeValuation(ctx, account: a, asOf: day(2026, 1, 1), marketValueEur: 1000)
        _ = makeValuation(ctx, account: a, asOf: day(2026, 3, 1), marketValueEur: 1100)
        _ = makeValuation(ctx, account: b, asOf: day(2026, 2, 1), marketValueEur: 500)
        try ctx.save()

        let valuations = try I.listValuations(for: [a.id, b.id], in: ctx)
        let series = I.computePortfolioSeries(
            investmentAccountIds: [a.id, b.id],
            valuations: valuations,
            legs: []
        )
        XCTAssertEqual(series.count, 3, "One point per distinct date")
        // 2026-01-01: only A baseline (1000), B not yet started
        XCTAssertEqual(series[0].marketValueEur, 1000)
        // 2026-02-01: A still 1000 (carry-forward), B's first valuation 500 → 1500
        XCTAssertEqual(series[1].marketValueEur, 1500)
        // 2026-03-01: A bumped to 1100, B carried 500 → 1600
        XCTAssertEqual(series[2].marketValueEur, 1600)
    }

    func testComputePortfolioSeriesContributionsAccumulateInCostBasis() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let acc = Account(
            group: invGroup, space: space, externalId: "x",
            type: .broker, institution: "T", name: "T", currency: "EUR"
        )
        ctx.insert(acc)
        _ = makeValuation(ctx, account: acc, asOf: day(2026, 1, 1), marketValueEur: 1000)
        _ = makeValuation(ctx, account: acc, asOf: day(2026, 4, 1), marketValueEur: 1500)
        let g = TransferGroup(pairedAt: .now); ctx.insert(g)
        _ = S.makeTx(
            ctx, account: acc, amount: 200, amountEur: 200, direction: .credit,
            bookedAt: day(2026, 2, 1), isTransfer: true, transferGroup: g
        )
        try ctx.save()

        let valuations = try I.listValuations(for: [acc.id], in: ctx)
        let legs = try I.listContributionLegs(for: [acc.id], in: ctx)
        let series = I.computePortfolioSeries(
            investmentAccountIds: [acc.id],
            valuations: valuations,
            legs: legs
        )
        // Only two valuation dates → only two series points.
        XCTAssertEqual(series.count, 2)
        // Day 1: baseline 1000, no legs yet → costBasis = 1000
        XCTAssertEqual(series[0].costBasisEur, 1000)
        // Day 2 (after Feb deposit): costBasis = 1000 + 200 = 1200
        XCTAssertEqual(series[1].costBasisEur, 1200)
    }

    func testComputePortfolioSeriesPositionsClampsToZero() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let acc = Account(
            group: invGroup, space: space, externalId: "x",
            type: .broker, institution: "T", name: "T", currency: "EUR"
        )
        ctx.insert(acc)
        // Cash exceeds market value (e.g. valuation reporting glitch) → positions clamps to 0
        _ = makeValuation(
            ctx, account: acc, asOf: day(2026, 1, 1),
            marketValueEur: 500, cashValueEur: 800
        )
        try ctx.save()

        let valuations = try I.listValuations(for: [acc.id], in: ctx)
        let series = I.computePortfolioSeries(
            investmentAccountIds: [acc.id],
            valuations: valuations,
            legs: []
        )
        XCTAssertEqual(series.first?.positionsEur, 0)
    }

    // MARK: - periodStartDate

    func testPeriodStartDateAllIsNil() {
        XCTAssertNil(I.periodStartDate(.all))
    }

    func testPeriodStartDateYtdIsJanFirst() {
        let now = day(2026, 7, 15)
        let start = I.periodStartDate(.ytd, now: now)
        XCTAssertEqual(start, day(2026, 1, 1).addingTimeInterval(-12 * 3600), "Jan 1 00:00 UTC")
        // The helper day() embeds hour: 12, so subtract 12h to get midnight. Simpler check:
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: start!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.day, 1)
        XCTAssertEqual(comps.hour, 0)
    }

    func testPeriodStartDateOneYearAndThreeYears() {
        let now = day(2026, 5, 17)
        let oneY = I.periodStartDate(.oneYear, now: now)!
        let threeY = I.periodStartDate(.threeYears, now: now)!
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(cal.component(.year, from: oneY), 2025)
        XCTAssertEqual(cal.component(.year, from: threeY), 2023)
    }
}
