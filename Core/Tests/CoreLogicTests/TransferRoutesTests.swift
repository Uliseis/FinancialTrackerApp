import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class TransferRoutesTests: XCTestCase {
    typealias S = TransferTestSupport

    // MARK: - routeMatches

    func testRouteMatchesDisabledRouteIsFalse() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let target = S.makeAccount(ctx, name: "Target", space: space)
        let route = S.makeRoute(ctx, pattern: "rent", target: target, enabled: false)
        let source = S.makeAccount(ctx, name: "Source", space: space)
        let tx = S.makeTx(ctx, account: source, amount: 1, direction: .debit, description: "rent")
        XCTAssertFalse(CoreLogic.TransferRoutes.routeMatches(route: route, tx: tx))
    }

    func testRouteMatchesSourceAccountConstraint() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let allowedSource = S.makeAccount(ctx, name: "Source", space: space)
        let otherSource = S.makeAccount(ctx, name: "Other", space: space)
        let target = S.makeAccount(ctx, name: "Target", space: space)
        let route = S.makeRoute(ctx, pattern: "rent", source: allowedSource, target: target)

        let okTx = S.makeTx(ctx, account: allowedSource, amount: 1, direction: .debit, description: "Rent payment")
        let badTx = S.makeTx(ctx, account: otherSource, amount: 1, direction: .debit, description: "Rent payment")

        XCTAssertTrue(CoreLogic.TransferRoutes.routeMatches(route: route, tx: okTx))
        XCTAssertFalse(CoreLogic.TransferRoutes.routeMatches(route: route, tx: badTx))
    }

    func testRouteMatchesDirectionConstraint() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let source = S.makeAccount(ctx, name: "S", space: space)
        let target = S.makeAccount(ctx, name: "T", space: space)
        let route = S.makeRoute(ctx, pattern: "rent", target: target, direction: .debit)

        let debitTx = S.makeTx(ctx, account: source, amount: 1, direction: .debit, description: "rent")
        let creditTx = S.makeTx(ctx, account: source, amount: 1, direction: .credit, description: "rent")

        XCTAssertTrue(CoreLogic.TransferRoutes.routeMatches(route: route, tx: debitTx))
        XCTAssertFalse(CoreLogic.TransferRoutes.routeMatches(route: route, tx: creditTx))
    }

    // MARK: - mirrorExternalId

    func testMirrorExternalIdFormat() {
        let id = UUID()
        XCTAssertEqual(
            CoreLogic.TransferRoutes.mirrorExternalId(id),
            "mirror:\(id.uuidString)"
        )
    }

    // MARK: - createMirror

    func testCreateMirrorBasicCase() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let source = S.makeAccount(ctx, name: "Source", space: space)
        let target = S.makeAccount(ctx, name: "Target", space: space)
        let route = S.makeRoute(ctx, pattern: "rent", target: target)
        let tx = S.makeTx(
            ctx, account: source, amount: 850, direction: .debit,
            description: "Rent payment", counterparty: "Landlord"
        )
        try ctx.save()

        let result = try CoreLogic.TransferRoutes.createMirror(
            from: tx, to: target, route: route, in: ctx
        )
        XCTAssertNotNil(result)

        let mirrors = try ctx.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.routedFromTx != nil }
        ))
        XCTAssertEqual(mirrors.count, 1)
        let mirror = try XCTUnwrap(mirrors.first)
        XCTAssertEqual(mirror.account?.id, target.id)
        XCTAssertEqual(mirror.amount, Decimal(-850))
        XCTAssertEqual(mirror.direction, .credit)
        XCTAssertEqual(mirror.externalId, "mirror:\(tx.id.uuidString)")
        XCTAssertTrue(mirror.isTransfer)
        XCTAssertNotNil(mirror.transferGroup)
        XCTAssertEqual(mirror.route?.id, route.id)

        XCTAssertTrue(tx.isTransfer, "Source must be flagged as transfer")
        XCTAssertEqual(tx.transferGroup?.id, mirror.transferGroup?.id)
    }

    func testCreateMirrorSameAccountReturnsNil() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let account = S.makeAccount(ctx, name: "A", space: space)
        let tx = S.makeTx(ctx, account: account, amount: 10, direction: .debit)
        XCTAssertNil(try CoreLogic.TransferRoutes.createMirror(from: tx, to: account, in: ctx))
    }

    func testCreateMirrorOnArchivedTargetReturnsNil() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let source = S.makeAccount(ctx, name: "S", space: space)
        let target = S.makeAccount(ctx, name: "T", space: space, archived: true)
        let tx = S.makeTx(ctx, account: source, amount: 10, direction: .debit)
        XCTAssertNil(try CoreLogic.TransferRoutes.createMirror(from: tx, to: target, in: ctx))
    }

    func testCreateMirrorCrossSpaceReturnsNil() throws {
        let ctx = try S.makeContext()
        let s1 = S.makeSpace(ctx, name: "Personal")
        let s2 = S.makeSpace(ctx, name: "Joint")
        let source = S.makeAccount(ctx, name: "S", space: s1)
        let target = S.makeAccount(ctx, name: "T", space: s2)
        let tx = S.makeTx(ctx, account: source, amount: 10, direction: .debit)
        XCTAssertNil(try CoreLogic.TransferRoutes.createMirror(from: tx, to: target, in: ctx))
    }

    func testCreateMirrorIsIdempotent() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let source = S.makeAccount(ctx, name: "S", space: space)
        let target = S.makeAccount(ctx, name: "T", space: space)
        let route = S.makeRoute(ctx, pattern: "rent", target: target)
        let tx = S.makeTx(ctx, account: source, amount: 10, direction: .debit, description: "rent")
        try ctx.save()

        let first = try XCTUnwrap(try CoreLogic.TransferRoutes.createMirror(
            from: tx, to: target, route: route, in: ctx
        ))
        let second = try XCTUnwrap(try CoreLogic.TransferRoutes.createMirror(
            from: tx, to: target, route: route, in: ctx
        ))
        XCTAssertEqual(first.mirrorId, second.mirrorId)
        XCTAssertEqual(first.transferGroupId, second.transferGroupId)

        let mirrors = try ctx.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.routedFromTx != nil }
        ))
        XCTAssertEqual(mirrors.count, 1, "Second call must not create a duplicate mirror")
    }

    func testCreateMirrorRefusesIfSourceIsItselfAMirror() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let a = S.makeAccount(ctx, name: "A", space: space)
        let b = S.makeAccount(ctx, name: "B", space: space)
        let c = S.makeAccount(ctx, name: "C", space: space)
        let original = S.makeTx(ctx, account: a, amount: 10, direction: .debit)
        let mirror = S.makeTx(ctx, account: b, amount: -10, direction: .credit, routedFromTx: original)
        try ctx.save()

        XCTAssertNil(try CoreLogic.TransferRoutes.createMirror(from: mirror, to: c, in: ctx))
    }

    // MARK: - removeMirror

    func testRemoveMirrorDeletesMirrorAndResetsSource() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let source = S.makeAccount(ctx, name: "S", space: space)
        let target = S.makeAccount(ctx, name: "T", space: space)
        let tx = S.makeTx(ctx, account: source, amount: 10, direction: .debit, description: "rent")
        try ctx.save()
        _ = try CoreLogic.TransferRoutes.createMirror(from: tx, to: target, in: ctx)

        let result = try CoreLogic.TransferRoutes.removeMirror(forSource: tx.id, in: ctx)
        XCTAssertEqual(result.deleted, 1)

        let mirrors = try ctx.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.routedFromTx != nil }
        ))
        XCTAssertEqual(mirrors.count, 0)
        XCTAssertFalse(tx.isTransfer)
        XCTAssertNil(tx.transferGroup)
    }

    // MARK: - removeRouteMirrors

    func testRemoveRouteMirrorsScopesToRouteOnly() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let source = S.makeAccount(ctx, name: "S", space: space)
        let target = S.makeAccount(ctx, name: "T", space: space)
        let routeA = S.makeRoute(ctx, pattern: "rent", target: target)
        let routeB = S.makeRoute(ctx, pattern: "salary", target: target)
        let txA = S.makeTx(ctx, account: source, amount: 10, direction: .debit, description: "rent A")
        let txB = S.makeTx(ctx, account: source, amount: 20, direction: .debit, description: "salary B")
        try ctx.save()
        _ = try CoreLogic.TransferRoutes.createMirror(from: txA, to: target, route: routeA, in: ctx)
        _ = try CoreLogic.TransferRoutes.createMirror(from: txB, to: target, route: routeB, in: ctx)

        let result = try CoreLogic.TransferRoutes.removeRouteMirrors(routeId: routeA.id, in: ctx)
        XCTAssertEqual(result.deleted, 1)
        XCTAssertEqual(result.sourcesReset, 1)

        let mirrors = try ctx.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.routedFromTx != nil }
        ))
        XCTAssertEqual(mirrors.count, 1)
        XCTAssertEqual(mirrors.first?.route?.id, routeB.id)
        XCTAssertFalse(txA.isTransfer)
        XCTAssertTrue(txB.isTransfer, "Other route's source must remain flagged")
    }

    // MARK: - apply

    func testApplyCreatesMirrorsForMatchingTxs() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let source = S.makeAccount(ctx, name: "S", space: space)
        let target = S.makeAccount(ctx, name: "T", space: space)
        _ = S.makeRoute(ctx, pattern: "rent", target: target)
        let match1 = S.makeTx(ctx, account: source, amount: 10, direction: .debit, description: "rent A")
        let match2 = S.makeTx(ctx, account: source, amount: 11, direction: .debit, description: "rent B")
        let noMatch = S.makeTx(ctx, account: source, amount: 12, direction: .debit, description: "groceries")
        try ctx.save()

        let result = try CoreLogic.TransferRoutes.apply(in: ctx)
        XCTAssertEqual(result.mirroredCreated, 2)
        XCTAssertTrue(match1.isTransfer)
        XCTAssertTrue(match2.isTransfer)
        XCTAssertFalse(noMatch.isTransfer)
    }

    func testApplyRespectsPriorityOrdering() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let source = S.makeAccount(ctx, name: "S", space: space)
        let targetA = S.makeAccount(ctx, name: "TA", space: space)
        let targetB = S.makeAccount(ctx, name: "TB", space: space)
        _ = S.makeRoute(ctx, pattern: "rent", target: targetA, priority: 1)
        _ = S.makeRoute(ctx, pattern: "rent", target: targetB, priority: 10)
        let tx = S.makeTx(ctx, account: source, amount: 10, direction: .debit, description: "rent")
        try ctx.save()

        _ = try CoreLogic.TransferRoutes.apply(in: ctx)
        let mirrors = try ctx.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.routedFromTx != nil }
        ))
        XCTAssertEqual(mirrors.count, 1)
        XCTAssertEqual(mirrors.first?.account?.id, targetB.id, "Higher-priority route wins")
        _ = tx
    }

    func testApplySkipsAlreadyRoutedTxs() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let source = S.makeAccount(ctx, name: "S", space: space)
        let target = S.makeAccount(ctx, name: "T", space: space)
        _ = S.makeRoute(ctx, pattern: "rent", target: target)
        let tx = S.makeTx(
            ctx, account: source, amount: 10, direction: .debit,
            description: "rent", isTransfer: true
        )
        try ctx.save()

        let result = try CoreLogic.TransferRoutes.apply(in: ctx)
        XCTAssertEqual(result.mirroredCreated, 0)
        _ = tx
    }

    func testApplyFiltersByRouteId() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let source = S.makeAccount(ctx, name: "S", space: space)
        let target = S.makeAccount(ctx, name: "T", space: space)
        let routeA = S.makeRoute(ctx, pattern: "rent", target: target)
        _ = S.makeRoute(ctx, pattern: "salary", target: target)
        _ = S.makeTx(ctx, account: source, amount: 10, direction: .debit, description: "rent A")
        _ = S.makeTx(ctx, account: source, amount: 11, direction: .debit, description: "salary B")
        try ctx.save()

        let result = try CoreLogic.TransferRoutes.apply(in: ctx, routeId: routeA.id)
        XCTAssertEqual(result.mirroredCreated, 1)
    }

    // MARK: - listManualAccountsForRouting

    func testListManualAccountsExcludesArchivedAndConnected() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let conn = Connection(connector: .enablebanking)
        ctx.insert(conn)
        _ = S.makeAccount(ctx, name: "Manual1", space: space)
        _ = S.makeAccount(ctx, name: "Manual2", space: space)
        _ = S.makeAccount(ctx, name: "Connected", space: space, connection: conn)
        _ = S.makeAccount(ctx, name: "Archived", space: space, archived: true)
        try ctx.save()

        let manual = try CoreLogic.TransferRoutes.listManualAccountsForRouting(in: ctx)
        XCTAssertEqual(manual.count, 2)
        XCTAssertEqual(Set(manual.map(\.name)), ["Manual1", "Manual2"])
    }
}
