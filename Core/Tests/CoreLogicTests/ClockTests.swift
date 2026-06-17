import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class ClockTests: XCTestCase {
    typealias S = TransferTestSupport

    // saveTouchingChanges stamps updatedAt on changed Touchables; plain save() does not
    // (so the sync pull path preserves remote clocks).
    func test_saveTouchingChanges_bumpsUpdatedAt_plainSaveDoesNot() throws {
        let ctx = try S.makeContext()
        let a = S.makeAccount(ctx, name: "A")
        a.createdAt = Date(timeIntervalSince1970: 1_000)
        a.updatedAt = a.createdAt
        try ctx.save()
        XCTAssertEqual(a.updatedAt, Date(timeIntervalSince1970: 1_000),
                       "plain save must not bump the clock (pull path relies on this)")

        a.name = "B"
        try ctx.saveTouchingChanges(now: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(a.updatedAt, Date(timeIntervalSince1970: 2_000),
                       "saveTouchingChanges must advance the clock on edit")
    }

    // A real mutation advances the clock past creation.
    func test_recategorize_advancesTransactionClock() throws {
        let ctx = try S.makeContext()
        let acct = S.makeAccount(ctx, name: "A")
        let tx = S.makeTx(ctx, account: acct, amount: -10, amountEur: -10, direction: .debit)
        tx.createdAt = Date(timeIntervalSince1970: 1_000)
        tx.updatedAt = tx.createdAt
        try ctx.save()
        let cat = try CoreLogic.Categories.create(name: "Food", in: ctx)
        try CoreLogic.Categories.recategorize(tx, to: cat, in: ctx)
        XCTAssertGreaterThan(tx.updatedAt, tx.createdAt,
                             "recategorize must bump the transaction clock")
    }
}
