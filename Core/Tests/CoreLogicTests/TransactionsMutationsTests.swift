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

    func testUpdateRewritesSignAndEurAndMarksManualCategory() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let acc = try CoreLogic.Accounts.createManual(
            name: "Cash", institution: "Wallet", currency: "EUR", space: space, in: ctx)
        let cat = CoreModel.Category(name: "Groceries", kind: "expense")
        ctx.insert(cat)
        let tx = try T.createManual(
            account: acc, amount: 10, direction: .debit, bookedAt: .now, in: ctx)
        XCTAssertEqual(tx.amount, -10)
        XCTAssertEqual(tx.categorySource, .bank)

        let when = Date(timeIntervalSince1970: 1_700_000_000)
        try T.update(tx, amount: 25, direction: .credit, bookedAt: when,
                     description: "  Refund  ", counterparty: nil, category: cat, in: ctx)

        XCTAssertEqual(tx.amount, 25)
        XCTAssertEqual(tx.amountEur, 25)
        XCTAssertEqual(tx.direction, .credit)
        XCTAssertEqual(tx.bookedAt, when)
        XCTAssertEqual(tx.transactionDescription, "Refund")
        XCTAssertNil(tx.counterparty)
        XCTAssertEqual(tx.category?.id, cat.id)
        XCTAssertEqual(tx.categorySource, .manual)

        XCTAssertThrowsError(try T.update(tx, amount: 0, direction: .debit, bookedAt: when,
                                          description: nil, counterparty: nil,
                                          category: nil, in: ctx)) {
            XCTAssertEqual($0 as? T.MutationError, .amountMustBePositive)
        }
    }

    func testUpdateKeepsBookedFxRateForForeignCurrency() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let acc = try CoreLogic.Accounts.createManual(
            name: "USD", institution: "Revolut", currency: "USD", space: space, in: ctx)
        let tx = try T.createManual(
            account: acc, amount: 100, direction: .debit, bookedAt: .now, in: ctx)
        tx.fxRateUsed = 2          // 2 USD per EUR
        tx.amountEur = -50

        try T.update(tx, amount: 20, direction: .debit, bookedAt: tx.bookedAt,
                     description: nil, counterparty: nil, category: nil, in: ctx)
        XCTAssertEqual(tx.amount, -20)
        XCTAssertEqual(tx.amountEur, -10)
        XCTAssertEqual(tx.fxRateUsed, 2)
    }

    func testDeleteRefusesTransferLegsAndCascadesMirrors() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let acc = try CoreLogic.Accounts.createManual(
            name: "Cash", institution: "Wallet", currency: "EUR", space: space, in: ctx)
        let source = try T.createManual(
            account: acc, amount: 10, direction: .debit, bookedAt: .now, in: ctx)
        let mirror = try T.createManual(
            account: acc, amount: 10, direction: .credit, bookedAt: .now, in: ctx)
        mirror.routedFromTx = source
        try ctx.save()

        XCTAssertThrowsError(try T.delete(mirror, in: ctx)) {
            XCTAssertEqual($0 as? T.MutationError, .isMirrorLeg)
        }

        // Deleting the source takes its mirror with it.
        try T.delete(source, in: ctx)
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<CoreModel.Transaction>()).isEmpty)
    }

    func testParseAmountHandlesBothSeparatorConventions() throws {
        // The bug this exists for: es-ES reads "42.50" as 42500.
        XCTAssertEqual(T.parseAmount("42.50"), Decimal(string: "42.50"))
        XCTAssertEqual(T.parseAmount("42,50"), Decimal(string: "42.50"))
        XCTAssertEqual(T.parseAmount("1.234,56"), Decimal(string: "1234.56"))
        XCTAssertEqual(T.parseAmount("1,234.56"), Decimal(string: "1234.56"))
        XCTAssertEqual(T.parseAmount("1.234.567,89"), Decimal(string: "1234567.89"))
        XCTAssertEqual(T.parseAmount(" 12,90 € "), Decimal(string: "12.90"))
        XCTAssertEqual(T.parseAmount("7"), 7)
        // Three digits after the only separator is grouping, not cents.
        XCTAssertEqual(T.parseAmount("1.234"), 1234)
        XCTAssertEqual(T.parseAmount("1,234"), 1234)
        XCTAssertNil(T.parseAmount("0"))
        XCTAssertNil(T.parseAmount(""))
        XCTAssertNil(T.parseAmount("abc"))
    }
}
