import Foundation
import SwiftData
import CoreModel

extension CoreLogic {
    public enum TransferRoutes {
        public static func mirrorExternalId(_ sourceTxId: UUID) -> String {
            "mirror:\(sourceTxId.uuidString)"
        }

        public static func routeMatches(route: TransferRoute, tx: Transaction) -> Bool {
            if !route.enabled { return false }
            if let src = route.sourceAccount, src.id != tx.account?.id { return false }
            if let dir = route.direction, dir != tx.direction { return false }
            let needle = route.pattern
            if needle.isEmpty { return false }
            let haystack: String
            switch route.field {
            case .counterparty: haystack = tx.counterparty ?? ""
            case .description:  haystack = tx.transactionDescription ?? ""
            }
            let h = haystack.lowercased()
            let n = needle.lowercased()
            switch route.matchType {
            case .equals:     return h == n
            case .startsWith: return h.hasPrefix(n)
            case .endsWith:   return h.hasSuffix(n)
            case .contains:   return h.contains(n)
            case .regex:
                guard let re = try? NSRegularExpression(pattern: needle, options: [.caseInsensitive]) else {
                    return false
                }
                let range = NSRange(haystack.startIndex..., in: haystack)
                return re.firstMatch(in: haystack, options: [], range: range) != nil
            }
        }

        public struct MirrorResult: Equatable, Sendable {
            public let mirrorId: UUID
            public let transferGroupId: UUID
        }

        @MainActor
        public static func createMirror(
            from source: Transaction,
            to targetAccount: Account,
            route: TransferRoute? = nil,
            in ctx: ModelContext
        ) throws -> MirrorResult? {
            guard source.account?.id != targetAccount.id else { return nil }
            if source.routedFromTx != nil { return nil }
            if targetAccount.archived { return nil }

            // TS uses strict equality on spaceId; if both are nil they're equal,
            // so a route between two manual accounts with no space proceeds.
            if source.account?.space?.id != targetAccount.space?.id { return nil }

            let externalId = mirrorExternalId(source.id)
            let targetID = targetAccount.id
            let existing = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate {
                    $0.account?.id == targetID && $0.externalId == externalId
                }
            ))

            if let mirror = existing.first {
                let group: TransferGroup
                if let g = mirror.transferGroup {
                    group = g
                } else if let g = source.transferGroup {
                    group = g
                    mirror.transferGroup = g
                } else {
                    group = TransferGroup(pairedAt: .now, route: route)
                    ctx.insert(group)
                    mirror.transferGroup = group
                }
                if !source.isTransfer || source.transferGroup?.id != group.id {
                    source.isTransfer = true
                    source.transferGroup = group
                }
                try ctx.save()
                return MirrorResult(mirrorId: mirror.id, transferGroupId: group.id)
            }

            let group: TransferGroup
            if let g = source.transferGroup {
                group = g
            } else {
                group = TransferGroup(pairedAt: .now, route: route)
                ctx.insert(group)
            }

            let mirror = Transaction(
                account: targetAccount,
                externalId: externalId,
                bookedAt: source.bookedAt,
                valueAt: source.valueAt,
                amount: -source.amount,
                currency: source.currency,
                amountEur: source.amountEur.map { -$0 },
                direction: source.direction.flipped,
                description: source.transactionDescription,
                counterparty: source.counterparty ?? "Routed transfer",
                isTransfer: true,
                transferGroup: group,
                routedFromTx: source,
                route: route
            )
            ctx.insert(mirror)

            source.isTransfer = true
            source.transferGroup = group

