import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class TransferRouteCRUDTests: XCTestCase {
    typealias S = TransferTestSupport
    typealias R = CoreLogic.TransferRoutes

    // source account A, target account B, same space, one matching debit on A.
    private func fixture() throws -> (ctx: ModelContext, a: Account, b: Account, tx: Transaction) {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let a = S.makeAccount(ctx, name: "A", space: space)
        let b = S.makeAccount(ctx, name: "B", space: space)
        let tx = S.makeTx(ctx, account: a, amount: -100, amountEur: -100, direction: .debit,
                          description: "SAVINGS TRANSFER")
        try ctx.save()
        return (ctx, a, b, tx)
    }

    private func mirrors(in ctx: ModelContext) throws -> [Transaction] {
        try ctx.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.routedFromTx != nil }
        ))
    }

    func testCreateRouteAppliesAndCreatesMirror() throws {
        let f = try fixture()
        let result = try R.createRoute(
            pattern: "SAVINGS", target: f.b, source: f.a, in: f.ctx)
        XCTAssertEqual(result.applied?.mirroredCreated, 1)
        XCTAssertEqual(try mirrors(in: f.ctx).count, 1)
        XCTAssertTrue(f.tx.isTransfer)
    }

    func testCreateRouteDisabledDoesNotApply() throws {
        let f = try fixture()
        let result = try R.createRoute(
            pattern: "SAVINGS", target: f.b, source: f.a, enabled: false, in: f.ctx)
        XCTAssertNil(result.applied)
        XCTAssertTrue(try mirrors(in: f.ctx).isEmpty)
        XCTAssertFalse(f.tx.isTransfer)
    }

    func testCreateRouteRejectsSourceEqualsTarget() throws {
        let f = try fixture()
        XCTAssertThrowsError(try R.createRoute(pattern: "x", target: f.a, source: f.a, in: f.ctx)) {
            XCTAssertEqual($0 as? R.RouteError, .sourceEqualsTarget)
        }
    }

    func testCreateRouteRejectsBlankPattern() throws {
        let f = try fixture()
        XCTAssertThrowsError(try R.createRoute(pattern: "  ", target: f.b, source: f.a, in: f.ctx)) {
            XCTAssertEqual($0 as? R.RouteError, .patternRequired)
        }
    }

    func testUpdateRouteMatcherChangeRemovesOldMirrorsAndReapplies() throws {
        let f = try fixture()
        let route = try R.createRoute(pattern: "SAVINGS", target: f.b, source: f.a, in: f.ctx).route
        XCTAssertEqual(try mirrors(in: f.ctx).count, 1)

        // Pattern no longer matches the tx ⇒ old mirror removed, nothing re-created.
        let result = try R.updateRoute(
            route, pattern: "RENT", target: f.b, source: f.a,
            field: .description, matchType: .contains, direction: nil, enabled: true, in: f.ctx)
        XCTAssertTrue(result.matchersChanged)
        XCTAssertEqual(result.mirrorsRemoved?.deleted, 1)
        XCTAssertEqual(result.reapplied?.mirroredCreated, 0)
        XCTAssertTrue(try mirrors(in: f.ctx).isEmpty)
        XCTAssertFalse(f.tx.isTransfer) // source reset
    }

    func testUpdateRouteDisableRemovesMirrorsWithoutReapply() throws {
        let f = try fixture()
        let route = try R.createRoute(pattern: "SAVINGS", target: f.b, source: f.a, in: f.ctx).route
        let result = try R.updateRoute(
            route, pattern: "SAVINGS", target: f.b, source: f.a,
            field: .description, matchType: .contains, direction: nil, enabled: false, in: f.ctx)
        XCTAssertFalse(result.matchersChanged)
        XCTAssertEqual(result.mirrorsRemoved?.deleted, 1)
        XCTAssertNil(result.reapplied)
        XCTAssertTrue(try mirrors(in: f.ctx).isEmpty)
    }

    func testUpdateRouteNoMatcherChangeKeepsMirrors() throws {
        let f = try fixture()
        let route = try R.createRoute(pattern: "SAVINGS", target: f.b, source: f.a, in: f.ctx).route
        let result = try R.updateRoute(
            route, pattern: "SAVINGS", target: f.b, source: f.a,
            field: .description, matchType: .contains, direction: nil, enabled: true, in: f.ctx)
        XCTAssertFalse(result.matchersChanged)
        XCTAssertNil(result.mirrorsRemoved)
        XCTAssertEqual(try mirrors(in: f.ctx).count, 1)
    }

    func testDeleteRouteRemovesMirrors() throws {
        let f = try fixture()
        let route = try R.createRoute(pattern: "SAVINGS", target: f.b, source: f.a, in: f.ctx).route
        let removed = try R.deleteRoute(route, in: f.ctx)
        XCTAssertEqual(removed.deleted, 1)
        XCTAssertTrue(try mirrors(in: f.ctx).isEmpty)
        XCTAssertTrue(try f.ctx.fetch(FetchDescriptor<TransferRoute>()).isEmpty)
        XCTAssertFalse(f.tx.isTransfer)
    }

    func testReorderRoutesAssignsDescendingPriority() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let target = S.makeAccount(ctx, name: "T", space: space)
        let r1 = try R.createRoute(pattern: "a", target: target, enabled: false, in: ctx).route
        let r2 = try R.createRoute(pattern: "b", target: target, enabled: false, in: ctx).route
        let r3 = try R.createRoute(pattern: "c", target: target, enabled: false, in: ctx).route
        try R.reorderRoutes([r3.id, r1.id, r2.id], in: ctx)
        XCTAssertEqual(r3.priority, 2)
        XCTAssertEqual(r1.priority, 1)
        XCTAssertEqual(r2.priority, 0)
    }
}
