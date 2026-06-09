import Foundation
import SwiftData
import CoreModel

extension CoreLogic {
    public enum Transfers {
        public static let defaultLookbackDays = 30
        public static let pairWindowDays = 3
        public static let eurTolerance: Decimal = Decimal(string: "0.01")!

        public struct DetectResult: Equatable, Sendable {
            public let scanned: Int
            public let matched: Int
        }

        @MainActor
        public static func detect(
            in ctx: ModelContext,
            sinceDays: Int? = nil,
            txIds: [UUID]? = nil
        ) throws -> DetectResult {
            let lookback = sinceDays ?? defaultLookbackDays
            let cutoff = Date().addingTimeInterval(-Double(lookback) * 86_400)

            let raw: [Transaction]
            if let ids = txIds, !ids.isEmpty {
                let idSet = Set(ids)
                raw = try ctx.fetch(FetchDescriptor<Transaction>(
                    predicate: #Predicate {
                        idSet.contains($0.id) &&
                        $0.amountEur != nil &&
                        $0.sharedExpenseGroup == nil
                    }
                ))
            } else {
                raw = try ctx.fetch(FetchDescriptor<Transaction>(
                    predicate: #Predicate {
                        $0.bookedAt >= cutoff &&
                        $0.amountEur != nil &&
                        $0.sharedExpenseGroup == nil
                    }
                ))
            }

            let candidates: [Candidate] = raw.compactMap { tx in
                guard let amount = tx.amountEur else { return nil }
                return Candidate(tx: tx, amountAbs: abs(amount))
            }

            let debits = candidates.filter { $0.tx.direction == .debit && !$0.tx.isTransfer }
            let credits = candidates.filter { $0.tx.direction == .credit && !$0.tx.isTransfer }
            if debits.isEmpty || credits.isEmpty {
                return DetectResult(scanned: candidates.count, matched: 0)
            }

            var claimed = Set<UUID>()
            var pairs: [(Candidate, Candidate)] = []
            let windowSeconds = Double(pairWindowDays) * 86_400

            for debit in debits {
                if claimed.contains(debit.tx.id) { continue }
                if debit.tx.categorySource == .manual { continue }
                let partners = credits.filter { c in
                    if claimed.contains(c.tx.id) { return false }
                    if c.tx.account?.id == debit.tx.account?.id { return false }
                    if c.tx.account?.space?.id != debit.tx.account?.space?.id { return false }
                    if c.tx.categorySource == .manual { return false }
                    if abs(c.amountAbs - debit.amountAbs) > eurTolerance { return false }
                    let diff = abs(c.tx.bookedAt.timeIntervalSince(debit.tx.bookedAt))
                    return diff <= windowSeconds
                }
                if partners.count == 1 {
                    let partner = partners[0]
                    claimed.insert(debit.tx.id)
                    claimed.insert(partner.tx.id)
                    pairs.append((debit, partner))
                }
            }

            if pairs.isEmpty { return DetectResult(scanned: candidates.count, matched: 0) }

            var matched = 0
            for (a, b) in pairs {
                let group: TransferGroup
                if let g = a.tx.transferGroup ?? b.tx.transferGroup {
                    group = g
                } else {
                    group = TransferGroup(pairedAt: .now)
                    ctx.insert(group)
                }
                for tx in [a.tx, b.tx] {
                    tx.isTransfer = true
                    tx.transferGroup = group
                }
                matched += 2
            }
            try ctx.save()
            return DetectResult(scanned: candidates.count, matched: matched)
        }

        public struct RepairResult: Equatable, Sendable {
            public var groupsBroken: Int
            public var txsUnflagged: Int
            public var mirrorsDeleted: Int
            public var orphansFixed: Int
        }

        @MainActor
        public static func repairGroups(
            in ctx: ModelContext,
            accountId: UUID? = nil
        ) throws -> RepairResult {
            var result = RepairResult(
                groupsBroken: 0, txsUnflagged: 0, mirrorsDeleted: 0, orphansFixed: 0
            )

            let seedTxs: [Transaction]
            if let accID = accountId {
                seedTxs = try ctx.fetch(FetchDescriptor<Transaction>(
                    predicate: #Predicate {
                        $0.account?.id == accID && $0.transferGroup != nil
                    }
                ))
            } else {
                seedTxs = try ctx.fetch(FetchDescriptor<Transaction>(
                    predicate: #Predicate { $0.transferGroup != nil }
                ))
            }
            let groupIds = Set(seedTxs.compactMap { $0.transferGroup?.id })

            let allMembers: [Transaction]
            if groupIds.isEmpty {
                allMembers = []
            } else if accountId == nil {
                allMembers = seedTxs
            } else {
                let everyWithGroup = try ctx.fetch(FetchDescriptor<Transaction>(
                    predicate: #Predicate { $0.transferGroup != nil }
                ))
                allMembers = everyWithGroup.filter {
                    guard let g = $0.transferGroup else { return false }
                    return groupIds.contains(g.id)
                }
            }

            var byGroup: [UUID: [Transaction]] = [:]
            for m in allMembers {
                if let g = m.transferGroup { byGroup[g.id, default: []].append(m) }
            }

            var txsToUnflag: [Transaction] = []
            var orphansToReset: [Transaction] = []
            for (_, group) in byGroup {
                let spaces = Set(group.map { $0.account?.space?.id })
                let anyArchived = group.contains { $0.account?.archived == true }
                let hasMirror = group.contains { $0.routedFromTx != nil }
                if spaces.count > 1 || anyArchived {
                    txsToUnflag.append(contentsOf: group)
                    result.groupsBroken += 1
                    continue
                }
                if group.count < 2 && !hasMirror {
                    orphansToReset.append(contentsOf: group)
                    result.orphansFixed += 1
                }
            }
            for t in txsToUnflag {
                t.isTransfer = false
                t.transferGroup = nil
                result.txsUnflagged += 1
            }
            for t in orphansToReset {
                t.isTransfer = false
                t.transferGroup = nil
                result.txsUnflagged += 1
            }

            let mirrorCandidates: [Transaction]
            if let accID = accountId {
                let allMirrors = try ctx.fetch(FetchDescriptor<Transaction>(
                    predicate: #Predicate { $0.routedFromTx != nil }
                ))
                mirrorCandidates = allMirrors.filter {
                    $0.account?.id == accID || $0.routedFromTx?.account?.id == accID
                }
            } else {
                mirrorCandidates = try ctx.fetch(FetchDescriptor<Transaction>(
                    predicate: #Predicate { $0.routedFromTx != nil }
                ))
            }

            var toDelete: [Transaction] = []
            var sourcesToReset: [Transaction] = []
            for m in mirrorCandidates {
                guard let s = m.routedFromTx else { continue }
                let mirrorSpace = m.account?.space?.id
                let sourceSpace = s.account?.space?.id
                let crossSpace = mirrorSpace != sourceSpace
                let mirrorOK = CoreLogic.AccountStatus.isUsableForTransfers(m.account)
                let sourceOK = CoreLogic.AccountStatus.isUsableForTransfers(s.account)
                if crossSpace || !mirrorOK || !sourceOK {
                    toDelete.append(m)
                    sourcesToReset.append(s)
                }
            }
            for m in toDelete {
                ctx.delete(m)
                result.mirrorsDeleted += 1
            }
            for s in sourcesToReset {
                s.isTransfer = false
                s.transferGroup = nil
            }

            try ctx.save()
            return result
        }

        private struct Candidate {
            let tx: Transaction
            let amountAbs: Decimal
        }
    }
}
