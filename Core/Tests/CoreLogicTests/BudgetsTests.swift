import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class BudgetsTests: XCTestCase {
    typealias S = TransferTestSupport
    typealias B = CoreLogic.Budgets

    private func midnight(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func noon(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    // MARK: - periodAt

    func testPeriodAtMonthFirstWindow() {
        let r = B.periodAt(startsOn: midnight(2026, 1, 15), period: .month, at: noon(2026, 1, 20))
        XCTAssertEqual(r.start, midnight(2026, 1, 15))
        XCTAssertEqual(r.end, midnight(2026, 2, 15))
    }

    func testPeriodAtMonthLaterWindow() {
        let r = B.periodAt(startsOn: midnight(2026, 1, 15), period: .month, at: noon(2026, 6, 20))
        XCTAssertEqual(r.start, midnight(2026, 6, 15))
        XCTAssertEqual(r.end, midnight(2026, 7, 15))
    }

    func testPeriodAtBeforeAnchorReturnsFirstWindow() {
        let r = B.periodAt(startsOn: midnight(2026, 6, 1), period: .month, at: noon(2026, 5, 1))
        XCTAssertEqual(r.start, midnight(2026, 6, 1))
        XCTAssertEqual(r.end, midnight(2026, 7, 1))
    }

    func testPeriodAtWeek() {
        let r = B.periodAt(startsOn: midnight(2026, 6, 1), period: .week, at: noon(2026, 6, 16))
        XCTAssertEqual(r.start, midnight(2026, 6, 15))
        XCTAssertEqual(r.end, midnight(2026, 6, 22))
    }

    func testPeriodAtYear() {
        let r = B.periodAt(startsOn: midnight(2024, 3, 1), period: .year, at: noon(2026, 5, 1))
        XCTAssertEqual(r.start, midnight(2026, 3, 1))
        XCTAssertEqual(r.end, midnight(2027, 3, 1))
    }

    // MARK: - budgetProgress

    func testBudgetProgressSumsDebitsInWindowAbs() throws {
        let ctx = try S.makeContext()
        let a = S.makeAccount(ctx, name: "Checking")
        let cat = CoreModel.Category(name: "Groceries")
        ctx.insert(cat)
        let budget = Budget(category: cat, amountEur: 400, period: .month, startsOn: midnight(2026, 6, 1))
        ctx.insert(budget)

        let t1 = S.makeTx(ctx, account: a, amount: -100, amountEur: -100, direction: .debit, bookedAt: noon(2026, 6, 5))
        t1.category = cat
        let t2 = S.makeTx(ctx, account: a, amount: -50, amountEur: -50, direction: .debit, bookedAt: noon(2026, 6, 20))
        t2.category = cat
        // credit in category — ignored (not a debit)
        let t3 = S.makeTx(ctx, account: a, amount: 30, amountEur: 30, direction: .credit, bookedAt: noon(2026, 6, 10))
        t3.category = cat
        // out of window
        let t4 = S.makeTx(ctx, account: a, amount: -999, amountEur: -999, direction: .debit, bookedAt: noon(2026, 5, 30))
        t4.category = cat
        // transfer — excluded
        let t5 = S.makeTx(ctx, account: a, amount: -200, amountEur: -200, direction: .debit,
                          bookedAt: noon(2026, 6, 12), isTransfer: true)
        t5.category = cat

        let p = try B.budgetProgress(budget, at: noon(2026, 6, 25), in: ctx)
        XCTAssertEqual(p.spentEur, 150)
        XCTAssertEqual(p.amountEur, 400)
        XCTAssertEqual(p.categoryId, cat.id)
        XCTAssertEqual(p.range.start, midnight(2026, 6, 1))
        XCTAssertEqual(p.range.end, midnight(2026, 7, 1))
    }

    func testBudgetProgressOnlyMatchesBudgetCategory() throws {
        let ctx = try S.makeContext()
        let a = S.makeAccount(ctx, name: "Checking")
        let groceries = CoreModel.Category(name: "Groceries")
        let dining = CoreModel.Category(name: "Dining")
        ctx.insert(groceries)
        ctx.insert(dining)
        let budget = Budget(category: groceries, amountEur: 400, period: .month, startsOn: midnight(2026, 6, 1))
        ctx.insert(budget)

        let inCat = S.makeTx(ctx, account: a, amount: -80, amountEur: -80, direction: .debit, bookedAt: noon(2026, 6, 5))
        inCat.category = groceries
        let otherCat = S.makeTx(ctx, account: a, amount: -300, amountEur: -300, direction: .debit, bookedAt: noon(2026, 6, 6))
        otherCat.category = dining

        let p = try B.budgetProgress(budget, at: noon(2026, 6, 25), in: ctx)
        XCTAssertEqual(p.spentEur, 80)
    }

    func testActiveBudgetsProgressReturnsOnlyActive() throws {
        let ctx = try S.makeContext()
        let cat = CoreModel.Category(name: "Groceries")
        ctx.insert(cat)
        let active = Budget(category: cat, amountEur: 100, period: .month, startsOn: midnight(2026, 6, 1), active: true)
        let inactive = Budget(category: cat, amountEur: 200, period: .month, startsOn: midnight(2026, 6, 1), active: false)
        ctx.insert(active)
        ctx.insert(inactive)

        let rows = try B.activeBudgetsProgress(at: noon(2026, 6, 25), in: ctx)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].budgetId, active.id)
        XCTAssertEqual(rows[0].amountEur, 100)
    }
}
