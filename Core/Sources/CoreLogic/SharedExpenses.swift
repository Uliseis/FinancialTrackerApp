import Foundation
import SwiftData
import CoreModel

extension CoreLogic {
    public enum SharedExpenses {
        public static let reimbursementWindowDays = 60
        public static let overcoverageEpsilon: Decimal = Decimal(string: "0.001")!

        public enum Error: Swift.Error, Equatable, Sendable {
            case labelRequired
            case noReimbursements
            case primaryIsAlsoReimbursement
            case primaryMustBeDebit
            case primaryIsTransfer
            case primaryAlreadyInGroup
            case primaryHasNoEurAmount
            case reimbursementNotCredit(txId: UUID)
            case reimbursementIsTransfer(txId: UUID)
            case reimbursementAlreadyInGroup(txId: UUID)
            case reimbursementOutsideWindow(txId: UUID, windowDays: Int)
            case reimbursementHasNoEurAmount(txId: UUID)
            case crossSpace(txId: UUID)
            case overcoverage(reimbursed: Decimal, primary: Decimal)
            case txNotFound(label: String)
            case groupNotFound
            case cannotRemovePrimary
            case startingTxNotCredit
            case noExpenses
            case creditIsAlsoExpense
            case creditMustBeCredit
            case creditIsTransfer
            case creditAlreadyInGroup
            case creditHasNoEurAmount
            case expenseNotDebit(txId: UUID)
            case expenseIsTransfer(txId: UUID)
            case expenseAlreadyInGroup(txId: UUID)
            case expenseOutsideWindow(txId: UUID, windowDays: Int)
            case expenseHasNoEurAmount(txId: UUID)
            case undercoverage(expenses: Decimal, credited: Decimal)
        }

        public struct CreateFromCreditInput: Equatable, Sendable {
            public var label: String
            public var creditTxId: UUID
            public var expenseTxIds: [UUID]

            public init(label: String, creditTxId: UUID, expenseTxIds: [UUID]) {
                self.label = label
                self.creditTxId = creditTxId
                self.expenseTxIds = expenseTxIds
            }
        }

        public struct CreateInput: Equatable, Sendable {
            public var label: String
            public var primaryTxId: UUID
            public var reimbursementTxIds: [UUID]

            public init(label: String, primaryTxId: UUID, reimbursementTxIds: [UUID]) {
                self.label = label
                self.primaryTxId = primaryTxId
                self.reimbursementTxIds = reimbursementTxIds
            }
        }

        public struct GroupNet: Equatable, Sendable {
            public let gross: Decimal
            public let reimbursed: Decimal
            public let net: Decimal
        }

        public struct GroupSummary: Equatable, Sendable {
            public let id: UUID
            public let label: String
            public let primaryTxId: UUID?
            public let gross: Decimal
            public let reimbursed: Decimal
            public let net: Decimal
        }

        public struct CandidateReimbursement: Equatable, Sendable {
            public let id: UUID
            public let bookedAt: Date
            public let amountEur: Decimal?
            public let counterparty: String?
            public let description: String?
            public let accountId: UUID?
        }

        public struct CandidateRefundedExpense: Equatable, Sendable {
            public let id: UUID
            public let bookedAt: Date
            public let amountEur: Decimal?
            public let counterparty: String?
            public let description: String?
            public let accountId: UUID?
            public let sharedExpenseGroupId: UUID?
            public let existingReimbursed: Decimal
        }

        // MARK: - Create / modify

