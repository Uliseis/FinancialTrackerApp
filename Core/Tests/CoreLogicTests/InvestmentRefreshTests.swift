import XCTest
import SwiftData
import CoreModel
import CoreIntegrations
@testable import CoreLogic

final class InvestmentRefreshTests: XCTestCase {
    private typealias R = CoreLogic.InvestmentRefresh
    private typealias S = TransferTestSupport

    // Regression: parseAmount reads "0,06033031" as 6033031 — its 1-2-digits rule treats that
    // comma as grouping, which is right for money and catastrophic for a BTC holding.
    func testParseQuantityKeepsEightDecimals() {
        let q = CoreLogic.Transactions.parseQuantity("0,06033031")
        XCTAssertEqual(q, Decimal(string: "0.06033031"))
        XCTAssertEqual(CoreLogic.Transactions.parseQuantity("0.06033031"), q)
        XCTAssertNotEqual(CoreLogic.Transactions.parseAmount("0,06033031"), q, "the money parser is the bug")
    }

    func testParseQuantityTreatsTheLastSeparatorAsDecimal() {
        XCTAssertEqual(CoreLogic.Transactions.parseQuantity("1.234,5"), Decimal(string: "1234.5"))
        XCTAssertEqual(CoreLogic.Transactions.parseQuantity("1,234.5"), Decimal(string: "1234.5"))
        XCTAssertEqual(CoreLogic.Transactions.parseQuantity("12"), 12)
        XCTAssertNil(CoreLogic.Transactions.parseQuantity(""))
        XCTAssertNil(CoreLogic.Transactions.parseQuantity("0"))
        XCTAssertNil(CoreLogic.Transactions.parseQuantity("abc"))
    }

    func testImplausibleGuardCatchesOrdersOfMagnitude() {
        XCTAssertTrue(R.isImplausible(345_035_075_921, previous: 4049), "the 6033031-BTC case")
        XCTAssertTrue(R.isImplausible(40, previous: 4049), "a 100x drop is equally suspect")
        XCTAssertFalse(R.isImplausible(4500, previous: 4049), "a real market move")
        XCTAssertFalse(R.isImplausible(4049, previous: nil), "nothing to compare against")
        XCTAssertFalse(R.isImplausible(4049, previous: 0))
    }

    @MainActor
    func testRefreshRefusesToWriteAnImplausibleValue() async throws {
        let ctx = try S.makeContext()
        let acc = Account(
            externalId: "x", type: .broker, institution: "R", name: "Crypto", currency: "EUR",
            liveValueSource: "crypto:bitcoin", assetQuantity: 6_033_031)
        ctx.insert(acc)
        ctx.insert(PortfolioValuation(
            account: acc, asOf: Date.now.addingTimeInterval(-86_400 * 3), marketValueEur: 4049))
        try ctx.save()

        let outcome = await R.run(in: ctx, crypto: StubPrices(["bitcoin": 57_000]))
        XCTAssertTrue(outcome.updated.isEmpty)
        XCTAssertEqual(outcome.failures.count, 1)
        XCTAssertTrue(outcome.failures[0].contains("far from the last"))
        let all = try CoreLogic.Investments.listValuations(for: [acc.id], in: ctx)
        XCTAssertEqual(all.count, 1, "the bad reading must not be stored")
    }

    @MainActor
    func testGuardComparesAgainstYesterdaySoTodayCanBeCorrected() async throws {
        let ctx = try S.makeContext()
        let acc = Account(
            externalId: "x", type: .broker, institution: "R", name: "Crypto", currency: "EUR",
            liveValueSource: "crypto:bitcoin", assetQuantity: Decimal(string: "0.07"))
        ctx.insert(acc)
        ctx.insert(PortfolioValuation(
            account: acc, asOf: Date.now.addingTimeInterval(-86_400), marketValueEur: 4000))
        // A bad value already written today, as happened on the device.
        ctx.insert(PortfolioValuation(account: acc, asOf: .now, marketValueEur: 345_035_075_921))
        try ctx.save()

        let outcome = await R.run(in: ctx, crypto: StubPrices(["bitcoin": 57_000]))
        XCTAssertEqual(outcome.updated, [acc.id])
        let all = try CoreLogic.Investments.listValuations(for: [acc.id], in: ctx)
        XCTAssertEqual(all.last?.marketValueEur, 3990, "today's bad row is overwritten")
    }

