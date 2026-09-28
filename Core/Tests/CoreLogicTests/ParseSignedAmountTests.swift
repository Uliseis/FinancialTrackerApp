import XCTest
@testable import CoreLogic

// Balances can be negative (a card) or zero (an emptied account). parseAmount refuses both,
// which left Set Current Balance unable to save a card balance at all.
final class ParseSignedAmountTests: XCTestCase {
    private func p(_ s: String) -> Decimal? { CoreLogic.Transactions.parseSignedAmount(s) }

    func testNegativeBalances() {
        XCTAssertEqual(p("-123,4"), Decimal(string: "-123.4"))
        XCTAssertEqual(p("-123.40"), Decimal(string: "-123.4"))
        XCTAssertEqual(p("−1.234,56"), Decimal(string: "-1234.56"))
        XCTAssertEqual(p("- 42,50 €"), Decimal(string: "-42.5"))
    }

    func testZeroAndPositive() {
        XCTAssertEqual(p("0"), 0)
        XCTAssertEqual(p("0,00"), 0)
        XCTAssertEqual(p("+12.5"), Decimal(string: "12.5"))
        XCTAssertEqual(p("1,234.56"), Decimal(string: "1234.56"))
    }

    func testRejectsGarbage() {
        XCTAssertNil(p(""))
        XCTAssertNil(p("-"))
        XCTAssertNil(p("abc"))
        XCTAssertNil(p("--5"))
    }

    func testUnsignedParserStillRejectsNegativeAndZero() {
        XCTAssertNil(CoreLogic.Transactions.parseAmount("-5"))
        XCTAssertNil(CoreLogic.Transactions.parseAmount("0"))
    }
}
