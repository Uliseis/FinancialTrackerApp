import Foundation
import SwiftData
import CoreModel

extension CoreLogic {
    // Ports the category-rules routes. Rules apply in priority DESC order (see
    // Categorize.applyRulesToTransactions); reorder assigns priority so the top of the list
    // is the highest priority. A rule always targets a category — one without is a no-op.
    public enum CategoryRules {
        public enum Error: Swift.Error, Equatable {
            case patternRequired
        }

        @MainActor @discardableResult
        public static func create(
            pattern: String, category: CoreModel.Category,
            field: RuleField = .description, matchType: RuleMatch = .contains,
            priority: Int = 0, in ctx: ModelContext, now: Date = .now
        ) throws -> CategoryRule {
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw Error.patternRequired }
            let rule = CategoryRule(
                pattern: trimmed, field: field, matchType: matchType,
                category: category, priority: priority, createdAt: now
            )
            ctx.insert(rule)
            try ctx.saveTouchingChanges()
            return rule
        }

        @MainActor
        public static func update(
            _ rule: CategoryRule, pattern: String, category: CoreModel.Category,
            field: RuleField, matchType: RuleMatch, in ctx: ModelContext
        ) throws {
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw Error.patternRequired }
            rule.pattern = trimmed
            rule.category = category
            rule.field = field
            rule.matchType = matchType
            try ctx.saveTouchingChanges()
        }

        // Top of the list = highest priority. Index 0 ⇒ (count-1), so applyRules' priority
        // DESC sort matches the displayed order.
        @MainActor
        public static func reorder(_ orderedIds: [UUID], in ctx: ModelContext) throws {
            let byId = Dictionary(
                (try ctx.fetch(FetchDescriptor<CategoryRule>())).map { ($0.id, $0) },
                uniquingKeysWith: { a, _ in a }
            )
            let top = orderedIds.count - 1
            for (index, id) in orderedIds.enumerated() {
                let priority = top - index
                guard let rule = byId[id], rule.priority != priority else { continue }
                rule.priority = priority
            }
            try ctx.saveTouchingChanges()
        }

        @MainActor
        public static func delete(_ rule: CategoryRule, in ctx: ModelContext) throws {
            ctx.delete(rule)
            try ctx.saveTouchingChanges()
        }
    }
}