            try ctx.save()
            return MirrorResult(mirrorId: mirror.id, transferGroupId: group.id)
        }

        public struct RemoveMirrorResult: Equatable, Sendable {
            public let deleted: Int
        }

        @MainActor
        public static func removeMirror(
            forSource sourceTxId: UUID,
            in ctx: ModelContext
        ) throws -> RemoveMirrorResult {
            let mirrors = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.routedFromTx?.id == sourceTxId }
            ))
            for m in mirrors {
                ctx.delete(m)
            }
            if let source = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.id == sourceTxId }
            )).first {
                source.isTransfer = false
                source.transferGroup = nil
            }
            try ctx.save()
            return RemoveMirrorResult(deleted: mirrors.count)
        }

        public struct RemoveRouteMirrorsResult: Equatable, Sendable {
            public let deleted: Int
            public let sourcesReset: Int
        }

        @MainActor
        public static func removeRouteMirrors(
            routeId: UUID,
            in ctx: ModelContext
        ) throws -> RemoveRouteMirrorsResult {
            let mirrors = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate {
                    $0.route?.id == routeId && $0.routedFromTx != nil
                }
            ))
            if mirrors.isEmpty {
                return RemoveRouteMirrorsResult(deleted: 0, sourcesReset: 0)
            }
            let sourceIds = mirrors.compactMap { $0.routedFromTx?.id }
            let deleted = mirrors.count
            for m in mirrors {
                ctx.delete(m)
            }
            var sourcesReset = 0
            for sourceID in sourceIds {
                if let s = try ctx.fetch(FetchDescriptor<Transaction>(
                    predicate: #Predicate { $0.id == sourceID }
                )).first {
                    s.isTransfer = false
                    s.transferGroup = nil
                    sourcesReset += 1
                }
            }
            try ctx.save()
            return RemoveRouteMirrorsResult(deleted: deleted, sourcesReset: sourcesReset)
        }

        public struct ApplyResult: Equatable, Sendable {
            public let scanned: Int
            public let mirroredCreated: Int
        }

        @MainActor
        public static func apply(
            in ctx: ModelContext,
            txIds: [UUID]? = nil,
            sinceDays: Int? = nil,
            routeId: UUID? = nil
        ) throws -> ApplyResult {
            let sort: [SortDescriptor<TransferRoute>] = [
                SortDescriptor(\.priority, order: .reverse),
                SortDescriptor(\.createdAt, order: .forward),
            ]
            let routes: [TransferRoute]
            if let id = routeId {
                routes = try ctx.fetch(FetchDescriptor<TransferRoute>(
                    predicate: #Predicate { $0.enabled == true && $0.id == id },
                    sortBy: sort
                ))
            } else {
                routes = try ctx.fetch(FetchDescriptor<TransferRoute>(
                    predicate: #Predicate { $0.enabled == true },
                    sortBy: sort
                ))
            }
            if routes.isEmpty { return ApplyResult(scanned: 0, mirroredCreated: 0) }

            let candidates: [Transaction]
            if let ids = txIds, !ids.isEmpty {
                let idSet = Set(ids)
                candidates = try ctx.fetch(FetchDescriptor<Transaction>(
                    predicate: #Predicate {
                        idSet.contains($0.id) &&
                        $0.routedFromTx == nil &&
                        $0.isTransfer == false
                    }
                ))
            } else if let sinceDays {
                let cutoff = Date().addingTimeInterval(-Double(sinceDays) * 86_400)
                candidates = try ctx.fetch(FetchDescriptor<Transaction>(
                    predicate: #Predicate {
                        $0.routedFromTx == nil &&
                        $0.isTransfer == false &&
                        $0.bookedAt >= cutoff
                    }
                ))
            } else {
                candidates = try ctx.fetch(FetchDescriptor<Transaction>(
                    predicate: #Predicate {
                        $0.routedFromTx == nil && $0.isTransfer == false
                    }
                ))
            }

            var created = 0
            for tx in candidates {
                var matched: TransferRoute?
                for r in routes where routeMatches(route: r, tx: tx) {
                    matched = r
                    break
                }
                guard let route = matched, let target = route.targetAccount else { continue }
                if target.id == tx.account?.id { continue }
                if try createMirror(from: tx, to: target, route: route, in: ctx) != nil {
                    created += 1
                }
            }
            return ApplyResult(scanned: candidates.count, mirroredCreated: created)
        }

        @MainActor
        public static func listManualAccountsForRouting(in ctx: ModelContext) throws -> [Account] {
            try ctx.fetch(FetchDescriptor<Account>(
                predicate: #Predicate { $0.archived == false && $0.connection == nil }
            ))
        }

        // MARK: - Route definition CRUD (ports transfer-routes API)

        public enum RouteError: Swift.Error, Equatable {
            case patternRequired
            case sourceEqualsTarget
        }

        // 730-day lookback for backfill — parity with the web (`sinceDays: 730`).
        public static let backfillLookbackDays = 730

        public struct CreateRouteResult {
            public let route: TransferRoute
            public let applied: ApplyResult?
        }

        public struct UpdateRouteResult: Equatable, Sendable {
            public let matchersChanged: Bool
            public let mirrorsRemoved: RemoveRouteMirrorsResult?
            public let reapplied: ApplyResult?
        }

        @MainActor @discardableResult
        public static func createRoute(
            pattern: String, target: Account, source: Account? = nil,
            field: RuleField = .description, matchType: RuleMatch = .contains,
            direction: TxDirection? = nil, priority: Int = 0, enabled: Bool = true,
            in ctx: ModelContext, now: Date = .now
        ) throws -> CreateRouteResult {
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw RouteError.patternRequired }
            if let source, source.id == target.id { throw RouteError.sourceEqualsTarget }
            let route = TransferRoute(
                pattern: trimmed, field: field, matchType: matchType,
                sourceAccount: source, targetAccount: target, direction: direction,
                priority: priority, enabled: enabled, createdAt: now, updatedAt: now
            )
            ctx.insert(route)
            try ctx.save()
            var applied: ApplyResult?
            if enabled {
                applied = try apply(in: ctx, sinceDays: backfillLookbackDays, routeId: route.id)
            }
            return CreateRouteResult(route: route, applied: applied)
        }

        // Changing any matcher (pattern/accounts/field/matchType/direction) or disabling the
        // route first removes the mirrors it spawned, then — if it stays enabled and a matcher
        // changed — re-applies so the mirror set matches the new definition. This is the
        // load-bearing wiring: stale mirrors must not survive a definition change.
        @MainActor @discardableResult
        public static func updateRoute(
            _ route: TransferRoute, pattern: String, target: Account, source: Account?,
            field: RuleField, matchType: RuleMatch, direction: TxDirection?, enabled: Bool,
            in ctx: ModelContext, now: Date = .now
        ) throws -> UpdateRouteResult {
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw RouteError.patternRequired }
            if let source, source.id == target.id { throw RouteError.sourceEqualsTarget }

            let matchersChanged =
                route.pattern != trimmed ||
                route.targetAccount?.id != target.id ||
                route.sourceAccount?.id != source?.id ||
                route.field != field ||
                route.matchType != matchType ||
                route.direction != direction

            var mirrorsRemoved: RemoveRouteMirrorsResult?
            if matchersChanged || !enabled {
                mirrorsRemoved = try removeRouteMirrors(routeId: route.id, in: ctx)
            }

            route.pattern = trimmed
            route.targetAccount = target
            route.sourceAccount = source
            route.field = field
            route.matchType = matchType
            route.direction = direction
            route.enabled = enabled
            route.updatedAt = now
            try ctx.save()

            var reapplied: ApplyResult?
            if matchersChanged && enabled {
                reapplied = try apply(in: ctx, sinceDays: backfillLookbackDays, routeId: route.id)
            }
            return UpdateRouteResult(
                matchersChanged: matchersChanged, mirrorsRemoved: mirrorsRemoved, reapplied: reapplied
            )
        }

        @MainActor @discardableResult
        public static func deleteRoute(
            _ route: TransferRoute, in ctx: ModelContext
        ) throws -> RemoveRouteMirrorsResult {
            let removed = try removeRouteMirrors(routeId: route.id, in: ctx)
            ctx.delete(route)
            try ctx.save()
            return removed
        }

        // Top of the list = highest priority (parity with the apply sort, priority DESC).
        @MainActor
        public static func reorderRoutes(_ orderedIds: [UUID], in ctx: ModelContext, now: Date = .now) throws {
            let byId = Dictionary(
                (try ctx.fetch(FetchDescriptor<TransferRoute>())).map { ($0.id, $0) },
                uniquingKeysWith: { a, _ in a }
            )
            let top = orderedIds.count - 1
            for (index, id) in orderedIds.enumerated() {
                let priority = top - index
                guard let route = byId[id], route.priority != priority else { continue }
                route.priority = priority
                route.updatedAt = now
            }
            try ctx.save()
        }

        @MainActor @discardableResult
        public static func backfillRoute(_ route: TransferRoute, in ctx: ModelContext) throws -> ApplyResult {
            try apply(in: ctx, sinceDays: backfillLookbackDays, routeId: route.id)
        }
    }
}
