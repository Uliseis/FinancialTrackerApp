import Foundation
import SwiftData
import CoreModel

extension CoreLogic {
    // Ports lib/spaces.ts + the spaces API routes. The default space catches accounts
    // with space == nil (see SpaceScope on the app side); deleting a space reassigns its
    // accounts to the default rather than relying on the .nullify rule, to match the web.
    public enum Spaces {
        public enum Error: Swift.Error, Equatable {
            case nameRequired
            case cannotDeleteDefault
        }

        @MainActor @discardableResult
        public static func ensureDefault(in ctx: ModelContext, now: Date = .now) throws -> AccountSpace {
            var d = FetchDescriptor<AccountSpace>(predicate: #Predicate { $0.isDefault })
            d.fetchLimit = 1
            if let existing = try ctx.fetch(d).first { return existing }
            let space = AccountSpace(
                name: "Individual", color: "#3b82f6", isDefault: true,
                sortOrder: 0, createdAt: now, updatedAt: now
            )
            ctx.insert(space)
            try ctx.save()
            return space
        }

        @MainActor
        public static func defaultSpaceId(in ctx: ModelContext, now: Date = .now) throws -> UUID {
            try ensureDefault(in: ctx, now: now).id
        }

        @MainActor @discardableResult
        public static func create(
            name: String, color: String? = nil, sortOrder: Int = 0,
            in ctx: ModelContext, now: Date = .now
        ) throws -> AccountSpace {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw Error.nameRequired }
            let space = AccountSpace(
                name: trimmed, color: color, isDefault: false,
                sortOrder: sortOrder, createdAt: now, updatedAt: now
            )
            ctx.insert(space)
            try ctx.save()
            return space
        }

        @MainActor
        public static func update(
            _ space: AccountSpace, name: String, color: String?,
            in ctx: ModelContext, now: Date = .now
        ) throws {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw Error.nameRequired }
            space.name = trimmed
            space.color = color
            space.updatedAt = now
            try ctx.save()
        }

        @MainActor
        public static func reorder(_ orderedIds: [UUID], in ctx: ModelContext, now: Date = .now) throws {
            let byId = Dictionary(
                (try ctx.fetch(FetchDescriptor<AccountSpace>())).map { ($0.id, $0) },
                uniquingKeysWith: { a, _ in a }
            )
            for (index, id) in orderedIds.enumerated() {
                guard let space = byId[id], space.sortOrder != index else { continue }
                space.sortOrder = index
                space.updatedAt = now
            }
            try ctx.save()
        }

        @MainActor
        public static func setDefault(_ space: AccountSpace, in ctx: ModelContext, now: Date = .now) throws {
            for other in try ctx.fetch(FetchDescriptor<AccountSpace>()) where other.isDefault && other.id != space.id {
                other.isDefault = false
                other.updatedAt = now
            }
            space.isDefault = true
            space.updatedAt = now
            try ctx.save()
        }

        @MainActor
        public static func delete(_ space: AccountSpace, in ctx: ModelContext, now: Date = .now) throws {
            if space.isDefault { throw Error.cannotDeleteDefault }
            let fallback = try ensureDefault(in: ctx, now: now)
            let spaceId = space.id
            let members = try ctx.fetch(FetchDescriptor<Account>(
                predicate: #Predicate { $0.space?.id == spaceId }
            ))
            for account in members { account.space = fallback }
            ctx.delete(space)
            try ctx.save()
        }
    }
}
