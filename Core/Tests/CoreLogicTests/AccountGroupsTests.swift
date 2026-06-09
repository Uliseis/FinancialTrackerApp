import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class AccountGroupsTests: XCTestCase {
    typealias S = TransferTestSupport
    typealias G = CoreLogic.AccountGroups

    func testCreateTrimsWithDefaults() throws {
        let ctx = try S.makeContext()
        let g = try G.create(name: "  Savings  ", in: ctx)
        XCTAssertEqual(g.name, "Savings")
        XCTAssertEqual(g.kind, .other)
        XCTAssertNil(g.color)
        XCTAssertEqual(g.sortOrder, 0)
    }

    func testCreateRejectsBlankName() throws {
        let ctx = try S.makeContext()
        XCTAssertThrowsError(try G.create(name: "  ", in: ctx)) {
            XCTAssertEqual($0 as? G.Error, .nameRequired)
        }
    }

    func testUpdateChangesNameKindColor() throws {
        let ctx = try S.makeContext()
        let g = try G.create(name: "Old", kind: .cash, color: "#111111", in: ctx)
        try G.update(g, name: "New", kind: .investment, color: nil, in: ctx)
        XCTAssertEqual(g.name, "New")
        XCTAssertEqual(g.kind, .investment)
        XCTAssertNil(g.color)
    }

    func testUpdateRejectsBlankName() throws {
        let ctx = try S.makeContext()
        let g = try G.create(name: "Keep", in: ctx)
        XCTAssertThrowsError(try G.update(g, name: " ", kind: .other, color: nil, in: ctx)) {
            XCTAssertEqual($0 as? G.Error, .nameRequired)
        }
    }

    func testReorderAssignsSequentialSortOrder() throws {
        let ctx = try S.makeContext()
        let a = try G.create(name: "A", sortOrder: 7, in: ctx)
        let b = try G.create(name: "B", sortOrder: 3, in: ctx)
        let c = try G.create(name: "C", sortOrder: 1, in: ctx)
        try G.reorder([b.id, c.id, a.id], in: ctx)
        XCTAssertEqual(b.sortOrder, 0)
        XCTAssertEqual(c.sortOrder, 1)
        XCTAssertEqual(a.sortOrder, 2)
    }

    func testDeleteDetachesAccountsButKeepsThem() throws {
        let ctx = try S.makeContext()
        let g = try G.create(name: "Cash", in: ctx)
        let account = S.makeAccount(ctx, name: "Wallet")
        account.group = g
        try ctx.save()
        try G.delete(g, in: ctx)
        XCTAssertNil(account.group)
        let remaining = try ctx.fetch(FetchDescriptor<Account>())
        XCTAssertTrue(remaining.contains { $0.id == account.id })
        let groups = try ctx.fetch(FetchDescriptor<AccountGroup>())
        XCTAssertFalse(groups.contains { $0.id == g.id })
    }
}
