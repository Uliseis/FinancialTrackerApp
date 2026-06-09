import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class CategoriesTests: XCTestCase {
    typealias S = TransferTestSupport
    typealias C = CoreLogic.Categories

    func testCreateTrimsAndStoresKind() throws {
        let ctx = try S.makeContext()
        let cat = try C.create(name: "  Salary  ", kind: .income, color: "#22c55e", in: ctx)
        XCTAssertEqual(cat.name, "Salary")
        XCTAssertEqual(cat.kind, "income")
        XCTAssertEqual(cat.color, "#22c55e")
    }

    func testCreateRejectsBlankName() throws {
        let ctx = try S.makeContext()
        XCTAssertThrowsError(try C.create(name: " ", in: ctx)) {
            XCTAssertEqual($0 as? C.Error, .nameRequired)
        }
    }

    func testUpdateChangesFieldsAndParent() throws {
        let ctx = try S.makeContext()
        let parent = try C.create(name: "Food", in: ctx)
        let child = try C.create(name: "Snacks", kind: .expense, in: ctx)
        try C.update(child, name: "Groceries", kind: .expense, parent: parent, color: "#abc", in: ctx)
        XCTAssertEqual(child.name, "Groceries")
        XCTAssertEqual(child.parent?.id, parent.id)
    }

    func testUpdateRejectsSelfParent() throws {
        let ctx = try S.makeContext()
        let cat = try C.create(name: "Food", in: ctx)
        XCTAssertThrowsError(try C.update(cat, name: "Food", kind: .expense, parent: cat, color: nil, in: ctx)) {
            XCTAssertEqual($0 as? C.Error, .cannotParentToSelf)
        }
    }

    func testDeleteNullifiesTransactionCategoryAndDetachesChildren() throws {
        let ctx = try S.makeContext()
        let parent = try C.create(name: "Food", in: ctx)
        let child = try C.create(name: "Snacks", parent: parent, in: ctx)
        let a = S.makeAccount(ctx, name: "Cash")
        let tx = S.makeTx(ctx, account: a, amount: -10, direction: .debit)
        tx.category = parent
        try ctx.save()
        try C.delete(parent, in: ctx)
        XCTAssertNil(tx.category)
        XCTAssertNil(child.parent)
        let remaining = try ctx.fetch(FetchDescriptor<CoreModel.Category>())
        XCTAssertTrue(remaining.contains { $0.id == child.id })
        XCTAssertFalse(remaining.contains { $0.id == parent.id })
    }

    func testRecategorizeSetsManualSource() throws {
        let ctx = try S.makeContext()
        let cat = try C.create(name: "Groceries", in: ctx)
        let a = S.makeAccount(ctx, name: "Cash")
        let tx = S.makeTx(ctx, account: a, amount: -10, direction: .debit,
                          categorySource: .bank)
        try C.recategorize(tx, to: cat, in: ctx)
        XCTAssertEqual(tx.category?.id, cat.id)
        XCTAssertEqual(tx.categorySource, .manual)
    }

    func testRecategorizeToNilStillManual() throws {
        let ctx = try S.makeContext()
        let cat = try C.create(name: "Groceries", in: ctx)
        let a = S.makeAccount(ctx, name: "Cash")
        let tx = S.makeTx(ctx, account: a, amount: -10, direction: .debit)
        tx.category = cat
        try ctx.save()
        try C.recategorize(tx, to: nil, in: ctx)
        XCTAssertNil(tx.category)
        XCTAssertEqual(tx.categorySource, .manual)
    }

    func testBulkRecategorize() throws {
        let ctx = try S.makeContext()
        let cat = try C.create(name: "Groceries", in: ctx)
        let a = S.makeAccount(ctx, name: "Cash")
        let txs = (0..<3).map { _ in
            S.makeTx(ctx, account: a, amount: -10, direction: .debit, categorySource: .rule)
        }
        try C.recategorize(txs, to: cat, in: ctx)
        for tx in txs {
            XCTAssertEqual(tx.category?.id, cat.id)
            XCTAssertEqual(tx.categorySource, .manual)
        }
    }
}