        @MainActor
        @discardableResult
        public static func createGroup(
            _ input: CreateInput,
            in ctx: ModelContext,
            now: Date = .now
        ) throws -> SharedExpenseGroup {
            let label = input.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if label.isEmpty { throw Error.labelRequired }
            if input.reimbursementTxIds.isEmpty { throw Error.noReimbursements }
            if Set(input.reimbursementTxIds).contains(input.primaryTxId) {
                throw Error.primaryIsAlsoReimbursement
            }

            let primary = try loadTx(input.primaryTxId, label: "primary", in: ctx)
            let reimbursements = try loadTxs(input.reimbursementTxIds, in: ctx)

            if primary.direction != .debit { throw Error.primaryMustBeDebit }
            if primary.isTransfer { throw Error.primaryIsTransfer }
            if primary.sharedExpenseGroup != nil { throw Error.primaryAlreadyInGroup }
            let primaryAmount = try primaryAmount(primary)

            var total: Decimal = 0
            for r in reimbursements {
                total += try validateReimbursement(r, primary: primary)
            }
            try assertWithinPrimary(total, primaryAmount: primaryAmount)
            try assertSameSpace(primary: primary, others: reimbursements)

            let group = SharedExpenseGroup(
                label: label,
                primaryTx: primary,
                attributionMonth: monthStart(primary.bookedAt),
                createdAt: now,
                updatedAt: now
            )
            ctx.insert(group)

            primary.sharedExpenseGroup = group
            for r in reimbursements { r.sharedExpenseGroup = group }

            try ctx.saveTouchingChanges()
            return group
        }

        // Mirror of createGroup, starting from an incoming payment instead of an expense.
        // A group is just N debits + N credits; the difference is only which side you pick
        // first, and which way the coverage inequality points. Here the incoming money must
        // be fully accounted for: sum(expenses) >= credit.
        @MainActor
        @discardableResult
        public static func createGroupFromCredit(
            _ input: CreateFromCreditInput,
            in ctx: ModelContext,
            now: Date = .now
        ) throws -> SharedExpenseGroup {
            let label = input.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if label.isEmpty { throw Error.labelRequired }
            if input.expenseTxIds.isEmpty { throw Error.noExpenses }
            if Set(input.expenseTxIds).contains(input.creditTxId) {
                throw Error.creditIsAlsoExpense
            }

            let credit = try loadTx(input.creditTxId, label: "credit", in: ctx)
            let expenses = try loadTxs(input.expenseTxIds, in: ctx)

            if credit.direction != .credit { throw Error.creditMustBeCredit }
            if credit.isTransfer { throw Error.creditIsTransfer }
            if credit.sharedExpenseGroup != nil { throw Error.creditAlreadyInGroup }
            guard let creditEur = credit.amountEur else { throw Error.creditHasNoEurAmount }
            let credited = abs(creditEur)

            var expenseTotal: Decimal = 0
            for e in expenses {
                expenseTotal += try validateExpense(e, anchor: credit)
            }
            try assertCoversCredit(expenseTotal, credited: credited)
            try assertSameSpace(primary: credit, others: expenses)

            // The anchor drives attributionMonth and the reimbursement window for later
            // edits; the biggest expense is the most representative of the bundle.
            let anchor = expenses.max { lhs, rhs in
                (lhs.amountEur.map { abs($0) } ?? 0) < (rhs.amountEur.map { abs($0) } ?? 0)
            } ?? expenses[0]

            let group = SharedExpenseGroup(
                label: label,
                primaryTx: anchor,
                attributionMonth: monthStart(anchor.bookedAt),
                createdAt: now,
                updatedAt: now
            )
            ctx.insert(group)
            credit.sharedExpenseGroup = group
            for e in expenses { e.sharedExpenseGroup = group }

            try ctx.saveTouchingChanges()
            return group
        }

        // Adds more expenses to an existing group. Coverage is only asserted downward here
        // (expenses can always exceed credits); the credit-side cap is enforced by
        // addReimbursements.
        @MainActor
        public static func addExpenses(
            groupId: UUID,
            txIds: [UUID],
            in ctx: ModelContext,
            now: Date = .now
        ) throws {
            if txIds.isEmpty { return }
            let group = try loadGroup(groupId, in: ctx)
            guard let anchor = group.primaryTx else { throw Error.groupNotFound }
            let candidates = try loadTxs(txIds, in: ctx)
            for e in candidates { _ = try validateExpense(e, anchor: anchor) }
            try assertSameSpace(primary: anchor, others: candidates)
            for e in candidates { e.sharedExpenseGroup = group }
            group.updatedAt = now
            try ctx.saveTouchingChanges()
        }

