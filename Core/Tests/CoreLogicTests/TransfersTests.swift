import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class TransfersTests: XCTestCase {
    typealias S = TransferTestSupport

    // MARK: - detect

    func testDetectPairsExactMatchOppositeAccounts() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let a = S.makeAccount(ctx, name: "A", space: space)
        let b = S.makeAccount(ctx, name: "B", space: space)
        let debit = S.makeTx(ctx, account: a, amount: 100, amountEur: 100, direction: .debit)
        let credit = S.makeTx(ctx, account: b, amount: 100, amountEur: 100, direction: .credit)
        try ctx.save()

        let result = try CoreLogic.Transfers.detect(in: ctx)
        XCTAssertEqual(result.matched, 2)
        XCTAssertTrue(debit.isTransfer)
        XCTAssertTrue(credit.isTransfer)
        XCTAssertNotNil(debit.transferGroup)
        XCTAssertEqual(debit.transferGroup?.id, credit.transferGroup?.id)
    }

    func testDetectIgnoresMultiplePartners() throws {
        // Per the TS rule: only match when a debit has exactly one viable credit
        // partner. Ambiguity = leave it to the user.
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let a = S.makeAccount(ctx, name: "A", space: space)
        let b = S.makeAccount(ctx, name: "B", space: space)
        let c = S.makeAccount(ctx, name: "C", space: space)
        let debit = S.makeTx(ctx, account: a, amount: 100, amountEur: 100, direction: .debit)
        let credit1 = S.makeTx(ctx, account: b, amount: 100, amountEur: 100, direction: .credit)
        let credit2 = S.makeTx(ctx, account: c, amount: 100, amountEur: 100, direction: .credit)
        try ctx.save()

        let result = try CoreLogic.Transfers.detect(in: ctx)
        XCTAssertEqual(result.matched, 0)
        XCTAssertFalse(debit.isTransfer)
        XCTAssertFalse(credit1.isTransfer)
        XCTAssertFalse(credit2.isTransfer)
    }

    func testDetectRespectsCrossSpaceBoundary() throws {
        let ctx = try S.makeContext()
        let s1 = S.makeSpace(ctx, name: "Personal")
        let s2 = S.makeSpace(ctx, name: "Joint")
        let a = S.makeAccount(ctx, name: "A", space: s1)
        let b = S.makeAccount(ctx, name: "B", space: s2)
        _ = S.makeTx(ctx, account: a, amount: 100, amountEur: 100, direction: .debit)
        _ = S.makeTx(ctx, account: b, amount: 100, amountEur: 100, direction: .credit)
        try ctx.save()

        let result = try CoreLogic.Transfers.detect(in: ctx)
        XCTAssertEqual(result.matched, 0)
    }

    func testDetectSkipsManualLocks() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let a = S.makeAccount(ctx, name: "A", space: space)
        let b = S.makeAccount(ctx, name: "B", space: space)
        _ = S.makeTx(
            ctx, account: a, amount: 100, amountEur: 100, direction: .debit,
            categorySource: .manual
        )
        _ = S.makeTx(ctx, account: b, amount: 100, amountEur: 100, direction: .credit)
        try ctx.save()

        let result = try CoreLogic.Transfers.detect(in: ctx)
        XCTAssertEqual(result.matched, 0)
    }

    func testDetectRespectsAmountTolerance() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let a = S.makeAccount(ctx, name: "A", space: space)
        let b = S.makeAccount(ctx, name: "B", space: space)
        // Within 0.01 EUR tolerance
        _ = S.makeTx(
            ctx, account: a, amount: Decimal(string: "100.00")!,
            amountEur: Decimal(string: "100.00")!, direction: .debit
        )
        _ = S.makeTx(
            ctx, account: b, amount: Decimal(string: "100.01")!,
            amountEur: Decimal(string: "100.01")!, direction: .credit
        )
        try ctx.save()

        let result = try CoreLogic.Transfers.detect(in: ctx)
        XCTAssertEqual(result.matched, 2, "0.01 EUR diff is within tolerance")
    }

    func testDetectRejectsBeyondTolerance() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let a = S.makeAccount(ctx, name: "A", space: space)
        let b = S.makeAccount(ctx, name: "B", space: space)
        _ = S.makeTx(
            ctx, account: a, amount: Decimal(string: "100.00")!,
            amountEur: Decimal(string: "100.00")!, direction: .debit
        )
        _ = S.makeTx(
            ctx, account: b, amount: Decimal(string: "100.50")!,
            amountEur: Decimal(string: "100.50")!, direction: .credit
        )
        try ctx.save()

        let result = try CoreLogic.Transfers.detect(in: ctx)
        XCTAssertEqual(result.matched, 0)
    }

    func testDetectRespectsTimeWindow() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let a = S.makeAccount(ctx, name: "A", space: space)
        let b = S.makeAccount(ctx, name: "B", space: space)
        let t0 = Date()
        _ = S.makeTx(ctx, account: a, amount: 100, amountEur: 100, direction: .debit, bookedAt: t0)
        _ = S.makeTx(
            ctx, account: b, amount: 100, amountEur: 100, direction: .credit,
            bookedAt: t0.addingTimeInterval(5 * 86_400)
        )
        try ctx.save()

        let result = try CoreLogic.Transfers.detect(in: ctx, sinceDays: 365)
        XCTAssertEqual(result.matched, 0, "5-day gap exceeds PAIR_WINDOW_DAYS=3")
    }

    func testDetectSkipsSharedExpenses() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let a = S.makeAccount(ctx, name: "A", space: space)
        let b = S.makeAccount(ctx, name: "B", space: space)
        let shared = SharedExpenseGroup(label: "Dinner", attributionMonth: .now)
        ctx.insert(shared)
        _ = S.makeTx(
            ctx, account: a, amount: 100, amountEur: 100, direction: .debit,
            sharedExpenseGroup: shared
        )
        _ = S.makeTx(ctx, account: b, amount: 100, amountEur: 100, direction: .credit)
        try ctx.save()

        let result = try CoreLogic.Transfers.detect(in: ctx)
        XCTAssertEqual(result.matched, 0)
    }

    // MARK: - repairGroups

    func testRepairUnflagsCrossSpaceGroup() throws {
        let ctx = try S.makeContext()
        let s1 = S.makeSpace(ctx, name: "Personal")
        let s2 = S.makeSpace(ctx, name: "Joint")
        let a = S.makeAccount(ctx, name: "A", space: s1)
        let b = S.makeAccount(ctx, name: "B", space: s2)
        let group = TransferGroup(pairedAt: .now)
        ctx.insert(group)
        let txA = S.makeTx(ctx, account: a, amount: 100, direction: .debit, isTransfer: true, transferGroup: group)
        let txB = S.makeTx(ctx, account: b, amount: 100, direction: .credit, isTransfer: true, transferGroup: group)
        try ctx.save()

        let result = try CoreLogic.Transfers.repairGroups(in: ctx)
        XCTAssertEqual(result.groupsBroken, 1)
        XCTAssertEqual(result.txsUnflagged, 2)
        XCTAssertFalse(txA.isTransfer)
        XCTAssertFalse(txB.isTransfer)
        XCTAssertNil(txA.transferGroup)
        XCTAssertNil(txB.transferGroup)
    }

    func testRepairUnflagsArchivedGroup() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let alive = S.makeAccount(ctx, name: "Alive", space: space)
        let dead = S.makeAccount(ctx, name: "Dead", space: space, archived: true)
        let group = TransferGroup(pairedAt: .now)
        ctx.insert(group)
        let txA = S.makeTx(ctx, account: alive, amount: 100, direction: .debit, isTransfer: true, transferGroup: group)
        let txB = S.makeTx(ctx, account: dead, amount: 100, direction: .credit, isTransfer: true, transferGroup: group)
        try ctx.save()

        let result = try CoreLogic.Transfers.repairGroups(in: ctx)
        XCTAssertEqual(result.groupsBroken, 1)
        XCTAssertFalse(txA.isTransfer)
        XCTAssertFalse(txB.isTransfer)
    }

    func testRepairPreservesExcludedGroup() throws {
        // The 2026-05-16 regression: `excluded` was conflated with broken.
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let a = S.makeAccount(ctx, name: "A", space: space, excluded: true)
        let b = S.makeAccount(ctx, name: "B", space: space)
        let group = TransferGroup(pairedAt: .now)
        ctx.insert(group)
        let txA = S.makeTx(ctx, account: a, amount: 100, direction: .debit, isTransfer: true, transferGroup: group)
        let txB = S.makeTx(ctx, account: b, amount: 100, direction: .credit, isTransfer: true, transferGroup: group)
        try ctx.save()

        let result = try CoreLogic.Transfers.repairGroups(in: ctx)
        XCTAssertEqual(result.groupsBroken, 0)
        XCTAssertEqual(result.txsUnflagged, 0)
        XCTAssertTrue(txA.isTransfer)
        XCTAssertTrue(txB.isTransfer)
    }

    func testRepairFixesOrphan() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let a = S.makeAccount(ctx, name: "A", space: space)
        let group = TransferGroup(pairedAt: .now)
        ctx.insert(group)
        let orphan = S.makeTx(ctx, account: a, amount: 100, direction: .debit, isTransfer: true, transferGroup: group)
        try ctx.save()

        let result = try CoreLogic.Transfers.repairGroups(in: ctx)
        XCTAssertEqual(result.orphansFixed, 1)
        XCTAssertEqual(result.txsUnflagged, 1)
        XCTAssertFalse(orphan.isTransfer)
        XCTAssertNil(orphan.transferGroup)
    }

    func testRepairDeletesCrossSpaceMirror() throws {
        let ctx = try S.makeContext()
        let s1 = S.makeSpace(ctx, name: "Personal")
        let s2 = S.makeSpace(ctx, name: "Joint")
        let source = S.makeAccount(ctx, name: "S", space: s1)
        let target = S.makeAccount(ctx, name: "T", space: s2)
        let group = TransferGroup(pairedAt: .now)
        ctx.insert(group)
        let src = S.makeTx(
            ctx, account: source, amount: 100, direction: .debit,
            isTransfer: true, transferGroup: group
        )
        let mirror = S.makeTx(
            ctx, account: target, amount: -100, direction: .credit,
            isTransfer: true, transferGroup: group, routedFromTx: src
        )
        try ctx.save()

        let mirrorID = mirror.persistentModelID
        let result = try CoreLogic.Transfers.repairGroups(in: ctx)
        XCTAssertEqual(result.mirrorsDeleted, 1)

        let remaining = try ctx.fetch(FetchDescriptor<Transaction>())
        XCTAssertFalse(remaining.contains { $0.persistentModelID == mirrorID })
        XCTAssertFalse(src.isTransfer, "Source must be reset after its cross-space mirror is deleted")
    }
}
