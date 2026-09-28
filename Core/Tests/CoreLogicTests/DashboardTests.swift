import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class DashboardTests: XCTestCase {
    typealias S = TransferTestSupport
    typealias D = CoreLogic.Dashboard

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private let now2606 = { () -> Date in
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!
    }()

    // MARK: - monthStart

    func testMonthStartOffsets() {
        let d = day(2026, 6, 15)
        XCTAssertEqual(D.monthStart(d), day(2026, 6, 1).addingTimeInterval(-12 * 3600))
        XCTAssertEqual(D.monthStart(d, offset: -1), day(2026, 5, 1).addingTimeInterval(-12 * 3600))
        XCTAssertEqual(D.monthStart(d, offset: 1), day(2026, 7, 1).addingTimeInterval(-12 * 3600))
    }

    // MARK: - monthlyCashFlow

    func testCashFlowIncomeAndExpenseThisMonth() throws {
        let ctx = try S.makeContext()
        let a = S.makeAccount(ctx, name: "Checking")
        _ = S.makeTx(ctx, account: a, amount: 2000, amountEur: 2000, direction: .credit, bookedAt: now2606)
        _ = S.makeTx(ctx, account: a, amount: -500, amountEur: -500, direction: .debit, bookedAt: now2606)
        let flow = try D.monthlyCashFlow(
            months: 1, accountIds: [a.id], incomeAccountIds: [a.id], now: now2606, in: ctx)
        XCTAssertEqual(flow.count, 1)
        XCTAssertEqual(flow[0].income, 2000)
        XCTAssertEqual(flow[0].expense, 500)
    }

    func testCashFlowExcludesTransfers() throws {
        let ctx = try S.makeContext()
        let a = S.makeAccount(ctx, name: "Checking")
        _ = S.makeTx(ctx, account: a, amount: -500, amountEur: -500, direction: .debit,
                     bookedAt: now2606, isTransfer: true)
        let flow = try D.monthlyCashFlow(
            months: 1, accountIds: [a.id], incomeAccountIds: [a.id], now: now2606, in: ctx)
        XCTAssertEqual(flow[0].expense, 0)
    }

    func testCashFlowIncomeRequiresIncomeAccount() throws {
        let ctx = try S.makeContext()
        let creditGroup = AccountGroup(name: "Cards", kind: .credit)
        ctx.insert(creditGroup)
        let card = S.makeAccount(ctx, name: "Card")
        card.group = creditGroup
        _ = S.makeTx(ctx, account: card, amount: 100, amountEur: 100, direction: .credit, bookedAt: now2606)
        let incomeIds = D.incomeAccountIds(from: [card])
        XCTAssertTrue(incomeIds.isEmpty)
        let flow = try D.monthlyCashFlow(
            months: 1, accountIds: [card.id], incomeAccountIds: incomeIds, now: now2606, in: ctx)
        XCTAssertEqual(flow[0].income, 0)
    }

    func testCashFlowIncomeCategoryGating() throws {
        let ctx = try S.makeContext()
        let a = S.makeAccount(ctx, name: "Checking")
        let expenseCat = CoreModel.Category(name: "Refunds", kind: "expense")
        let incomeCat = CoreModel.Category(name: "Salary", kind: "income")
        ctx.insert(expenseCat)
        ctx.insert(incomeCat)
        let c1 = S.makeTx(ctx, account: a, amount: 100, amountEur: 100, direction: .credit, bookedAt: now2606)
        c1.category = expenseCat
        let c2 = S.makeTx(ctx, account: a, amount: 200, amountEur: 200, direction: .credit, bookedAt: now2606)
        c2.category = incomeCat
        let flow = try D.monthlyCashFlow(
            months: 1, accountIds: [a.id], incomeAccountIds: [a.id], now: now2606, in: ctx)
        XCTAssertEqual(flow[0].income, 200) // null-category would also count; expense-kind excluded
    }

    func testRefundOffsetsSpendingInCashFlowAndBreakdown() throws {
        let ctx = try S.makeContext()
        let a = S.makeAccount(ctx, name: "Checking")
        let food = CoreModel.Category(name: "Restaurants", kind: "expense")
        ctx.insert(food)
        S.makeTx(ctx, account: a, amount: -50, amountEur: -50, direction: .debit, bookedAt: now2606).category = food
        S.makeTx(ctx, account: a, amount: 10, amountEur: 10, direction: .credit, bookedAt: now2606).category = food
        let flow = try D.monthlyCashFlow(
            months: 1, accountIds: [a.id], incomeAccountIds: [a.id], now: now2606, in: ctx)
        XCTAssertEqual(flow[0].expense, 40)
        XCTAssertEqual(flow[0].income, 0)
        XCTAssertEqual(try D.categoryBreakdown(accountIds: [a.id], now: now2606, in: ctx),
                       [D.CategorySpend(categoryId: food.id, total: 40)])
    }

    func testCashFlowSharedExpenseNetAddedToExpense() throws {
        let ctx = try S.makeContext()
        let a = S.makeAccount(ctx, name: "Checking")
        let direct = S.makeTx(ctx, account: a, amount: -30, amountEur: -30, direction: .debit, bookedAt: now2606)
        _ = direct
        let primary = S.makeTx(ctx, account: a, amount: -100, amountEur: -100, direction: .debit, bookedAt: now2606)
        let reimb = S.makeTx(ctx, account: a, amount: 60, amountEur: 60, direction: .credit, bookedAt: now2606)
        let group = SharedExpenseGroup(label: "Dinner", primaryTx: primary,
                                       attributionMonth: D.monthStart(now2606))
        ctx.insert(group)
        primary.sharedExpenseGroup = group
        reimb.sharedExpenseGroup = group
        let flow = try D.monthlyCashFlow(
            months: 1, accountIds: [a.id], incomeAccountIds: [a.id], now: now2606, in: ctx)
        // direct 30 + (gross 100 − reimbursed 60) = 70
        XCTAssertEqual(flow[0].expense, 70)
        // reimbursement credit must NOT count as income (it's a SEG member)
        XCTAssertEqual(flow[0].income, 0)
    }

    func testCashFlowBucketsMonthsOldestFirst() throws {
        let ctx = try S.makeContext()
        let a = S.makeAccount(ctx, name: "Checking")
        _ = S.makeTx(ctx, account: a, amount: -100, amountEur: -100, direction: .debit, bookedAt: day(2026, 6, 10))
        _ = S.makeTx(ctx, account: a, amount: -50, amountEur: -50, direction: .debit, bookedAt: day(2026, 5, 10))
        let flow = try D.monthlyCashFlow(
            months: 3, accountIds: [a.id], incomeAccountIds: [a.id], now: now2606, in: ctx)
        XCTAssertEqual(flow.count, 3)
        XCTAssertEqual(flow[0].monthStart, D.monthStart(now2606, offset: -2)) // April
        XCTAssertEqual(flow[0].expense, 0)
        XCTAssertEqual(flow[1].monthStart, D.monthStart(now2606, offset: -1)) // May
        XCTAssertEqual(flow[1].expense, 50)
        XCTAssertEqual(flow[2].monthStart, D.monthStart(now2606)) // June
        XCTAssertEqual(flow[2].expense, 100)
    }

    // MARK: - categoryBreakdown

    func testCategoryBreakdownSortsByTotalDescending() throws {
        let ctx = try S.makeContext()
        let a = S.makeAccount(ctx, name: "Checking")
        let groceries = CoreModel.Category(name: "Groceries")
        let transport = CoreModel.Category(name: "Transport")
        ctx.insert(groceries)
        ctx.insert(transport)
        let t1 = S.makeTx(ctx, account: a, amount: -100, amountEur: -100, direction: .debit, bookedAt: now2606)
        t1.category = groceries
        let t2 = S.makeTx(ctx, account: a, amount: -200, amountEur: -200, direction: .debit, bookedAt: now2606)
        t2.category = groceries
        let t3 = S.makeTx(ctx, account: a, amount: -40, amountEur: -40, direction: .debit, bookedAt: now2606)
        t3.category = transport
        let rows = try D.categoryBreakdown(accountIds: [a.id], now: now2606, in: ctx)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].categoryId, groceries.id)
        XCTAssertEqual(rows[0].total, 300)
        XCTAssertEqual(rows[1].categoryId, transport.id)
        XCTAssertEqual(rows[1].total, 40)
    }

    func testCategoryBreakdownAttributesSegNetToPrimaryCategory() throws {
        let ctx = try S.makeContext()
        let a = S.makeAccount(ctx, name: "Checking")
        let dining = CoreModel.Category(name: "Dining")
        ctx.insert(dining)
        let primary = S.makeTx(ctx, account: a, amount: -50, amountEur: -50, direction: .debit, bookedAt: now2606)
        primary.category = dining
        let reimb = S.makeTx(ctx, account: a, amount: 20, amountEur: 20, direction: .credit, bookedAt: now2606)
        let group = SharedExpenseGroup(label: "Lunch", primaryTx: primary,
                                       attributionMonth: D.monthStart(now2606))
        ctx.insert(group)
        primary.sharedExpenseGroup = group
        reimb.sharedExpenseGroup = group
        let rows = try D.categoryBreakdown(accountIds: [a.id], now: now2606, in: ctx)
        // gross 50 − reimbursed 20 = 30, attributed to the primary's category
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].categoryId, dining.id)
        XCTAssertEqual(rows[0].total, 30)
    }

    func testCategoryBreakdownOmitsNetZeroSegGroup() throws {
        let ctx = try S.makeContext()
        let a = S.makeAccount(ctx, name: "Checking")
        let groceries = CoreModel.Category(name: "Groceries")
        let dining = CoreModel.Category(name: "Dining")
        ctx.insert(groceries)
        ctx.insert(dining)
        let g1 = S.makeTx(ctx, account: a, amount: -100, amountEur: -100, direction: .debit, bookedAt: now2606)
        g1.category = groceries
        // Fully reimbursed shared dinner: gross 50 − reimbursed 50 = net 0.
        let primary = S.makeTx(ctx, account: a, amount: -50, amountEur: -50, direction: .debit, bookedAt: now2606)
        primary.category = dining
        let reimb = S.makeTx(ctx, account: a, amount: 50, amountEur: 50, direction: .credit, bookedAt: now2606)
        let group = SharedExpenseGroup(label: "Split dinner", primaryTx: primary,
                                       attributionMonth: D.monthStart(now2606))
        ctx.insert(group)
        primary.sharedExpenseGroup = group
        reimb.sharedExpenseGroup = group
        let rows = try D.categoryBreakdown(accountIds: [a.id], now: now2606, in: ctx)
        // iOS divergence: a net-zero SEG group is omitted (the web spec emits a 0-total
        // row). Only the standalone groceries spend remains.
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].categoryId, groceries.id)
        XCTAssertEqual(rows[0].total, 100)
        XCTAssertFalse(rows.contains { $0.categoryId == dining.id })
    }

    func testCategoryBreakdownExcludesOtherMonthsAndTransfers() throws {
        let ctx = try S.makeContext()
        let a = S.makeAccount(ctx, name: "Checking")
        _ = S.makeTx(ctx, account: a, amount: -100, amountEur: -100, direction: .debit, bookedAt: day(2026, 5, 10))
        _ = S.makeTx(ctx, account: a, amount: -100, amountEur: -100, direction: .debit,
                     bookedAt: now2606, isTransfer: true)
        let rows = try D.categoryBreakdown(accountIds: [a.id], now: now2606, in: ctx)
        XCTAssertTrue(rows.isEmpty)
    }

    // MARK: - Pay cycle

    private let strict20 = CoreLogic.Dashboard.Cycle(startDay: 20, startsEarlyOnWeekends: false)

    private func midnight(_ y: Int, _ m: Int, _ d: Int) -> Date {
        day(y, m, d).addingTimeInterval(-12 * 3600)
    }

    func testCycleStartOnDayOneIsTheCalendarMonth() {
        XCTAssertEqual(D.cycleStart(day(2026, 6, 15), cycle: .calendarMonth), D.monthStart(day(2026, 6, 15)))
    }

    func testCycleStartRunsFromTheTwentiethToTheNineteenth() {
        XCTAssertEqual(D.cycleStart(day(2026, 9, 20), cycle: strict20), midnight(2026, 9, 20))
        XCTAssertEqual(D.cycleStart(day(2026, 10, 19), cycle: strict20), midnight(2026, 9, 20))
        XCTAssertEqual(D.cycleStart(day(2026, 1, 5), cycle: strict20), midnight(2025, 12, 20))
        XCTAssertEqual(D.cycleStart(day(2026, 9, 25), cycle: strict20, offset: -1), midnight(2026, 8, 20))
    }

    func testCashFlowBucketsByPayCycle() throws {
        let ctx = try S.makeContext()
        let a = S.makeAccount(ctx, name: "Checking")
        _ = S.makeTx(ctx, account: a, amount: 2000, amountEur: 2000, direction: .credit, bookedAt: day(2026, 6, 20))
        _ = S.makeTx(ctx, account: a, amount: -300, amountEur: -300, direction: .debit, bookedAt: day(2026, 7, 5))
        _ = S.makeTx(ctx, account: a, amount: -100, amountEur: -100, direction: .debit, bookedAt: day(2026, 6, 19))
        let flow = try D.monthlyCashFlow(
            months: 2, accountIds: [a.id], incomeAccountIds: [a.id], now: day(2026, 7, 10),
            cycle: strict20, in: ctx)
        XCTAssertEqual(flow.map(\.monthStart), [midnight(2026, 5, 20), midnight(2026, 6, 20)])
        XCTAssertEqual(flow[1].income, 2000)
        XCTAssertEqual(flow[1].expense, 300, "5 Jul belongs to the cycle that started 20 Jun")
        XCTAssertEqual(flow[0].expense, 100, "19 Jun closes the previous cycle")
    }

    func testCategoryBreakdownFollowsThePayCycle() throws {
        let ctx = try S.makeContext()
        let a = S.makeAccount(ctx, name: "Checking")
        _ = S.makeTx(ctx, account: a, amount: -40, amountEur: -40, direction: .debit, bookedAt: day(2026, 7, 2))
        _ = S.makeTx(ctx, account: a, amount: -60, amountEur: -60, direction: .debit, bookedAt: day(2026, 6, 10))
        let rows = try D.categoryBreakdown(
            accountIds: [a.id], now: day(2026, 7, 10), cycle: strict20, in: ctx)
        XCTAssertEqual(rows.map(\.total), [40])
    }

    // 20 Sep 2026 is a Sunday and 20 Jun a Saturday: the salary lands on the Friday before.
    func testWeekendStartMovesToTheFridayBefore() {
        let cycle = D.Cycle(startDay: 20)
        XCTAssertEqual(D.cycleStart(day(2026, 9, 18), cycle: cycle), midnight(2026, 9, 18))
        XCTAssertEqual(D.cycleStart(day(2026, 9, 17), cycle: cycle), midnight(2026, 8, 20))
        XCTAssertEqual(D.cycleStart(day(2026, 9, 18), cycle: cycle, offset: -3), midnight(2026, 6, 19))
        XCTAssertEqual(D.cycleStart(day(2026, 10, 19), cycle: cycle), midnight(2026, 9, 18))
        XCTAssertEqual(D.cycleStart(day(2026, 10, 20), cycle: cycle), midnight(2026, 10, 20))
    }

    // Day 2 on a Sunday reaches back into the previous calendar month.
    func testWeekendStartCanCrossIntoThePreviousMonth() {
        let cycle = D.Cycle(startDay: 2)
        // 2 Aug 2026 is a Sunday ⇒ the August cycle starts Friday 31 Jul.
        XCTAssertEqual(D.cycleStart(day(2026, 7, 31), cycle: cycle), midnight(2026, 7, 31))
        XCTAssertEqual(D.cycleStart(day(2026, 7, 30), cycle: cycle), midnight(2026, 7, 2))
    }

    func testManuallyAttributedGroupLandsInTheNamedCycle() throws {
        let ctx = try S.makeContext()
        let a = S.makeAccount(ctx, name: "Checking")
        let primary = S.makeTx(ctx, account: a, amount: -100, amountEur: -100, direction: .debit,
                               bookedAt: day(2026, 6, 5))
        let g = SharedExpenseGroup(label: "Trip", primaryTx: primary, attributionMonth: midnight(2026, 7, 1))
        ctx.insert(g)
        primary.sharedExpenseGroup = g
        try ctx.save()
        let flow = try D.monthlyCashFlow(
            months: 3, accountIds: [a.id], incomeAccountIds: [a.id], now: day(2026, 7, 25),
            cycle: strict20, in: ctx)
        XCTAssertEqual(flow.map(\.expense), [0, 0, 100], "July attribution ⇒ the cycle from 20 Jul")
    }
}

