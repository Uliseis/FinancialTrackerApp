import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class CategoryRulesTests: XCTestCase {
    typealias S = TransferTestSupport
    typealias R = CoreLogic.CategoryRules
    typealias Cat = CoreLogic.Categories

    func testCreateTrimsWithDefaults() throws {
        let ctx = try S.makeContext()
        let cat = try Cat.create(name: "Groceries", in: ctx)
        let rule = try R.create(pattern: "  MERCADONA  ", category: cat, in: ctx)
        XCTAssertEqual(rule.pattern, "MERCADONA")
        XCTAssertEqual(rule.field, .description)
        XCTAssertEqual(rule.matchType, .contains)
        XCTAssertEqual(rule.category?.id, cat.id)
    }

    func testCreateRejectsBlankPattern() throws {
        let ctx = try S.makeContext()
        let cat = try Cat.create(name: "Groceries", in: ctx)
        XCTAssertThrowsError(try R.create(pattern: "  ", category: cat, in: ctx)) {
            XCTAssertEqual($0 as? R.Error, .patternRequired)
        }
    }

    func testUpdateChangesFields() throws {
        let ctx = try S.makeContext()
        let cat1 = try Cat.create(name: "Groceries", in: ctx)
        let cat2 = try Cat.create(name: "Transport", in: ctx)
        let rule = try R.create(pattern: "x", category: cat1, in: ctx)
        try R.update(rule, pattern: "UBER", category: cat2,
                     field: .counterparty, matchType: .startsWith, in: ctx)
        XCTAssertEqual(rule.pattern, "UBER")
        XCTAssertEqual(rule.category?.id, cat2.id)
        XCTAssertEqual(rule.field, .counterparty)
        XCTAssertEqual(rule.matchType, .startsWith)
    }

    func testReorderAssignsDescendingPriorityTopFirst() throws {
        let ctx = try S.makeContext()
        let cat = try Cat.create(name: "C", in: ctx)
        let a = try R.create(pattern: "a", category: cat, priority: 0, in: ctx)
        let b = try R.create(pattern: "b", category: cat, priority: 0, in: ctx)
        let c = try R.create(pattern: "c", category: cat, priority: 0, in: ctx)
        try R.reorder([c.id, a.id, b.id], in: ctx) // c top
        XCTAssertEqual(c.priority, 2)
        XCTAssertEqual(a.priority, 1)
        XCTAssertEqual(b.priority, 0)
    }

    func testDeleteRemovesRuleButKeepsCategory() throws {
        let ctx = try S.makeContext()
        let cat = try Cat.create(name: "Groceries", in: ctx)
        let rule = try R.create(pattern: "x", category: cat, in: ctx)
        try R.delete(rule, in: ctx)
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<CategoryRule>()).isEmpty)
        XCTAssertFalse(try ctx.fetch(FetchDescriptor<CoreModel.Category>()).isEmpty)
    }

    func testApplyRulesRespectsReorderedPriority() throws {
        let ctx = try S.makeContext()
        let groceries = try Cat.create(name: "Groceries", in: ctx)
        let transport = try Cat.create(name: "Transport", in: ctx)
        // Both rules match "UBER EATS"; whichever is higher priority wins.
        let r1 = try R.create(pattern: "UBER", category: transport, in: ctx)
        let r2 = try R.create(pattern: "EATS", category: groceries, in: ctx)
        let acc = S.makeAccount(ctx, name: "Card")
        let tx = S.makeTx(ctx, account: acc, amount: -10, direction: .debit,
                          description: "UBER EATS", categorySource: .bank)
        try R.reorder([r2.id, r1.id], in: ctx) // EATS→groceries on top
        _ = try CoreLogic.Categorize.applyRulesToTransactions(in: ctx)
        XCTAssertEqual(tx.category?.id, groceries.id)
        XCTAssertEqual(tx.categorySource, .rule)
    }

    func testPreviewCountsAndSamples() throws {
        let ctx = try S.makeContext()
        let acc = S.makeAccount(ctx, name: "Card")
        _ = S.makeTx(ctx, account: acc, amount: -1, direction: .debit, description: "MERCADONA A")
        _ = S.makeTx(ctx, account: acc, amount: -2, direction: .debit, description: "mercadona b")
        _ = S.makeTx(ctx, account: acc, amount: -3, direction: .debit, description: "Lidl")
        let preview = try CoreLogic.Categorize.preview(pattern: "mercadona", in: ctx)
        XCTAssertEqual(preview.count, 2)
        XCTAssertEqual(preview.sampleIds.count, 2)
    }

    func testPreviewEmptyPatternIsZero() throws {
        let ctx = try S.makeContext()
        let acc = S.makeAccount(ctx, name: "Card")
        _ = S.makeTx(ctx, account: acc, amount: -1, direction: .debit, description: "X")
        let preview = try CoreLogic.Categorize.preview(pattern: "   ", in: ctx)
        XCTAssertEqual(preview.count, 0)
    }
}
