import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class TransferInvariantsTests: XCTestCase {
    typealias S = TransferTestSupport

    func testCleanStateReturnsNoViolations() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let a = S.makeAccount(ctx, name: "A", space: space)
        let b = S.makeAccount(ctx, name: "B", space: space)
        let group = TransferGroup(pairedAt: .now)
        ctx.insert(group)
        _ = S.makeTx(ctx, account: a, amount: 100, direction: .debit, isTransfer: true, transferGroup: group)
        _ = S.makeTx(ctx, account: b, amount: 100, direction: .credit, isTransfer: true, transferGroup: group)
        try ctx.save()

        let violations = try CoreLogic.TransferInvariants.assertAll(in: ctx)
        XCTAssertEqual(violations, [])
        XCTAssertEqual(CoreLogic.TransferInvariants.format(violations), "")
    }

    func testOrphanTransferGroupIsFlagged() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let a = S.makeAccount(ctx, name: "A", space: space)
        let group = TransferGroup(pairedAt: .now)
        ctx.insert(group)
        let orphan = S.makeTx(ctx, account: a, amount: 50, direction: .debit, isTransfer: true, transferGroup: group)
        try ctx.save()

        let v = try CoreLogic.TransferInvariants.orphanTransferGroup(in: ctx)
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "orphan_transfer_group")
        XCTAssertEqual(v?.count, 1)
        XCTAssertEqual(v?.sampleIds, [orphan.id])
    }

    func testOrphanWithMirrorPresentIsNotFlagged() throws {
        // A solo group is acceptable when its sole member is a routed source
        // (the mirror lives elsewhere). The orphan check explicitly ignores
        // mirrors via `routed_from_tx_id IS NULL`.
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let a = S.makeAccount(ctx, name: "A", space: space)
        let b = S.makeAccount(ctx, name: "B", space: space)
        let group = TransferGroup(pairedAt: .now)
        ctx.insert(group)
        let source = S.makeTx(ctx, account: a, amount: 50, direction: .debit, isTransfer: true, transferGroup: group)
        _ = S.makeTx(
            ctx, account: b, amount: -50, direction: .credit,
            isTransfer: true, transferGroup: group, routedFromTx: source
        )
        try ctx.save()

        // Group has 2 members → not size-1, so orphan check naturally passes too.
        XCTAssertNil(try CoreLogic.TransferInvariants.orphanTransferGroup(in: ctx))
    }

    func testMirrorWithUnflaggedSourceIsFlagged() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let a = S.makeAccount(ctx, name: "A", space: space)
        let b = S.makeAccount(ctx, name: "B", space: space)
        let source = S.makeTx(ctx, account: a, amount: 50, direction: .debit, isTransfer: false)
        let mirror = S.makeTx(
            ctx, account: b, amount: -50, direction: .credit,
            isTransfer: true, routedFromTx: source
        )
        try ctx.save()

        let v = try CoreLogic.TransferInvariants.mirrorWithUnflaggedSource(in: ctx)
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "mirror_with_unflagged_source")
        XCTAssertEqual(v?.count, 1)
        XCTAssertEqual(v?.sampleIds, [mirror.id])
    }

    func testDanglingTransferFlagIsFlagged() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let a = S.makeAccount(ctx, name: "A", space: space)
        let dangling = S.makeTx(ctx, account: a, amount: 10, direction: .debit, isTransfer: true)
        try ctx.save()

        let v = try CoreLogic.TransferInvariants.danglingTransferFlag(in: ctx)
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "dangling_transfer_flag")
        XCTAssertEqual(v?.count, 1)
        XCTAssertEqual(v?.sampleIds, [dangling.id])
    }

    func testCrossSpaceTransferGroupIsFlagged() throws {
        let ctx = try S.makeContext()
        let s1 = S.makeSpace(ctx, name: "Personal")
        let s2 = S.makeSpace(ctx, name: "Joint")
        let a = S.makeAccount(ctx, name: "A", space: s1)
        let b = S.makeAccount(ctx, name: "B", space: s2)
        let group = TransferGroup(pairedAt: .now)
        ctx.insert(group)
        _ = S.makeTx(ctx, account: a, amount: 100, direction: .debit, isTransfer: true, transferGroup: group)
        _ = S.makeTx(ctx, account: b, amount: 100, direction: .credit, isTransfer: true, transferGroup: group)
        try ctx.save()

        let v = try CoreLogic.TransferInvariants.crossSpaceTransferGroup(in: ctx)
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "cross_space_transfer_group")
        XCTAssertEqual(v?.count, 2)
    }

    func testTransferOnArchivedAccountIsFlagged() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let dead = S.makeAccount(ctx, name: "Dead", space: space, archived: true)
        let tx = S.makeTx(ctx, account: dead, amount: 10, direction: .debit, isTransfer: true)
        try ctx.save()

        let v = try CoreLogic.TransferInvariants.transferOnArchivedAccount(in: ctx)
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "transfer_on_archived_account")
        XCTAssertEqual(v?.count, 1)
        XCTAssertEqual(v?.sampleIds, [tx.id])
    }

    func testExcludedAccountIsNotFlagged() throws {
        // Regression for the 2026-05-16 incident: `excluded` must not be
        // treated as broken. The archived check must not fire on excluded-only.
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let a = S.makeAccount(ctx, name: "Excluded", space: space, excluded: true)
        let b = S.makeAccount(ctx, name: "Counter", space: space)
        let group = TransferGroup(pairedAt: .now)
        ctx.insert(group)
        _ = S.makeTx(ctx, account: a, amount: 100, direction: .debit, isTransfer: true, transferGroup: group)
        _ = S.makeTx(ctx, account: b, amount: 100, direction: .credit, isTransfer: true, transferGroup: group)
        try ctx.save()

        let violations = try CoreLogic.TransferInvariants.assertAll(in: ctx)
        XCTAssertEqual(violations, [], "excluded-only account must not produce any violation")
    }

    func testFormatJoinsViolations() {
        let id1 = UUID()
        let id2 = UUID()
        let v1 = CoreLogic.TransferInvariants.Violation(
            name: "orphan_transfer_group", count: 1, sampleIds: [id1]
        )
        let v2 = CoreLogic.TransferInvariants.Violation(
            name: "dangling_transfer_flag", count: 2, sampleIds: [id1, id2]
        )
        let out = CoreLogic.TransferInvariants.format([v1, v2])
        XCTAssertTrue(out.contains("orphan_transfer_group=1"))
        XCTAssertTrue(out.contains("dangling_transfer_flag=2"))
        XCTAssertTrue(out.contains("; "))
    }
}
