import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class FXTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema(CoreModelSchema.allTypes)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func loadFixture() throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "ecb-sample", withExtension: "xml", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func day(_ iso: String) -> Date {
        FX.isoDayToDate(iso)!
    }

    func testParseEcbXmlExtractsAllRates() throws {
        let xml = try loadFixture()
        let rates = FX.parseEcbXml(xml)
        XCTAssertEqual(rates.count, 6)
        XCTAssertTrue(rates.contains(EcbRate(date: day("2026-05-15"), currency: "USD", rate: Decimal(string: "1.0856")!)))
        XCTAssertTrue(rates.contains(EcbRate(date: day("2026-05-15"), currency: "JPY", rate: Decimal(string: "167.81")!)))
        XCTAssertTrue(rates.contains(EcbRate(date: day("2026-05-13"), currency: "USD", rate: Decimal(string: "1.0790")!)))
    }

    func testParseEcbXmlIgnoresEmptyOuterCube() throws {
        let xml = try loadFixture()
        let rates = FX.parseEcbXml(xml)
        let dates = Set(rates.map { $0.date })
        XCTAssertEqual(dates.count, 3, "Only inner dated Cube elements should produce rows")
    }

    func testIngestDedupesOnDateCurrency() throws {
        let ctx = try makeContext()
        let xml = try loadFixture()
        let parsed = FX.parseEcbXml(xml)

        let firstRun = try FX.ingest(parsed, in: ctx)
        XCTAssertEqual(firstRun, 6)

        let secondRun = try FX.ingest(parsed, in: ctx)
        XCTAssertEqual(secondRun, 0, "Re-ingest must skip existing (date, currency) pairs")

        let stored = try ctx.fetch(FetchDescriptor<FxRate>())
        XCTAssertEqual(stored.count, 6)
    }

    func testGetRateEurReturnsOne() throws {
        let ctx = try makeContext()
        let rate = try FX.getRate(date: .now, currency: "EUR", in: ctx)
        XCTAssertEqual(rate, 1)
    }

    func testGetRateExactMatch() throws {
        let ctx = try makeContext()
        try FX.ingest(FX.parseEcbXml(try loadFixture()), in: ctx)
        let rate = try FX.getRate(date: day("2026-05-15"), currency: "USD", in: ctx)
        XCTAssertEqual(rate, Decimal(string: "1.0856"))
    }

    func testGetRatePriorDayFallback() throws {
        let ctx = try makeContext()
        try FX.ingest(FX.parseEcbXml(try loadFixture()), in: ctx)
        // No rate published on 2026-05-16 (weekend in our fixture); should fall back to 2026-05-15.
        let rate = try FX.getRate(date: day("2026-05-16"), currency: "USD", in: ctx)
        XCTAssertEqual(rate, Decimal(string: "1.0856"))
    }

    func testGetRateReturnsNilWhenNoData() throws {
        let ctx = try makeContext()
        try FX.ingest(FX.parseEcbXml(try loadFixture()), in: ctx)
        let rate = try FX.getRate(date: day("2025-01-01"), currency: "USD", in: ctx)
        XCTAssertNil(rate, "No rate at or before the requested date should produce nil")
    }

    func testToEurDividesByRate() throws {
        let ctx = try makeContext()
        try FX.ingest(FX.parseEcbXml(try loadFixture()), in: ctx)
        let result = try XCTUnwrap(try FX.toEur(
            amount: Decimal(string: "108.56")!,
            currency: "USD",
            date: day("2026-05-15"),
            in: ctx
        ))
        // 108.56 / 1.0856 = 100.0
        let diff = result.amountEur - Decimal(100)
        XCTAssertLessThan(abs(diff), Decimal(string: "0.0001")!)
        XCTAssertEqual(result.rate, Decimal(string: "1.0856"))
    }

    func testBackfillUpdatesMissingAmounts() throws {
        let ctx = try makeContext()
        try FX.ingest(FX.parseEcbXml(try loadFixture()), in: ctx)

        let account = Account(
            externalId: "test",
            type: .bank,
            institution: "Test",
            name: "USD account",
            currency: "USD"
        )
        ctx.insert(account)
        let tx = Transaction(
            account: account,
            externalId: "tx-1",
            bookedAt: day("2026-05-15"),
            amount: Decimal(string: "108.56")!,
            currency: "USD",
            direction: .debit
        )
        ctx.insert(tx)
        try ctx.save()

        XCTAssertNil(tx.amountEur)

        let result = try FX.backfillTransactionEurAmounts(in: ctx)
        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(tx.amountEur, Decimal(string: "100.00"))
        XCTAssertEqual(tx.fxRateUsed, Decimal(string: "1.0856"))
    }

    func testBackfillSkipsWhenNoRateAvailable() throws {
        let ctx = try makeContext()

        let account = Account(
            externalId: "test",
            type: .bank,
            institution: "Test",
            name: "GBP account",
            currency: "GBP"
        )
        ctx.insert(account)
        let tx = Transaction(
            account: account,
            externalId: "tx-1",
            bookedAt: day("2025-01-01"),
            amount: 50,
            currency: "GBP",
            direction: .debit
        )
        ctx.insert(tx)
        try ctx.save()

        let result = try FX.backfillTransactionEurAmounts(in: ctx)
        XCTAssertEqual(result.updated, 0)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertNil(tx.amountEur)
    }
}
