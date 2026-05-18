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
                CoreLogic.deleteTransaction(m, in: ctx)
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
                CoreLogic.deleteTransaction(m, in: ctx)
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
    }
}