        @MainActor
        public static func addReimbursements(
            groupId: UUID,
            txIds: [UUID],
            in ctx: ModelContext,
            now: Date = .now
        ) throws {
            if txIds.isEmpty { return }
            let group = try loadGroup(groupId, in: ctx)
            guard let primary = group.primaryTx else { throw Error.groupNotFound }
            let candidates = try loadTxs(txIds, in: ctx)
            let existingMembers = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.sharedExpenseGroup?.id == groupId }
            ))
            // Cap is the whole expense side of the group, not just the anchor.
            var expenseTotal: Decimal = 0
            var total: Decimal = 0
            for m in existingMembers {
                let eur = m.amountEur.map { abs($0) } ?? 0
                if m.direction == .debit { expenseTotal += eur } else { total += eur }
            }
            if expenseTotal == 0 { expenseTotal = try primaryAmount(primary) }
            for r in candidates {
                total += try validateReimbursement(r, primary: primary)
            }
            try assertWithinPrimary(total, primaryAmount: expenseTotal)
            try assertSameSpace(primary: primary, others: candidates)

            for r in candidates { r.sharedExpenseGroup = group }
            group.updatedAt = now
            try ctx.saveTouchingChanges()
        }

        @MainActor
        public static func removeReimbursement(
            groupId: UUID,
            txId: UUID,
            in ctx: ModelContext,
            now: Date = .now
        ) throws {
            let group = try loadGroup(groupId, in: ctx)
            let members = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.sharedExpenseGroup?.id == groupId }
            ))
            // The anchor can go as long as another expense can take its place — a group with
            // no expense side has nothing to net against.
            if group.primaryTx?.id == txId {
                let replacement = members.first { $0.id != txId && $0.direction == .debit }
                guard let replacement else { throw Error.cannotRemovePrimary }
                group.primaryTx = replacement
                group.attributionMonth = monthStart(replacement.bookedAt)
            }
            for tx in members where tx.id == txId { tx.sharedExpenseGroup = nil }
            group.updatedAt = now
            try ctx.saveTouchingChanges()
        }

        @MainActor
        public static func renameGroup(
            _ group: SharedExpenseGroup, label: String, in ctx: ModelContext, now: Date = .now
        ) throws {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw Error.labelRequired }
            group.label = trimmed
            group.updatedAt = now
            try ctx.saveTouchingChanges()
        }

        @MainActor
        public static func deleteGroup(_ group: SharedExpenseGroup, in ctx: ModelContext) throws {
            ctx.delete(group)
            try ctx.saveTouchingChanges()
        }

        // MARK: - Net summaries

        @MainActor
        public static func netForGroup(_ groupId: UUID, in ctx: ModelContext) throws -> GroupNet {
            _ = try loadGroup(groupId, in: ctx)
            let members = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.sharedExpenseGroup?.id == groupId }
            ))
            // Split by direction, not by "is it the primary" — a group can hold several
            // expenses. For a legacy single-expense group the only debit is the primary,
            // so this is identical to the old math.
            var gross: Decimal = 0
            var reimbursed: Decimal = 0
            for m in members {
                let eur = m.amountEur.map { abs($0) } ?? 0
                if m.direction == .debit { gross += eur } else { reimbursed += eur }
            }
            return GroupNet(gross: gross, reimbursed: reimbursed, net: gross - reimbursed)
        }

        @MainActor
        public static func netForGroups(
            _ ids: [UUID],
            in ctx: ModelContext
        ) throws -> [UUID: GroupSummary] {
            if ids.isEmpty { return [:] }
            let idSet = Set(ids)
            let groups = try ctx.fetch(FetchDescriptor<SharedExpenseGroup>(
                predicate: #Predicate { idSet.contains($0.id) }
            ))
            let allMembers = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.sharedExpenseGroup != nil }
            ))
            let members = allMembers.filter {
                guard let g = $0.sharedExpenseGroup else { return false }
                return idSet.contains(g.id)
            }
            var out: [UUID: GroupSummary] = [:]
            var grossById: [UUID: Decimal] = [:]
            var reimbursedById: [UUID: Decimal] = [:]
            for g in groups {
                grossById[g.id] = 0
                reimbursedById[g.id] = 0
            }
            for m in members {
                guard let gid = m.sharedExpenseGroup?.id else { continue }
                let eur = m.amountEur.map { abs($0) } ?? 0
                if m.direction == .debit {
                    grossById[gid, default: 0] += eur
                } else {
                    reimbursedById[gid, default: 0] += eur
                }
            }
            for g in groups {
                let gross = grossById[g.id] ?? 0
                let reimbursed = reimbursedById[g.id] ?? 0
                out[g.id] = GroupSummary(
                    id: g.id,
                    label: g.label,
                    primaryTxId: g.primaryTx?.id,
                    gross: gross,
                    reimbursed: reimbursed,
                    net: gross - reimbursed
                )
            }
            return out
        }

        // MARK: - Candidate search

        @MainActor
        public static func findCandidateReimbursements(
            primaryTxId: UUID,
            query: String,
            in ctx: ModelContext,
            limit: Int = 50
        ) throws -> [CandidateReimbursement] {
            let primary = try loadTx(primaryTxId, label: "primary", in: ctx)
            let primarySpaceId = primary.account?.space?.id
            let windowStart = primary.bookedAt.addingTimeInterval(-windowSeconds())
            let windowEnd = primary.bookedAt.addingTimeInterval(windowSeconds())

            let raw = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate {
                    $0.isTransfer == false &&
                    $0.sharedExpenseGroup == nil &&
                    $0.bookedAt >= windowStart &&
                    $0.bookedAt <= windowEnd
                },
                sortBy: [SortDescriptor(\.bookedAt, order: .reverse)]
            ))
            let n = query.lowercased()
            let filtered = raw.lazy.filter { tx in
                guard tx.direction == .credit else { return false }
                guard let acc = tx.account, !acc.archived, !acc.excluded else { return false }
                if acc.space?.id != primarySpaceId { return false }
                if n.isEmpty { return true }
                let cp = (tx.counterparty ?? "").lowercased()
                let d = (tx.transactionDescription ?? "").lowercased()
                return cp.contains(n) || d.contains(n)
            }
            return filtered.prefix(limit).map { tx in
                CandidateReimbursement(
                    id: tx.id,
                    bookedAt: tx.bookedAt,
                    amountEur: tx.amountEur,
                    counterparty: tx.counterparty,
                    description: tx.transactionDescription,
                    accountId: tx.account?.id
                )
            }
        }

        @MainActor
        public static func findCandidateRefundedExpenses(
            creditTxId: UUID,
            query: String,
            in ctx: ModelContext,
            limit: Int = 50
        ) throws -> [CandidateRefundedExpense] {
            let credit = try loadTx(creditTxId, label: "credit", in: ctx)
            if credit.direction != .credit { throw Error.startingTxNotCredit }
            let creditSpaceId = credit.account?.space?.id
            let windowStart = credit.bookedAt.addingTimeInterval(-windowSeconds())
            let windowEnd = credit.bookedAt.addingTimeInterval(windowSeconds())

            let raw = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate {
                    $0.isTransfer == false &&
                    $0.bookedAt >= windowStart &&
                    $0.bookedAt <= windowEnd
                },
                sortBy: [SortDescriptor(\.bookedAt, order: .reverse)]
            ))
            let n = query.lowercased()
            let filtered = raw.lazy.filter { tx in
                guard tx.direction == .debit else { return false }
                guard let acc = tx.account, !acc.archived, !acc.excluded else { return false }
                if acc.space?.id != creditSpaceId { return false }
                if n.isEmpty { return true }
                let cp = (tx.counterparty ?? "").lowercased()
                let d = (tx.transactionDescription ?? "").lowercased()
                return cp.contains(n) || d.contains(n)
            }
            let rows = Array(filtered.prefix(limit))

            // Per-group existing-reimbursed totals
            let groupedIds = rows.compactMap { $0.sharedExpenseGroup?.id }
            var reimbursedByGroup: [UUID: Decimal] = [:]
            if !groupedIds.isEmpty {
                let summaries = try netForGroups(groupedIds, in: ctx)
                for (id, s) in summaries { reimbursedByGroup[id] = s.reimbursed }
            }

            return rows.map { tx in
                let gid = tx.sharedExpenseGroup?.id
                return CandidateRefundedExpense(
                    id: tx.id,
                    bookedAt: tx.bookedAt,
                    amountEur: tx.amountEur,
                    counterparty: tx.counterparty,
                    description: tx.transactionDescription,
                    accountId: tx.account?.id,
                    sharedExpenseGroupId: gid,
                    existingReimbursed: gid.flatMap { reimbursedByGroup[$0] } ?? 0
                )
            }
        }

        // MARK: - Helpers

        public static func monthStart(_ date: Date) -> Date {
            var cal = Calendar(identifier: .iso8601)
            cal.timeZone = TimeZone(identifier: "UTC")!
            let comps = cal.dateComponents([.year, .month], from: date)
            return cal.date(from: comps) ?? date
        }

        private static func windowSeconds() -> TimeInterval {
            Double(reimbursementWindowDays) * 86_400
        }

        private static func withinWindow(_ a: Date, _ b: Date) -> Bool {
            abs(a.timeIntervalSince(b)) <= windowSeconds()
        }

        private static func primaryAmount(_ p: Transaction) throws -> Decimal {
            guard let eur = p.amountEur else { throw Error.primaryHasNoEurAmount }
            return abs(eur)
        }

        private static func validateReimbursement(
            _ r: Transaction,
            primary: Transaction
        ) throws -> Decimal {
            if r.direction != .credit { throw Error.reimbursementNotCredit(txId: r.id) }
            if r.isTransfer { throw Error.reimbursementIsTransfer(txId: r.id) }
            if r.sharedExpenseGroup != nil { throw Error.reimbursementAlreadyInGroup(txId: r.id) }
            if !withinWindow(r.bookedAt, primary.bookedAt) {
                throw Error.reimbursementOutsideWindow(txId: r.id, windowDays: reimbursementWindowDays)
            }
            guard let eur = r.amountEur else { throw Error.reimbursementHasNoEurAmount(txId: r.id) }
            return abs(eur)
        }

        private static func assertWithinPrimary(
            _ total: Decimal,
            primaryAmount: Decimal
        ) throws {
            if total > primaryAmount + overcoverageEpsilon {
                throw Error.overcoverage(reimbursed: total, primary: primaryAmount)
            }
        }

        private static func validateExpense(
            _ e: Transaction,
            anchor: Transaction
        ) throws -> Decimal {
            if e.direction != .debit { throw Error.expenseNotDebit(txId: e.id) }
            if e.isTransfer { throw Error.expenseIsTransfer(txId: e.id) }
            if e.sharedExpenseGroup != nil { throw Error.expenseAlreadyInGroup(txId: e.id) }
            if !withinWindow(e.bookedAt, anchor.bookedAt) {
                throw Error.expenseOutsideWindow(txId: e.id, windowDays: reimbursementWindowDays)
            }
            guard let eur = e.amountEur else { throw Error.expenseHasNoEurAmount(txId: e.id) }
            return abs(eur)
        }

        private static func assertCoversCredit(
            _ expenseTotal: Decimal,
            credited: Decimal
        ) throws {
            if expenseTotal + overcoverageEpsilon < credited {
                throw Error.undercoverage(expenses: expenseTotal, credited: credited)
            }
        }

        @MainActor
        private static func assertSameSpace(
            primary: Transaction,
            others: [Transaction]
        ) throws {
            if others.isEmpty { return }
            let primarySpace = primary.account?.space?.id
            for r in others {
                if r.account?.space?.id != primarySpace {
                    throw Error.crossSpace(txId: r.id)
                }
            }
        }

        @MainActor
        private static func loadTx(
            _ id: UUID,
            label: String,
            in ctx: ModelContext
        ) throws -> Transaction {
            let rows = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.id == id }
            ))
            guard let tx = rows.first else { throw Error.txNotFound(label: label) }
            return tx
        }

        @MainActor
        private static func loadTxs(_ ids: [UUID], in ctx: ModelContext) throws -> [Transaction] {
            if ids.isEmpty { return [] }
            let idSet = Set(ids)
            let rows = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate { idSet.contains($0.id) }
            ))
            if rows.count != ids.count { throw Error.txNotFound(label: "one or more transactions") }
            return rows
        }

        @MainActor
        private static func loadGroup(_ id: UUID, in ctx: ModelContext) throws -> SharedExpenseGroup {
            let rows = try ctx.fetch(FetchDescriptor<SharedExpenseGroup>(
                predicate: #Predicate { $0.id == id }
            ))
            guard let g = rows.first else { throw Error.groupNotFound }
            return g
        }
    }
}
