import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class TransfersListTests: XCTestCase {
    typealias S = TransferTestSupport
    typealias T = CoreLogic.Transfers

    func testListGroupsEmptyStore() throws {
        let ctx = try S.makeContext()
        XCTAssertTrue(try T.listGroups(in: ctx).isEmpty)
    }

    func testListGroupsLegsDebitFirstAndSortedByRecency() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let a = S.makeAccount(ctx, name: "A", space: space)
        let b = S.makeAccount(ctx, name: "B", space: space)

        let old = Date(timeIntervalSince1970: 1_000_000)
        let recent = Date(timeIntervalSince1970: 2_000_000)

        let oldCredit = S.makeTx(ctx, account: b, amount: 10, amountEur: 10,
                                 direction: .credit, bookedAt: old)
        let oldDebit = S.makeTx(ctx, account: a, amount: -10, amountEur: -10,
                                direction: .debit, bookedAt: old)
        _ = try T.pairManual(oldDebit, oldCredit, in: ctx)

        let newDebit = S.makeTx(ctx, account: a, amount: -20, amountEur: -20,
                                direction: .debit, bookedAt: recent)
        let newCredit = S.makeTx(ctx, account: b, amount: 20, amountEur: 20,
                                 direction: .credit, bookedAt: recent)
        _ = try T.pairManual(newDebit, newCredit, in: ctx)

        let listings = try T.listGroups(in: ctx)
        XCTAssertEqual(listings.count, 2)
        XCTAssertEqual(listings[0].latestAt, recent)
        XCTAssertEqual(listings[1].latestAt, old)
        for listing in listings {
            XCTAssertEqual(listing.legs.count, 2)
            XCTAssertEqual(listing.legs.first?.direction, .debit)
            XCTAssertEqual(listing.legs.last?.direction, .credit)
        }
        XCTAssertEqual(listings[0].legs.first?.id, newDebit.id)
    }

    func testListGroupsIncludesRoutedMirrorGroups() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let a = S.makeAccount(ctx, name: "A", space: space)
        let b = S.makeAccount(ctx, name: "B", space: space)
        let source = S.makeTx(ctx, account: a, amount: -50, amountEur: -50,
                              direction: .debit, description: "ROUTED")
        try ctx.save()
        _ = try XCTUnwrap(CoreLogic.TransferRoutes.createMirror(from: source, to: b, in: ctx))

        let listings = try T.listGroups(in: ctx)
        XCTAssertEqual(listings.count, 1)
        XCTAssertEqual(listings[0].legs.count, 2)
        XCTAssertEqual(listings[0].legs.first?.id, source.id)
    }
}
