import Foundation
import SwiftData
import CoreModel

extension CoreLogic {
    public enum TransferInvariants {
        public struct Violation: Equatable, Sendable {
            public let name: String
            public let count: Int
            public let sampleIds: [UUID]

            public init(name: String, count: Int, sampleIds: [UUID]) {
                self.name = name
                self.count = count
                self.sampleIds = sampleIds
            }
        }

        public static let sampleCap = 25
        public static let sampleIdsCap = 5

        @MainActor
        public static func assertAll(in ctx: ModelContext) throws -> [Violation] {
            var out: [Violation] = []
            if let v = try orphanTransferGroup(in: ctx)        { out.append(v) }
            if let v = try mirrorWithUnflaggedSource(in: ctx)  { out.append(v) }
            if let v = try danglingTransferFlag(in: ctx)       { out.append(v) }
            if let v = try crossSpaceTransferGroup(in: ctx)    { out.append(v) }
            if let v = try transferOnArchivedAccount(in: ctx)  { out.append(v) }
            return out
        }

        public static func format(_ violations: [Violation]) -> String {
            if violations.isEmpty { return "" }
            return violations.map { v in
                let ids = v.sampleIds.map(\.uuidString).joined(separator: ",")
                return "\(v.name)=\(v.count)(\(ids))"
            }.joined(separator: "; ")
        }

        @MainActor
        public static func orphanTransferGroup(in ctx: ModelContext) throws -> Violation? {
            let withGroup = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.transferGroup != nil }
            ))
            var sizes: [UUID: Int] = [:]
            for t in withGroup {
                if let g = t.transferGroup { sizes[g.id, default: 0] += 1 }
            }
            let bad = withGroup.filter { t in
                guard t.routedFromTx == nil, let g = t.transferGroup else { return false }
                return (sizes[g.id] ?? 0) == 1
            }
            let capped = Array(bad.prefix(sampleCap))
            if capped.isEmpty { return nil }
            return Violation(
                name: "orphan_transfer_group",
                count: capped.count,
                sampleIds: capped.prefix(sampleIdsCap).map(\.id)
            )
        }

        @MainActor
        public static func mirrorWithUnflaggedSource(in ctx: ModelContext) throws -> Violation? {
            let mirrors = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.routedFromTx != nil }
            ))
            let bad = mirrors.filter { $0.routedFromTx?.isTransfer == false }
            let capped = Array(bad.prefix(sampleCap))
            if capped.isEmpty { return nil }
            return Violation(
                name: "mirror_with_unflagged_source",
                count: capped.count,
                sampleIds: capped.prefix(sampleIdsCap).map(\.id)
            )
        }

        @MainActor
        public static func danglingTransferFlag(in ctx: ModelContext) throws -> Violation? {
            let bad = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate {
                    $0.isTransfer == true && $0.transferGroup == nil && $0.routedFromTx == nil
                }
            ))
            let capped = Array(bad.prefix(sampleCap))
            if capped.isEmpty { return nil }
            return Violation(
                name: "dangling_transfer_flag",
                count: capped.count,
                sampleIds: capped.prefix(sampleIdsCap).map(\.id)
            )
        }

        @MainActor
        public static func crossSpaceTransferGroup(in ctx: ModelContext) throws -> Violation? {
            let withGroup = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.transferGroup != nil }
            ))
            var spacesByGroup: [UUID: Set<UUID?>] = [:]
            var membersByGroup: [UUID: [Transaction]] = [:]
            for t in withGroup {
                guard let g = t.transferGroup else { continue }
                spacesByGroup[g.id, default: []].insert(t.account?.space?.id)
                membersByGroup[g.id, default: []].append(t)
            }
            let badGroupIds = spacesByGroup.compactMap { $0.value.count > 1 ? $0.key : nil }
            if badGroupIds.isEmpty { return nil }
            let bad = badGroupIds.flatMap { membersByGroup[$0] ?? [] }
            let capped = Array(bad.prefix(sampleCap))
            if capped.isEmpty { return nil }
            return Violation(
                name: "cross_space_transfer_group",
                count: capped.count,
                sampleIds: capped.prefix(sampleIdsCap).map(\.id)
            )
        }

        @MainActor
        public static func transferOnArchivedAccount(in ctx: ModelContext) throws -> Violation? {
            let candidates = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.isTransfer == true }
            ))
            let bad = candidates.filter { $0.account?.archived == true }
            let capped = Array(bad.prefix(sampleCap))
            if capped.isEmpty { return nil }
            return Violation(
                name: "transfer_on_archived_account",
                count: capped.count,
                sampleIds: capped.prefix(sampleIdsCap).map(\.id)
            )
        }
    }
}
