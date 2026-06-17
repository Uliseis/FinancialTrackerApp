import Foundation
import SwiftData
import CoreModel

extension CoreLogic {
    // Ports the account-groups API routes. Deleting a group detaches its accounts via the
    // Account.group .nullify rule — accounts survive, just ungrouped ("Other" in the UI).
    public enum AccountGroups {
        public enum Error: Swift.Error, Equatable {
            case nameRequired
        }

        @MainActor @discardableResult
        public static func create(
            name: String, kind: AccountGroupKind = .other, color: String? = nil,
            sortOrder: Int = 0, in ctx: ModelContext, now: Date = .now
        ) throws -> AccountGroup {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw Error.nameRequired }
            let group = AccountGroup(
                name: trimmed, color: color, kind: kind,
                sortOrder: sortOrder, createdAt: now, updatedAt: now
            )
            ctx.insert(group)
            try ctx.saveTouchingChanges()
            return group
        }

        @MainActor
        public static func update(
            _ group: AccountGroup, name: String, kind: AccountGroupKind, color: String?,
            in ctx: ModelContext, now: Date = .now
        ) throws {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw Error.nameRequired }
            group.name = trimmed
            group.kind = kind
            group.color = color
            group.updatedAt = now
            try ctx.saveTouchingChanges()
        }

        @MainActor
        public static func reorder(_ orderedIds: [UUID], in ctx: ModelContext, now: Date = .now) throws {
            let byId = Dictionary(
                (try ctx.fetch(FetchDescriptor<AccountGroup>())).map { ($0.id, $0) },
                uniquingKeysWith: { a, _ in a }
            )
            for (index, id) in orderedIds.enumerated() {
                guard let group = byId[id], group.sortOrder != index else { continue }
                group.sortOrder = index
                group.updatedAt = now
            }
            try ctx.saveTouchingChanges()
        }

        @MainActor
        public static func delete(_ group: AccountGroup, in ctx: ModelContext) throws {
            ctx.delete(group)
            try ctx.saveTouchingChanges()
        }
    }
}
