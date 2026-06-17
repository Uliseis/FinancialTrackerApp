import Foundation
import SwiftData
import CoreModel

extension CoreLogic.Budgets {
    // Ports the budgets routes. A budget always targets a category (the web requires
    // categoryId); amount is a Decimal (the web's numeric string).
    @MainActor @discardableResult
    public static func create(
        category: CoreModel.Category, amountEur: Decimal, period: BudgetPeriod = .month,
        startsOn: Date, active: Bool = true, in ctx: ModelContext, now: Date = .now
    ) throws -> Budget {
        let budget = Budget(
            category: category, amountEur: amountEur, period: period,
            startsOn: startsOn, active: active, createdAt: now, updatedAt: now
        )
        ctx.insert(budget)
        try ctx.saveTouchingChanges()
        return budget
    }

    @MainActor
    public static func update(
        _ budget: Budget, category: CoreModel.Category, amountEur: Decimal,
        period: BudgetPeriod, startsOn: Date, active: Bool, in ctx: ModelContext, now: Date = .now
    ) throws {
        budget.category = category
        budget.amountEur = amountEur
        budget.period = period
        budget.startsOn = startsOn
        budget.active = active
        budget.updatedAt = now
        try ctx.saveTouchingChanges()
    }

    @MainActor
    public static func delete(_ budget: Budget, in ctx: ModelContext) throws {
        ctx.delete(budget)
        try ctx.saveTouchingChanges()
    }
}
