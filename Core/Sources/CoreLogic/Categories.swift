import Foundation
import SwiftData
import CoreModel

extension CoreLogic {
    // Ports the categories routes + the manual side of the tx recategorize. `kind` is stored
    // as the CategoryKind rawValue. Deleting a category cascades its rules/budgets and
    // nullifies tx.category + child.parent via the model's @Relationship rules.
    public enum Categories {
        public enum Error: Swift.Error, Equatable {
            case nameRequired
            case cannotParentToSelf
            case parentCycle
        }

        @MainActor @discardableResult
        public static func create(
            name: String, kind: CategoryKind = .expense, parent: CoreModel.Category? = nil,
            color: String? = nil, in ctx: ModelContext, now: Date = .now
        ) throws -> CoreModel.Category {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw Error.nameRequired }
            let category = CoreModel.Category(
                name: trimmed, parent: parent, kind: kind.rawValue,
                color: color, createdAt: now
            )
            ctx.insert(category)
            try ctx.save()
            return category
        }

        @MainActor
        public static func update(
            _ category: CoreModel.Category, name: String, kind: CategoryKind, parent: CoreModel.Category?,
            color: String?, in ctx: ModelContext
        ) throws {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw Error.nameRequired }
            if let parent, parent.id == category.id { throw Error.cannotParentToSelf }
            // Stricter than the web (which has no guard): a parent cycle would hang the
            // planned ancestor-walking rollups.
            var ancestor = parent?.parent
            while let current = ancestor {
                if current.id == category.id { throw Error.parentCycle }
                ancestor = current.parent
            }
            category.name = trimmed
            category.kind = kind.rawValue
            category.parent = parent
            category.color = color
            try ctx.save()
        }

        @MainActor
        public static func delete(_ category: CoreModel.Category, in ctx: ModelContext) throws {
            ctx.delete(category)
            try ctx.save()
        }

        // Manual categorization always sets categorySource = .manual — the side that wins
        // LWW conflict resolution per the locked policy, regardless of clock.
        @MainActor
        public static func recategorize(
            _ tx: Transaction, to category: CoreModel.Category?, in ctx: ModelContext
        ) throws {
            tx.category = category
            tx.categorySource = .manual
            try ctx.save()
        }

        @MainActor
        public static func recategorize(
            _ txs: [Transaction], to category: CoreModel.Category?, in ctx: ModelContext
        ) throws {
            for tx in txs {
                tx.category = category
                tx.categorySource = .manual
            }
            try ctx.save()
        }
    }
}
