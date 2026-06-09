import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class SpacesTests: XCTestCase {
    typealias S = TransferTestSupport
    typealias Sp = CoreLogic.Spaces

    func testEnsureDefaultCreatesIndividualWhenNone() throws {
        let ctx = try S.makeContext()
        let d = try Sp.ensureDefault(in: ctx)
        XCTAssertEqual(d.name, "Individual")
        XCTAssertTrue(d.isDefault)
        XCTAssertEqual(d.sortOrder, 0)
    }

    func testEnsureDefaultIsIdempotent() throws {
        let ctx = try S.makeContext()
        let first = try Sp.ensureDefault(in: ctx)
        let second = try Sp.ensureDefault(in: ctx)
        XCTAssertEqual(first.id, second.id)
        let all = try ctx.fetch(FetchDescriptor<AccountSpace>())
        XCTAssertEqual(all.count, 1)
    }

    func testEnsureDefaultReturnsExistingDefault() throws {
        let ctx = try S.makeContext()
        let existing = AccountSpace(name: "Home", isDefault: true)
        ctx.insert(existing)
        try ctx.save()
        let d = try Sp.ensureDefault(in: ctx)
        XCTAssertEqual(d.id, existing.id)
    }

    func testCreateTrimsAndIsNotDefault() throws {
        let ctx = try S.makeContext()
        let s = try Sp.create(name: "  Travel  ", color: "#ff0000", in: ctx)
        XCTAssertEqual(s.name, "Travel")
        XCTAssertEqual(s.color, "#ff0000")
        XCTAssertFalse(s.isDefault)
    }

    func testCreateRejectsBlankName() throws {
        let ctx = try S.makeContext()
        XCTAssertThrowsError(try Sp.create(name: "   ", in: ctx)) {
            XCTAssertEqual($0 as? Sp.Error, .nameRequired)
        }
    }

    func testUpdateRenamesAndSetsColor() throws {
        let ctx = try S.makeContext()
        let s = try Sp.create(name: "Old", color: "#111111", in: ctx)
        try Sp.update(s, name: "  New  ", color: nil, in: ctx)
        XCTAssertEqual(s.name, "New")
        XCTAssertNil(s.color)
    }

    func testUpdateRejectsBlankName() throws {
        let ctx = try S.makeContext()
        let s = try Sp.create(name: "Keep", in: ctx)
        XCTAssertThrowsError(try Sp.update(s, name: "", color: nil, in: ctx)) {
            XCTAssertEqual($0 as? Sp.Error, .nameRequired)
        }
    }

    func testReorderAssignsSequentialSortOrder() throws {
        let ctx = try S.makeContext()
        let a = try Sp.create(name: "A", sortOrder: 5, in: ctx)
        let b = try Sp.create(name: "B", sortOrder: 9, in: ctx)
        let c = try Sp.create(name: "C", sortOrder: 2, in: ctx)
        try Sp.reorder([c.id, a.id, b.id], in: ctx)
        XCTAssertEqual(c.sortOrder, 0)
        XCTAssertEqual(a.sortOrder, 1)
        XCTAssertEqual(b.sortOrder, 2)
    }

    func testSetDefaultIsExclusive() throws {
        let ctx = try S.makeContext()
        let first = try Sp.ensureDefault(in: ctx)
        let other = try Sp.create(name: "Other", in: ctx)
        try Sp.setDefault(other, in: ctx)
        XCTAssertTrue(other.isDefault)
        XCTAssertFalse(first.isDefault)
        let defaults = try ctx.fetch(FetchDescriptor<AccountSpace>()).filter { $0.isDefault }
        XCTAssertEqual(defaults.count, 1)
    }

    func testDeleteDefaultThrows() throws {
        let ctx = try S.makeContext()
        let d = try Sp.ensureDefault(in: ctx)
        XCTAssertThrowsError(try Sp.delete(d, in: ctx)) {
            XCTAssertEqual($0 as? Sp.Error, .cannotDeleteDefault)
        }
    }

    func testDeleteReassignsAccountsToDefault() throws {
        let ctx = try S.makeContext()
        let def = try Sp.ensureDefault(in: ctx)
        let victim = try Sp.create(name: "Victim", in: ctx)
        let account = S.makeAccount(ctx, name: "Checking", space: victim)
        try ctx.save()
        try Sp.delete(victim, in: ctx)
        XCTAssertEqual(account.space?.id, def.id)
        let remaining = try ctx.fetch(FetchDescriptor<AccountSpace>())
        XCTAssertFalse(remaining.contains { $0.id == victim.id })
    }
}
