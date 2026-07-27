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

        // An unpaired leg still moved money into the account, so it counts. Only the
        // non-transfer row (a return, not a contribution) is left out.
        let legs = try I.listContributionLegs(for: [inv.id], in: ctx)
        XCTAssertEqual(legs.count, 3)
        XCTAssertEqual(Set(legs.map(\.netEur)), [500, -200, 99])
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

        let total = try I.sumLatestValue(for: [a, b], in: ctx)
        XCTAssertEqual(total, 1500 + 700)
    }

    func testSumLatestValueAddsContributionsBookedAfterTheSnapshot() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let a = Account(
            group: invGroup, space: space, externalId: "a",
            type: .broker, institution: "T1", name: "T1", currency: "EUR"
        )
        ctx.insert(a)
        _ = makeValuation(ctx, account: a, asOf: day(2026, 1, 1), marketValueEur: 1000)
        let g = TransferGroup(pairedAt: .now); ctx.insert(g)
        _ = S.makeTx(
            ctx, account: a, amount: 250, amountEur: 250, direction: .credit,
            bookedAt: day(2026, 5, 1), isTransfer: true, transferGroup: g
        )
        try ctx.save()

        // Net worth must not ignore money paid in since the last snapshot.
        XCTAssertEqual(try I.sumLatestValue(for: [a], in: ctx), 1250)
    }

    // MARK: - computeAccountMetrics (pure)

    func testComputeAccountMetricsEmptyAccountGetsEmptyMetrics() {
        let id = UUID()
        let result = I.computeAccountMetrics(
            bases: [.init(accountId: id)], valuations: [], legs: []
        )
        let m = result[id]
        XCTAssertNotNil(m)
        XCTAssertNil(m?.anchorValueEur)
        XCTAssertNil(m?.valueEur)
        XCTAssertNil(m?.costBasisEur)
        XCTAssertEqual(m?.contributionsSinceValueEur, 0)
    }

    // The headline behaviour: paying money in raises value and cost basis identically, so a
    // deposit never reads as a loss. This is what the old baseline-as-market-value model got
    // wrong — it moved cost basis only.
    func testDepositAfterSnapshotRaisesValueAndCostBasisEqually() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let acc = Account(
            group: invGroup, space: space, externalId: "x",
            type: .broker, institution: "T", name: "T", currency: "EUR",
            costBasisOpeningEur: 800, costBasisOpeningAt: day(2026, 1, 1)
        )
        ctx.insert(acc)
        _ = makeValuation(ctx, account: acc, asOf: day(2026, 1, 1), marketValueEur: 1000)
        let g = TransferGroup(pairedAt: .now); ctx.insert(g)
        _ = S.makeTx(
            ctx, account: acc, amount: 500, amountEur: 500, direction: .credit,
            bookedAt: day(2026, 6, 1), isTransfer: true, transferGroup: g
        )
        try ctx.save()

        let m = try XCTUnwrap(try I.loadMetrics(for: [acc], in: ctx)[acc.id])
        XCTAssertEqual(m.anchorValueEur, 1000)
        XCTAssertEqual(m.valueEur, 1500, "snapshot + money in since")
        XCTAssertEqual(m.contributionsSinceValueEur, 500)
        XCTAssertEqual(m.costBasisEur, 1300, "opening + money in since opening")
        XCTAssertEqual(m.pnlEur, 200, "unchanged by the deposit")
    }

    func testLiveValuedAccountIgnoresContributionsInValue() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let acc = Account(
            group: invGroup, space: space, externalId: "x",
            type: .broker, institution: "T", name: "T", currency: "EUR",
            costBasisOpeningEur: 800, costBasisOpeningAt: day(2026, 1, 1),
            liveValueSource: "t212"
        )
        ctx.insert(acc)
        _ = makeValuation(ctx, account: acc, asOf: day(2026, 6, 1), marketValueEur: 2000)
        let g = TransferGroup(pairedAt: .now); ctx.insert(g)
        // Booked before the live figure was taken — the feed already sees this money.
        _ = S.makeTx(
            ctx, account: acc, amount: 500, amountEur: 500, direction: .credit,
            bookedAt: day(2026, 3, 1), isTransfer: true, transferGroup: g
        )
        try ctx.save()

        let m = try XCTUnwrap(try I.loadMetrics(for: [acc], in: ctx)[acc.id])
        XCTAssertTrue(m.isLive)
        XCTAssertEqual(m.valueEur, 2000, "live value is authoritative, never adjusted")
        XCTAssertEqual(m.contributionsSinceValueEur, 0)
        XCTAssertEqual(m.costBasisEur, 1300)
    }

    // The Prophero Bali shape: capital in, then a yield, then an exit. Rent must not read as
    // the asset being sold off in slices.
    @MainActor
    private func makeYieldingAsset(_ ctx: ModelContext) throws -> (Account, CoreModel.Category) {
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Real Estate", kind: .investment)
        let acc = Account(
            group: invGroup, space: space, externalId: "bali",
            type: .broker, institution: "Prophero", name: "Bali", currency: "EUR",
            costBasisOpeningEur: 25_000, costBasisOpeningAt: day(2026, 1, 1))
        ctx.insert(acc)
        let income = CoreModel.Category(name: "Investment income", kind: "income")
        ctx.insert(income)
        _ = makeValuation(ctx, account: acc, asOf: day(2026, 1, 1), marketValueEur: 25_000)
        return (acc, income)
    }

    func testDistributionsAreReturnNotAWithdrawalOfCapital() throws {
        let ctx = try S.makeContext()
        let (acc, income) = try makeYieldingAsset(ctx)
        let g = TransferGroup(pairedAt: .now); ctx.insert(g)
        for month in 4...6 {
            _ = S.makeTx(
                ctx, account: acc, amount: -250, amountEur: -250, direction: .debit,
                bookedAt: day(2026, month, 1), isTransfer: true, transferGroup: g,
                category: income)
        }
        try ctx.save()

        let m = try XCTUnwrap(try I.loadMetrics(for: [acc], in: ctx)[acc.id])
        XCTAssertEqual(m.costBasisEur, 25_000, "rent doesn't reduce what's invested")
        XCTAssertEqual(m.distributionsEur, 750)
        XCTAssertEqual(m.valueEur, 25_000, "the property isn't worth less for having paid out")
        XCTAssertEqual(m.totalReturnEur, 750)
        XCTAssertEqual(m.totalReturnPct, Decimal(750) / Decimal(25_000))
    }

    func testExitReturnsCapitalAndKeepsTotalReturnHonest() throws {
        let ctx = try S.makeContext()
        let (acc, income) = try makeYieldingAsset(ctx)
        let g = TransferGroup(pairedAt: .now); ctx.insert(g)
        _ = S.makeTx(
            ctx, account: acc, amount: -3_200, amountEur: -3_200, direction: .debit,
            bookedAt: day(2026, 6, 1), isTransfer: true, transferGroup: g, category: income)
        // Sold: 28.000 back, uncategorised, so it reads as capital returned.
        _ = S.makeTx(
            ctx, account: acc, amount: -28_000, amountEur: -28_000, direction: .debit,
            bookedAt: day(2028, 6, 1), isTransfer: true, transferGroup: g)
        _ = makeValuation(ctx, account: acc, asOf: day(2028, 6, 2), marketValueEur: 0)
        try ctx.save()

        let m = try XCTUnwrap(try I.loadMetrics(for: [acc], in: ctx)[acc.id])
        XCTAssertEqual(m.valueEur, 0, "nothing left to hold")
        XCTAssertEqual(m.capitalInEur, 25_000)
        XCTAssertEqual(m.capitalReturnedEur, 28_000)
        XCTAssertEqual(m.distributionsEur, 3_200)
        XCTAssertEqual(m.totalReturnEur, 6_200, "3.000 on the sale + 3.200 of yield")
        XCTAssertEqual(m.totalReturnPct, Decimal(6_200) / Decimal(25_000))
    }

    // MyInvestor's shape: one bank transfer arrives, then part of it is allocated to the
    // pension wrapper. Only the arrival has a bank row, so the split has to be recordable.
    func testInternalTransferMovesCostBasisBetweenTwoAccounts() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let funds = Account(
            group: invGroup, space: space, externalId: "funds",
            type: .broker, institution: "MyInvestor", name: "Funds", currency: "EUR",
            costBasisOpeningEur: 20_000, costBasisOpeningAt: day(2026, 1, 1))
        let pension = Account(
            group: invGroup, space: space, externalId: "pension",
            type: .broker, institution: "MyInvestor", name: "Pension", currency: "EUR",
            costBasisOpeningEur: 2_000, costBasisOpeningAt: day(2026, 1, 1))
        ctx.insert(funds); ctx.insert(pension)
        _ = makeValuation(ctx, account: funds, asOf: day(2026, 2, 1), marketValueEur: 20_500)
        _ = makeValuation(ctx, account: pension, asOf: day(2026, 2, 1), marketValueEur: 2_100)
        try ctx.save()

        try CoreLogic.Transfers.createInternalTransfer(
            from: funds, to: pension, amountEur: 1_500,
            bookedAt: day(2026, 3, 1), note: "2026 pension contribution", in: ctx)

        let metrics = try I.loadMetrics(for: [funds, pension], in: ctx)
        let f = try XCTUnwrap(metrics[funds.id])
        let p = try XCTUnwrap(metrics[pension.id])
        XCTAssertEqual(f.costBasisEur, 18_500, "20.000 − 1.500")
        XCTAssertEqual(p.costBasisEur, 3_500, "2.000 + 1.500")
        XCTAssertEqual(
            (f.costBasisEur ?? 0) + (p.costBasisEur ?? 0), 22_000,
            "nothing invented, nothing lost")
        XCTAssertEqual(f.valueEur, 19_000, "the money left the funds account")
        XCTAssertEqual(p.valueEur, 3_600)
    }

    func testLastInternalTransferOffersTheRecurringTopUp() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let funds = Account(
            group: invGroup, space: space, externalId: "funds",
            type: .broker, institution: "MyInvestor", name: "Funds", currency: "EUR")
        let pension = Account(
            group: invGroup, space: space, externalId: "pension",
            type: .broker, institution: "MyInvestor", name: "Pension", currency: "EUR")
        ctx.insert(funds); ctx.insert(pension)
        try ctx.save()

        XCTAssertNil(try CoreLogic.Transfers.lastInternalTransfer(into: pension, in: ctx))

        try CoreLogic.Transfers.createInternalTransfer(
            from: funds, to: pension, amountEur: 125, bookedAt: day(2026, 5, 26), in: ctx)
        try CoreLogic.Transfers.createInternalTransfer(
            from: funds, to: pension, amountEur: 125, bookedAt: day(2026, 6, 19), in: ctx)

        let s = try XCTUnwrap(try CoreLogic.Transfers.lastInternalTransfer(into: pension, in: ctx))
        XCTAssertEqual(s.amountEur, 125)
        XCTAssertEqual(s.sourceId, funds.id)
        XCTAssertEqual(s.lastBookedAt, day(2026, 6, 19), "the most recent one")

        // The suggestion must not fire on the account the money came FROM.
        XCTAssertNil(try CoreLogic.Transfers.lastInternalTransfer(into: funds, in: ctx))
    }

    func testInternalTransferRefusesAcrossSpaces() throws {
        let ctx = try S.makeContext()
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let a = Account(
            group: invGroup, space: S.makeSpace(ctx), externalId: "a",
            type: .broker, institution: "X", name: "A", currency: "EUR")
        let b = Account(
            group: invGroup, space: S.makeSpace(ctx), externalId: "b",
            type: .broker, institution: "X", name: "B", currency: "EUR")
        ctx.insert(a); ctx.insert(b)
        try ctx.save()

        XCTAssertThrowsError(
            try CoreLogic.Transfers.createInternalTransfer(
                from: a, to: b, amountEur: 100, in: ctx))
    }

    // MARK: - drift guards

    func testFundedButNeverValuedAccountIsWorthWhatWentIn() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let acc = Account(
            group: invGroup, space: space, externalId: "new",
            type: .broker, institution: "X", name: "New", currency: "EUR",
            costBasisOpeningEur: 0, costBasisOpeningAt: day(2026, 1, 1))
        ctx.insert(acc)
        let g = TransferGroup(pairedAt: .now); ctx.insert(g)
        _ = S.makeTx(
            ctx, account: acc, amount: 5_000, amountEur: 5_000, direction: .credit,
            bookedAt: day(2026, 3, 1), isTransfer: true, transferGroup: g)
        try ctx.save()

        // Otherwise net worth falls by 5.000 the moment the money leaves the bank account.
        let m = try XCTUnwrap(try I.loadMetrics(for: [acc], in: ctx)[acc.id])
        XCTAssertEqual(m.valueEur, 5_000)
        XCTAssertEqual(m.pnlEur, 0)
        XCTAssertNil(m.anchorValueEur, "nothing has actually been read")
        XCTAssertTrue(m.isStale, "a placeholder should ask to be replaced")
        XCTAssertEqual(try I.sumLatestValue(for: [acc], in: ctx), 5_000)
    }

    func testContributionsAfterTheReadingCountAsCashNotPositions() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let acc = Account(
            group: invGroup, space: space, externalId: "x",
            type: .broker, institution: "T", name: "T", currency: "EUR")
        ctx.insert(acc)
        _ = makeValuation(
            ctx, account: acc, asOf: day(2026, 1, 1), marketValueEur: 10_000, cashValueEur: 500)
        let g = TransferGroup(pairedAt: .now); ctx.insert(g)
        _ = S.makeTx(
            ctx, account: acc, amount: 1_000, amountEur: 1_000, direction: .credit,
            bookedAt: day(2026, 6, 1), isTransfer: true, transferGroup: g)
        try ctx.save()

        let m = try XCTUnwrap(try I.loadMetrics(for: [acc], in: ctx)[acc.id])
        XCTAssertEqual(m.valueEur, 11_000)
        XCTAssertEqual(m.latestCashEur, 1_500, "the new money hasn't been invested yet")
        XCTAssertEqual(m.latestPositionsEur, 9_500, "positions are unchanged by a deposit")
        XCTAssertEqual((m.latestCashEur ?? 0) + (m.latestPositionsEur ?? 0), m.valueEur)
    }

    // The summary card adds these up across accounts, so a nil on either side silently
    // dropped a whole account out of the breakdown while it still counted in the total.
    func testPositionsAreKnownEvenWhenCashIsNotReported() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let acc = Account(
            group: invGroup, space: space, externalId: "x",
            type: .broker, institution: "T", name: "T", currency: "EUR")
        ctx.insert(acc)
        // Crypto readings carry no cash figure at all.
        _ = makeValuation(ctx, account: acc, asOf: day(2026, 1, 1), marketValueEur: 3_447)
        try ctx.save()

        let m = try XCTUnwrap(try I.loadMetrics(for: [acc], in: ctx)[acc.id])
        XCTAssertNil(m.latestCashEur, "unknown, not zero")
        XCTAssertEqual(m.latestPositionsEur, 3_447, "all of it is positions")
        XCTAssertEqual((m.latestCashEur ?? 0) + (m.latestPositionsEur ?? 0), m.valueEur)
    }

    func testOpeningDateIsPinnedToStartOfDaySoResavingCantMoveCostBasis() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let acc = Account(
            group: invGroup, space: space, externalId: "x",
            type: .broker, institution: "T", name: "T", currency: "EUR")
        ctx.insert(acc)
        _ = makeValuation(ctx, account: acc, asOf: day(2026, 1, 1), marketValueEur: 10_000)
        let g = TransferGroup(pairedAt: .now); ctx.insert(g)
        // Booked at midday on the same day the opening figure is dated.
        _ = S.makeTx(
            ctx, account: acc, amount: 400, amountEur: 400, direction: .credit,
            bookedAt: day(2026, 3, 1), isTransfer: true, transferGroup: g)
        try ctx.save()

        // Saved twice at different times of day — the picker hands back the current clock.
        try I.setCostBasisOpening(
            acc, amountEur: 9_000, at: day(2026, 3, 1).addingTimeInterval(-3 * 3600), in: ctx)
        let first = try XCTUnwrap(try I.loadMetrics(for: [acc], in: ctx)[acc.id]).costBasisEur
        try I.setCostBasisOpening(
            acc, amountEur: 9_000, at: day(2026, 3, 1).addingTimeInterval(6 * 3600), in: ctx)
        let second = try XCTUnwrap(try I.loadMetrics(for: [acc], in: ctx)[acc.id]).costBasisEur

        XCTAssertEqual(first, second, "the hour the form happened to be open must not matter")
        XCTAssertEqual(first, 9_400, "legs during that day count")
    }

    func testInflowTaggedAsIncomeIsStillCapital() throws {
        let ctx = try S.makeContext()
        let (acc, income) = try makeYieldingAsset(ctx)
        let g = TransferGroup(pairedAt: .now); ctx.insert(g)
        // A reinvested dividend arrives rather than being paid out.
        _ = S.makeTx(
            ctx, account: acc, amount: 500, amountEur: 500, direction: .credit,
            bookedAt: day(2026, 4, 1), isTransfer: true, transferGroup: g, category: income)
        try ctx.save()

        let m = try XCTUnwrap(try I.loadMetrics(for: [acc], in: ctx)[acc.id])
        XCTAssertEqual(m.distributionsEur, 0, "nothing was paid out")
        XCTAssertEqual(m.capitalInEur, 25_500)
        XCTAssertEqual(m.valueEur, 25_500)
        XCTAssertEqual(m.totalReturnEur, 0, "arriving money is not a gain")
    }

    func testMetricsDoNotDependOnValuationOrdering() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let acc = Account(
            group: invGroup, space: space, externalId: "x",
            type: .broker, institution: "T", name: "T", currency: "EUR")
        ctx.insert(acc)
        let old = makeValuation(ctx, account: acc, asOf: day(2026, 1, 1), marketValueEur: 1_000)
        let new = makeValuation(ctx, account: acc, asOf: day(2026, 6, 1), marketValueEur: 1_500)
        try ctx.save()

        let bases = [I.AccountBasis(accountId: acc.id)]
        let forwards = I.computeAccountMetrics(bases: bases, valuations: [old, new], legs: [])
        let backwards = I.computeAccountMetrics(bases: bases, valuations: [new, old], legs: [])
        XCTAssertEqual(forwards[acc.id]?.valueEur, 1_500)
        XCTAssertEqual(forwards[acc.id]?.valueEur, backwards[acc.id]?.valueEur)
    }

    // The chart and the account rows are computed by two separate functions; if they ever
    // disagree, one of them is lying to the user.
    func testChartsLastPointAgreesWithTheHeadlineFigures() throws {
        let ctx = try S.makeContext()
        let (bali, income) = try makeYieldingAsset(ctx)
        let space = try XCTUnwrap(bali.space)
        let invGroup = try XCTUnwrap(bali.group)
        let broker = Account(
            group: invGroup, space: space, externalId: "broker",
            type: .broker, institution: "T", name: "Broker", currency: "EUR",
            costBasisOpeningEur: 5_000, costBasisOpeningAt: day(2026, 1, 1))
        ctx.insert(broker)
        _ = makeValuation(ctx, account: broker, asOf: day(2026, 1, 1), marketValueEur: 5_000)
        _ = makeValuation(ctx, account: broker, asOf: day(2026, 5, 1), marketValueEur: 6_000)
        let g = TransferGroup(pairedAt: .now); ctx.insert(g)
        _ = S.makeTx(
            ctx, account: broker, amount: 800, amountEur: 800, direction: .credit,
            bookedAt: day(2026, 6, 1), isTransfer: true, transferGroup: g)
        _ = S.makeTx(
            ctx, account: bali, amount: -250, amountEur: -250, direction: .debit,
            bookedAt: day(2026, 6, 15), isTransfer: true, transferGroup: g, category: income)
        try ctx.save()

        let accounts = [bali, broker]
        let ids = accounts.map(\.id)
        let bases = accounts.map(I.basis(for:))
        let valuations = try I.listValuations(for: ids, in: ctx)
        let legs = try I.listContributionLegs(for: ids, in: ctx)
        let metrics = I.computeAccountMetrics(bases: bases, valuations: valuations, legs: legs)
        let series = I.computePortfolioSeries(bases: bases, valuations: valuations, legs: legs)

        let headlineValue = metrics.values.reduce(Decimal(0)) { $0 + ($1.valueEur ?? 0) }
        let headlineCost = metrics.values.reduce(Decimal(0)) { $0 + ($1.costBasisEur ?? 0) }
        let last = try XCTUnwrap(series.last)
        XCTAssertEqual(last.marketValueEur, headlineValue)
        XCTAssertEqual(last.costBasisEur, headlineCost)
        XCTAssertEqual(headlineValue, 31_800, "25.000 Bali + 6.000 + 800 paid in")
        XCTAssertEqual(headlineCost, 30_800, "25.000 + 5.000 + 800; the payout is not a sale")
    }

    func testCostBasisIsNilWithoutAnOpeningFigure() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let acc = Account(
            group: invGroup, space: space, externalId: "x",
            type: .broker, institution: "T", name: "T", currency: "EUR"
        )
        ctx.insert(acc)
        _ = makeValuation(ctx, account: acc, asOf: day(2026, 1, 1), marketValueEur: 1000)
        try ctx.save()

        // Better no P&L than a P&L invented from a market value pretending to be cost.
        let m = try XCTUnwrap(try I.loadMetrics(for: [acc], in: ctx)[acc.id])
        XCTAssertEqual(m.valueEur, 1000)
        XCTAssertNil(m.costBasisEur)
        XCTAssertNil(m.pnlEur)
    }

    func testComputeAccountMetricsBaselineLatestAndPnl() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let acc = Account(
            group: invGroup, space: space, externalId: "x",
            type: .broker, institution: "T", name: "T", currency: "EUR"
        )
        acc.costBasisOpeningEur = 1000
        acc.costBasisOpeningAt = day(2026, 1, 1)
        ctx.insert(acc)
        let v1 = makeValuation(ctx, account: acc, asOf: day(2026, 1, 1), marketValueEur: 1000)
        let v2 = makeValuation(ctx, account: acc, asOf: day(2026, 6, 1), marketValueEur: 1500, cashValueEur: 300)
        let g = TransferGroup(pairedAt: .now); ctx.insert(g)
        // Deposit AFTER the opening figure → added to cost basis
        let deposit = S.makeTx(
            ctx, account: acc, amount: 200, amountEur: 200, direction: .credit,
            bookedAt: day(2026, 3, 1), isTransfer: true, transferGroup: g
        )
        try ctx.save()
        _ = v1; _ = v2; _ = deposit

        let m = try XCTUnwrap(try I.loadMetrics(for: [acc], in: ctx)[acc.id])
        XCTAssertEqual(m.anchorValueEur, 1500)
        XCTAssertEqual(m.valueEur, 1500, "deposit predates the newest snapshot")
        XCTAssertEqual(m.latestCashEur, 300)
        XCTAssertEqual(m.latestPositionsEur, 1200, "value - cash")
        XCTAssertEqual(m.contributionsSinceValueEur, 0)
        XCTAssertEqual(m.costBasisEur, 1200, "opening + contributions")
        XCTAssertEqual(m.pnlEur, 300, "value - costBasis")
        XCTAssertEqual(m.pnlPct, Decimal(300) / Decimal(1200))
    }

    func testComputeAccountMetricsStrictGreaterThanAnchor() throws {
        // A leg booked at the same instant as the anchor is already inside it.
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let invGroup = makeGroup(ctx, name: "Invest", kind: .investment)
        let acc = Account(
            group: invGroup, space: space, externalId: "x",
            type: .broker, institution: "T", name: "T", currency: "EUR"
        )
        let openingAt = day(2026, 1, 1)
        acc.costBasisOpeningEur = 1000
        acc.costBasisOpeningAt = openingAt
        ctx.insert(acc)
        let latestAt = day(2026, 6, 1)
        _ = makeValuation(ctx, account: acc, asOf: openingAt, marketValueEur: 1000)
        _ = makeValuation(ctx, account: acc, asOf: latestAt, marketValueEur: 1100)
        let g = TransferGroup(pairedAt: .now); ctx.insert(g)
        _ = S.makeTx(
            ctx, account: acc, amount: 500, amountEur: 500, direction: .credit,
            bookedAt: openingAt, isTransfer: true, transferGroup: g
        )
        _ = S.makeTx(
            ctx, account: acc, amount: 300, amountEur: 300, direction: .credit,
            bookedAt: latestAt, isTransfer: true, transferGroup: g
        )
        try ctx.save()

        let m = try XCTUnwrap(try I.loadMetrics(for: [acc], in: ctx)[acc.id])
        XCTAssertEqual(m.contributionsSinceValueEur, 0, "Same-instant leg must be excluded")
        XCTAssertEqual(m.valueEur, 1100)
        XCTAssertEqual(m.costBasisEur, 1300, "opening + the June leg only")
    }

    func testComputeAccountMetricsZeroCostBasisGivesNilPct() {
        let id = UUID()
        let m = I.computeAccountMetrics(
            bases: [.init(accountId: id, costBasisOpeningEur: 0)],
            valuations: [],
            legs: []
        )
        XCTAssertNil(m[id]?.pnlPct)
    }

    // MARK: - computePortfolioSeries (pure)

    func testComputePortfolioSeriesEmptyValuationsReturnsEmpty() {
        let series = I.computePortfolioSeries(
            bases: [.init(accountId: UUID())], valuations: [], legs: []
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
            bases: [.init(accountId: a.id), .init(accountId: b.id)],
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
            bases: [.init(
                accountId: acc.id, costBasisOpeningEur: 1000, costBasisOpeningAt: day(2026, 1, 1)
            )],
            valuations: valuations,
            legs: legs
        )
        // Two valuation dates plus the deposit day, which now gets its own point.
        XCTAssertEqual(series.count, 3)
        XCTAssertEqual(series[0].costBasisEur, 1000, "opening, no legs yet")
        XCTAssertEqual(series[1].costBasisEur, 1200, "deposit day: 1000 + 200")
        XCTAssertEqual(series[1].marketValueEur, 1200, "value steps up with the deposit")
        XCTAssertEqual(series[2].costBasisEur, 1200)
        XCTAssertEqual(series[2].marketValueEur, 1500, "April snapshot supersedes")
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
            bases: [.init(accountId: acc.id)],
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

    func testRecordValuationInsertsThenOverwritesSameDay() throws {
        let ctx = try TransferTestSupport.makeContext()
        let space = TransferTestSupport.makeSpace(ctx)
        let acct = try CoreLogic.Accounts.createManual(
            name: "Broker", institution: "Trading212", currency: "EUR", space: space, in: ctx)

        let day = Date(timeIntervalSince1970: 1_770_000_000)
        try CoreLogic.Investments.recordValuation(
            account: acct, marketValueEur: 100, cashValueEur: 10, asOf: day, in: ctx)
        var all = try ctx.fetch(FetchDescriptor<PortfolioValuation>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].marketValueEur, 100)

        // Same UTC day ⇒ correction, not a second point on the chart.
        try CoreLogic.Investments.recordValuation(
            account: acct, marketValueEur: 250, cashValueEur: nil,
            asOf: day.addingTimeInterval(3_600), in: ctx)
        all = try ctx.fetch(FetchDescriptor<PortfolioValuation>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].marketValueEur, 250)
        XCTAssertNil(all[0].cashValueEur)

        // A different day is a new snapshot.
        try CoreLogic.Investments.recordValuation(
            account: acct, marketValueEur: 300, asOf: day.addingTimeInterval(86_400 * 2), in: ctx)
        all = try ctx.fetch(FetchDescriptor<PortfolioValuation>())
        XCTAssertEqual(all.count, 2)
    }
}
