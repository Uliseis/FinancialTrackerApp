import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class TransactionsMutationsTests: XCTestCase {
    typealias S = TransferTestSupport
    typealias T = CoreLogic.Transactions

    func testCreateManualInsertsDebitWithManualPrefixAndEurBackfill() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let acct = try CoreLogic.Accounts.createManual(
            name: "Revolut Credit Card", institution: "Revolut", currency: "EUR",
            space: space, in: ctx)
        let tx = try T.createManual(
            account: acct, amount: 14.20, bookedAt: .now,
            description: "  Mercadona  ", counterparty: "Mercadona", in: ctx)
        XCTAssertTrue(tx.externalId.hasPrefix("manual-tx:"))
        XCTAssertEqual(tx.direction, .debit)
        // Magnitude in, signed out: a debit is stored negative to match the store's convention.
        XCTAssertEqual(tx.amount, -14.20)
        XCTAssertEqual(tx.amountEur, -14.20)
        XCTAssertEqual(tx.fxRateUsed, 1)
        XCTAssertEqual(tx.transactionDescription, "Mercadona")
        // No category chosen ⇒ .bank so the rule engine can still classify it.
        XCTAssertEqual(tx.categorySource, .bank)
        XCTAssertEqual(tx.account?.id, acct.id)
    }

    func testCreateManualCreditStaysPositive() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let acct = try CoreLogic.Accounts.createManual(
            name: "Revolut Credit Card", institution: "Revolut", currency: "EUR",
            space: space, in: ctx)
        let tx = try T.createManual(
            account: acct, amount: 30, direction: .credit, bookedAt: .now, in: ctx)
        XCTAssertEqual(tx.amount, 30)
        XCTAssertEqual(tx.amountEur, 30)
    }

    func testCreateManualRejectsNonPositive() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let acct = try CoreLogic.Accounts.createManual(
            name: "Revolut Credit Card", institution: "Revolut", space: space, in: ctx)
        XCTAssertThrowsError(try T.createManual(account: acct, amount: 0, bookedAt: .now, in: ctx)) {
            XCTAssertEqual($0 as? T.MutationError, .amountMustBePositive)
        }
    }
}
