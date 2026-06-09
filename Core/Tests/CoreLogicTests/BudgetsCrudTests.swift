import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class BudgetsCrudTests: XCTestCase {
    typealias S = TransferTestSupport
    typealias B = CoreLogic.Budgets
    typealias Cat = CoreLogic.Categories

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testCreateBudget() throws {
        let ctx = try S.makeContext()
        let cat = try Cat.create(name: "Groceries", in: ctx)
        let budget = try B.create(category: cat, amountEur: 300, startsOn: day(2026, 6, 1), in: ctx)
        XCTAssertEqual(budget.category?.id, cat.id)
        XCTAssertEqual(budget.amountEur, 300)
        XCTAssertEqual(budget.period, .month)
        XCTAssertTrue(budget.active)
    }

    func testUpdateBudget() throws {
        let ctx = try S.makeContext()
        let cat1 = try Cat.create(name: "Groceries", in: ctx)
        let cat2 = try Cat.create(name: "Transport", in: ctx)
        let budget = try B.create(category: cat1, amountEur: 300, startsOn: day(2026, 6, 1), in: ctx)
        try B.update(budget, category: cat2, amountEur: 150, period: .week,
                     startsOn: day(2026, 1, 1), active: false, in: ctx)
        XCTAssertEqual(budget.category?.id, cat2.id)
        XCTAssertEqual(budget.amountEur, 150)
        XCTAssertEqual(budget.period, .week)
        XCTAssertFalse(budget.active)
    }

    func testDeleteBudget() throws {
        let ctx = try S.makeContext()
        let cat = try Cat.create(name: "Groceries", in: ctx)
        let budget = try B.create(category: cat, amountEur: 300, startsOn: day(2026, 6, 1), in: ctx)
        try B.delete(budget, in: ctx)
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<Budget>()).isEmpty)
        XCTAssertFalse(try ctx.fetch(FetchDescriptor<CoreModel.Category>()).isEmpty)
    }
}