    func testCoinIdParsing() {
        XCTAssertEqual(R.coinId(from: "crypto:bitcoin"), "bitcoin")
        XCTAssertNil(R.coinId(from: "crypto:"), "empty id is not a source")
        XCTAssertNil(R.coinId(from: "t212"))
        XCTAssertNil(R.coinId(from: nil))
    }

    @MainActor
    func testLiveValuedAccountsSkipsArchivedAndUnsourced() throws {
        let ctx = try S.makeContext()
        let live = Account(
            externalId: "a", type: .broker, institution: "T", name: "Live", currency: "EUR",
            liveValueSource: "t212")
        let manual = Account(
            externalId: "b", type: .broker, institution: "M", name: "Manual", currency: "EUR")
        let archived = Account(
            externalId: "c", type: .broker, institution: "X", name: "Old", currency: "EUR",
            archived: true, liveValueSource: "crypto:bitcoin")
        ctx.insert(live); ctx.insert(manual); ctx.insert(archived)
        try ctx.save()

        let found = try R.liveValuedAccounts(in: ctx)
        XCTAssertEqual(found.map(\.name), ["Live"])
    }

    @MainActor
    func testRefreshRecordsCryptoValueFromQuantityTimesPrice() async throws {
        let ctx = try S.makeContext()
        let acc = Account(
            externalId: "x", type: .broker, institution: "R", name: "Crypto", currency: "EUR",
            liveValueSource: "crypto:bitcoin", assetQuantity: Decimal(string: "0.05"))
        ctx.insert(acc)
        try ctx.save()

        let outcome = await R.run(in: ctx, crypto: StubPrices(["bitcoin": 60_000]))
        XCTAssertEqual(outcome.updated, [acc.id])
        let v = try XCTUnwrap(CoreLogic.Investments.listValuations(for: [acc.id], in: ctx).last)
        XCTAssertEqual(v.marketValueEur, 3000)
    }

    @MainActor
    func testRefreshReportsAccountsMissingAQuantity() async throws {
        let ctx = try S.makeContext()
        let acc = Account(
            externalId: "x", type: .broker, institution: "R", name: "Crypto", currency: "EUR",
            liveValueSource: "crypto:bitcoin")
        ctx.insert(acc)
        try ctx.save()

        let outcome = await R.run(in: ctx, crypto: StubPrices(["bitcoin": 60_000]))
        XCTAssertTrue(outcome.updated.isEmpty)
        XCTAssertEqual(outcome.failures.count, 1)
        XCTAssertTrue(outcome.failures[0].contains("no quantity"))
    }

    @MainActor
    func testRefreshTwiceInADayOverwritesRatherThanStacking() async throws {
        let ctx = try S.makeContext()
        let acc = Account(
            externalId: "x", type: .broker, institution: "R", name: "Crypto", currency: "EUR",
            liveValueSource: "crypto:bitcoin", assetQuantity: 1)
        ctx.insert(acc)
        try ctx.save()

        _ = await R.run(in: ctx, crypto: StubPrices(["bitcoin": 50_000]))
        _ = await R.run(in: ctx, crypto: StubPrices(["bitcoin": 51_000]))
        let all = try CoreLogic.Investments.listValuations(for: [acc.id], in: ctx)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].marketValueEur, 51_000)
    }
}

// Serves canned prices instead of hitting CoinGecko.
private struct StubPrices: CryptoPriceSource {
    let stub: [String: Decimal]
    init(_ stub: [String: Decimal]) { self.stub = stub }
    func prices(for coinIds: [String]) async throws -> [String: Decimal] {
        stub.filter { coinIds.contains($0.key) }
    }
}
