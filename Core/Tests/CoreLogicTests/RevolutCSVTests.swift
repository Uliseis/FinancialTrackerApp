import XCTest
@testable import CoreLogic

final class RevolutCSVTests: XCTestCase {
    typealias R = CoreLogic.RevolutCSV

    // Ids verified against real statements (2026-07-26 reconciliation).
    func testSlugMatchesWebScheme() {
        XCTAssertEqual(R.slug("El Corte Inglés"), "el-corte-ingle-s")
        XCTAssertEqual(R.slug("Náutico de San Vicente"), "na-utico-de-san-vicente")
        XCTAssertEqual(R.slug("  Coop.vitivinicola Arousan "), "coop-vitivinicola-arousan")
        XCTAssertEqual(R.slug("Uber   *one"), "uber-one")
        XCTAssertEqual(R.slug(String(repeating: "ab-", count: 20)).count, 40)
    }

    func testEarlyMorningMadridChargeKeysToPreviousUTCDay() throws {
        let csv = """
        Type,Started Date,Completed Date,Description,Amount,Fee,Balance
        CARD_PAYMENT,2026-07-26 00:18:00,2026-07-27 10:00:00,Zalando,-16.95,0.00,-100.00
        TRANSFER,2026-08-19 17:55:46,2026-08-19 17:55:46,To EUR,978.74,0.00,85.00
        CARD_PAYMENT,2026-08-19 03:51:07,2026-08-20 11:09:36,Náutico de San Vicente,-8.00,0.00,69.00
        CARD_PAYMENT,2026-08-19 03:54:59,2026-08-20 11:08:44,Náutico de San Vicente,-8.00,0.00,77.00
        """
        let parsed = try R.parse(csv)
        XCTAssertEqual(parsed.skippedTransfers, 1)
        XCTAssertEqual(parsed.errors, [])
        XCTAssertEqual(parsed.rows.map(\.externalId), [
            "revolutcsv:v1:2026-07-25:-16.95:zalando:0",
            "revolutcsv:v1:2026-08-19:-8.00:na-utico-de-san-vicente:0",
            "revolutcsv:v1:2026-08-19:-8.00:na-utico-de-san-vicente:1",
        ])
        XCTAssertEqual(parsed.rows[0].amount, Decimal(string: "-16.95"))
        XCTAssertEqual(parsed.rows[0].startedAt, ISO8601DateFormatter().date(from: "2026-07-25T22:18:00Z"))
        XCTAssertEqual(parsed.rows[0].completedAt, ISO8601DateFormatter().date(from: "2026-07-27T08:00:00Z"))
        XCTAssertEqual(parsed.rows[1].description, "Náutico de San Vicente")
    }

    func testRejectsForeignFormatsAndBadRows() throws {
        XCTAssertThrowsError(try R.parse("Foo,Bar\n1,2"))
        XCTAssertEqual(R.normalizeAmount("1,234.56"), "1234.56")
        XCTAssertEqual(R.normalizeAmount("12,5"), "12.5")
        XCTAssertNil(R.normalizeAmount("1.234,56"))
        let parsed = try R.parse("Type,Started Date,Completed Date,Description,Amount\r\nCARD_PAYMENT,,,\"Quoted, name\",-1.00\r\nCARD_PAYMENT,2026-01-01 12:00:00,,\"Quoted, name\",-1.00\r\n")
        XCTAssertEqual(parsed.errors.count, 1)
        XCTAssertEqual(parsed.rows.first?.description, "Quoted, name")
        XCTAssertEqual(parsed.rows.first?.externalId, "revolutcsv:v1:2026-01-01:-1.00:quoted-name:0")
    }

    func testSkipsNotCompletedAndTopupsAndSubtractsFeeKeepingId() throws {
        let csv = """
        Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance
        CARD_PAYMENT,Current,2026-08-01 12:00:00,,Hotel hold,-80.00,0.00,EUR,REVERTED,
        CARD_PAYMENT,Current,2026-08-02 12:00:00,,Pending,-5.00,0.00,EUR,PENDING,
        TOPUP,Current,2026-08-03 12:00:00,2026-08-03 12:00:00,Top-up,100.00,0.00,EUR,COMPLETED,100.00
        CARD_PAYMENT,Current,2026-08-04 12:00:00,2026-08-05 12:00:00,El Corte Inglés,-10.00,0.25,EUR,completed ,89.75
        """
        let parsed = try R.parse(csv)
        XCTAssertEqual(parsed.skippedNotCompleted, 2)
        XCTAssertEqual(parsed.skippedTransfers, 1)
        XCTAssertEqual(parsed.rows.map(\.externalId), ["revolutcsv:v1:2026-08-04:-10.00:el-corte-ingle-s:0"])
        XCTAssertEqual(parsed.rows[0].amount, Decimal(string: "-10.25"))
    }

    func testParsesWithoutStateOrFeeColumns() throws {
        let parsed = try R.parse("Type,Started Date,Completed Date,Description,Amount\nCARD_PAYMENT,2026-08-04 12:00:00,,Zalando,-16.95")
        XCTAssertEqual(parsed.rows.map(\.amount), [Decimal(string: "-16.95")])
        XCTAssertEqual(parsed.skippedNotCompleted, 0)
    }
}
