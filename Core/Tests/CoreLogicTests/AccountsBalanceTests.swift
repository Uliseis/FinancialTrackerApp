import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class AccountsBalanceTests: XCTestCase {
    typealias S = TransferTestSupport
    typealias A = CoreLogic.Accounts

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testConnectedNoAnchorUsesStoredBalance() throws {
        let ctx = try S.makeContext()
        let conn = Connection(connector: .enablebanking)
        ctx.insert(conn)
        let a = S.makeAccount(ctx, name: "Bank", connection: conn)
        a.balance = 1000
        // tx is ignored for connected-no-anchor accounts (bank balance is authoritative).
        _ = S.makeTx(ctx, account: a, amount: -50, amountEur: -50, direction: .debit)
        let m = try A.computeEurBalances([a], in: ctx)
        XCTAssertEqual(m[a.id], 1000)
    }

    func testManualNoAnchorOpeningPlusAllTx() throws {
        let ctx = try S.makeContext()
        let a = S.makeAccount(ctx, name: "Cash") // no connection ⇒ manual
        a.manualOpeningBalance = 100
        _ = S.makeTx(ctx, account: a, amount: 50, amountEur: 50, direction: .credit)
        _ = S.makeTx(ctx, account: a, amount: -30, amountEur: -30, direction: .debit)
        let m = try A.computeEurBalances([a], in: ctx)
        XCTAssertEqual(m[a.id], 120) // 100 + 50 - 30
    }

    func testAnchorPlusTxSinceAnchorOnly() throws {
        let ctx = try S.makeContext()
        let conn = Connection(connector: .enablebanking)
        ctx.insert(conn)
        let a = S.makeAccount(ctx, name: "Anchored", connection: conn)
        a.balanceAnchor = 200
        a.balanceAnchorAt = day(2026, 1, 1)
        // before the anchor ⇒ excluded
        _ = S.makeTx(ctx, account: a, amount: -10, amountEur: -10, direction: .debit,
                     bookedAt: day(2025, 12, 31))
        // on/after the anchor ⇒ included
        _ = S.makeTx(ctx, account: a, amount: 25, amountEur: 25, direction: .credit,
                     bookedAt: day(2026, 1, 2))
        let m = try A.computeEurBalances([a], in: ctx)
        XCTAssertEqual(m[a.id], 225) // 200 + 25
    }

    func testEurConversionDividesByLatestRate() throws {
        let ctx = try S.makeContext()
        ctx.insert(FxRate(date: day(2020, 1, 1), currency: "USD",
                          rate: Decimal(string: "1.25")!))
        let conn = Connection(connector: .enablebanking)
        ctx.insert(conn)
        let a = S.makeAccount(ctx, name: "USD", connection: conn)
        a.currency = "USD"
        a.balance = 125
        let m = try A.computeEurBalances([a], in: ctx)
        XCTAssertEqual(m[a.id], 100) // 125 USD / 1.25 = 100 EUR
    }

    func testNativeBalanceOmitsConnectedNilBalance() throws {
        let ctx = try S.makeContext()
        let conn = Connection(connector: .enablebanking)
        ctx.insert(conn)
        let a = S.makeAccount(ctx, name: "NoBal", connection: conn) // balance nil, no anchor
        let m = A.computeNativeBalances([a], in: ctx)
        XCTAssertNil(m[a.id])
    }

    func testNativeManualOpeningPlusAllTx() throws {
        let ctx = try S.makeContext()
        let a = S.makeAccount(ctx, name: "Cash")
        a.manualOpeningBalance = 100
        _ = S.makeTx(ctx, account: a, amount: 40, amountEur: 40, direction: .credit)
        let m = A.computeNativeBalances([a], in: ctx)
        XCTAssertEqual(m[a.id], 140)
    }
}
