import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class TransferPairManualTests: XCTestCase {
    typealias S = TransferTestSupport
    typealias T = CoreLogic.Transfers

    private func twoAccounts(sameSpace: Bool = true) throws -> (ctx: ModelContext, a: Account, b: Account) {
        let ctx = try S.makeContext()
        let space1 = S.makeSpace(ctx, name: "One")
        let a = S.makeAccount(ctx, name: "A", space: space1)
        let space2: AccountSpace
        if sameSpace {
            space2 = space1
        } else {
            space2 = AccountSpace(name: "Two")
            ctx.insert(space2)
        }
        let b = S.makeAccount(ctx, name: "B", space: space2)
        return (ctx, a, b)
    }

    func testPairManualHappyPath() throws {
        let f = try twoAccounts()
        let debit = S.makeTx(f.ctx, account: f.a, amount: -100, amountEur: -100, direction: .debit)
        let credit = S.makeTx(f.ctx, account: f.b, amount: 100, amountEur: 100, direction: .credit)
        let group = try T.pairManual(debit, credit, in: f.ctx)
        XCTAssertTrue(debit.isTransfer)
        XCTAssertTrue(credit.isTransfer)
        XCTAssertEqual(debit.transferGroup?.id, group.id)
        XCTAssertEqual(credit.transferGroup?.id, group.id)
        XCTAssertNil(group.pairedAt) // manual ⇒ nil
    }

    func testPairManualReusesExistingGroup() throws {
        let f = try twoAccounts()
        let existing = TransferGroup()
        f.ctx.insert(existing)
        let debit = S.makeTx(f.ctx, account: f.a, amount: -50, amountEur: -50, direction: .debit,
                             transferGroup: existing)
        let credit = S.makeTx(f.ctx, account: f.b, amount: 50, amountEur: 50, direction: .credit)
        let group = try T.pairManual(debit, credit, in: f.ctx)
        XCTAssertEqual(group.id, existing.id)
    }

    func testPairManualRejectsSameDirection() throws {
        let f = try twoAccounts()
        let d1 = S.makeTx(f.ctx, account: f.a, amount: -1, amountEur: -1, direction: .debit)
        let d2 = S.makeTx(f.ctx, account: f.b, amount: -1, amountEur: -1, direction: .debit)
        XCTAssertThrowsError(try T.pairManual(d1, d2, in: f.ctx)) {
            XCTAssertEqual($0 as? T.PairError, .notOneDebitOneCredit)
        }
    }

    func testPairManualRejectsDifferentSpace() throws {
        let f = try twoAccounts(sameSpace: false)
        let debit = S.makeTx(f.ctx, account: f.a, amount: -10, amountEur: -10, direction: .debit)
        let credit = S.makeTx(f.ctx, account: f.b, amount: 10, amountEur: 10, direction: .credit)
        XCTAssertThrowsError(try T.pairManual(debit, credit, in: f.ctx)) {
            XCTAssertEqual($0 as? T.PairError, .differentSpace)
        }
    }

    func testPairManualRejectsArchivedAccount() throws {
        let f = try twoAccounts()
        f.b.archived = true
        let debit = S.makeTx(f.ctx, account: f.a, amount: -10, amountEur: -10, direction: .debit)
        let credit = S.makeTx(f.ctx, account: f.b, amount: 10, amountEur: 10, direction: .credit)
        XCTAssertThrowsError(try T.pairManual(debit, credit, in: f.ctx)) {
            XCTAssertEqual($0 as? T.PairError, .accountArchived)
        }
    }

    func testPairManualRejectsMissingEur() throws {
        let f = try twoAccounts()
        let debit = S.makeTx(f.ctx, account: f.a, amount: -10, currency: "USD", amountEur: nil, direction: .debit)
        let credit = S.makeTx(f.ctx, account: f.b, amount: 10, amountEur: 10, direction: .credit)
        XCTAssertThrowsError(try T.pairManual(debit, credit, in: f.ctx)) {
            XCTAssertEqual($0 as? T.PairError, .missingEurAmount)
        }
    }

    func testPairManualRejectsAmountsDiffer() throws {
        let f = try twoAccounts()
        let debit = S.makeTx(f.ctx, account: f.a, amount: -100, amountEur: -100, direction: .debit)
        let credit = S.makeTx(f.ctx, account: f.b, amount: 90, amountEur: 90, direction: .credit)
        XCTAssertThrowsError(try T.pairManual(debit, credit, in: f.ctx)) {
            XCTAssertEqual($0 as? T.PairError, .amountsDiffer)
        }
    }

    func testPairManualRejectsSharedExpenseMember() throws {
        let f = try twoAccounts()
        let seg = SharedExpenseGroup(label: "Trip", attributionMonth: .now)
        f.ctx.insert(seg)
        let debit = S.makeTx(f.ctx, account: f.a, amount: -10, amountEur: -10, direction: .debit,
                             sharedExpenseGroup: seg)
        let credit = S.makeTx(f.ctx, account: f.b, amount: 10, amountEur: 10, direction: .credit)
        XCTAssertThrowsError(try T.pairManual(debit, credit, in: f.ctx)) {
            XCTAssertEqual($0 as? T.PairError, .inSharedExpenseGroup)
        }
    }

    func testUnpairClearsWholeGroup() throws {
        let f = try twoAccounts()
        let debit = S.makeTx(f.ctx, account: f.a, amount: -100, amountEur: -100, direction: .debit)
        let credit = S.makeTx(f.ctx, account: f.b, amount: 100, amountEur: 100, direction: .credit)
        _ = try T.pairManual(debit, credit, in: f.ctx)
        try T.unpair(debit, in: f.ctx)
        XCTAssertFalse(debit.isTransfer)
        XCTAssertFalse(credit.isTransfer)
        XCTAssertNil(debit.transferGroup)
        XCTAssertNil(credit.transferGroup)
    }

    func testUnpairRemovesRoutedMirrorFromSource() throws {
        let f = try twoAccounts()
        let source = S.makeTx(f.ctx, account: f.a, amount: -100, amountEur: -100, direction: .debit,
                             description: "ROUTED")
        try f.ctx.save()
        let mirror = try XCTUnwrap(CoreLogic.TransferRoutes.createMirror(from: source, to: f.b, in: f.ctx))
        XCTAssertFalse(try f.ctx.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.routedFromTx != nil })).isEmpty)
        try T.unpair(source, in: f.ctx)
        XCTAssertTrue(try f.ctx.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.routedFromTx != nil })).isEmpty)
        XCTAssertFalse(source.isTransfer)
        _ = mirror
    }
}
