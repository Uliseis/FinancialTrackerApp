import Foundation
import SwiftData
import CoreModel

extension CoreLogic {
    // Monthly statement import for a manual account (the Revolut credit card). Rows the user
    // already quick-added during the month are matched by content — same amount, within
    // matchWindow — and upgraded to the statement's externalId, so the next import is a plain
    // id dedupe and the user's merchant naming and category survive. Only genuinely new
    // charges are inserted.
    public enum StatementImport {
        public struct Summary: Equatable, Sendable {
            public var parsed = 0
            public var inserted = 0
            public var matchedManual = 0
            public var skippedDuplicate = 0
            public var skippedTransfers = 0
            public var categorized = 0
            public var errors: [String] = []
            public init() {}
        }

        public enum ImportError: Error, Equatable {
            case notManualAccount
            case archived
        }

        public static let matchWindow: TimeInterval = 3 * 86_400
        // Quick-add rows and screenshot-sourced rows are the only ones a statement can supersede.
        static let matchablePrefixes = ["manual-tx:", "revolutshot:", Automations.recurringPrefix]

        @MainActor @discardableResult
        public static func importRevolutCSV(
            _ text: String, into account: Account, in ctx: ModelContext, now: Date = .now
        ) throws -> Summary {
            guard CoreLogic.Accounts.isManual(account) else { throw ImportError.notManualAccount }
            guard !account.archived else { throw ImportError.archived }
            let parsed = try RevolutCSV.parse(text)

            var summary = Summary()
            summary.parsed = parsed.rows.count + parsed.skippedTransfers
            summary.skippedTransfers = parsed.skippedTransfers
            summary.errors = parsed.errors

            let accountId = account.id
            let existing = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.account?.id == accountId }))
            let known = Set(existing.map(\.externalId))
            var fresh: [RevolutCSV.Row] = []
            for row in parsed.rows {
                if known.contains(row.externalId) { summary.skippedDuplicate += 1 } else { fresh.append(row) }
            }

            // Nearest-in-time pairs first, globally, so a charge two days off can't steal the
            // candidate that belongs to an identical charge two hours off.
            let candidates = existing.filter { tx in
                matchablePrefixes.contains { tx.externalId.hasPrefix($0) }
            }
            var pairs: [(distance: TimeInterval, row: Int, candidate: Int)] = []
            for (r, row) in fresh.enumerated() {
                for (c, tx) in candidates.enumerated() where tx.amount == row.amount {
                    let distance = abs(tx.bookedAt.timeIntervalSince(row.startedAt))
                    if distance <= matchWindow { pairs.append((distance, r, c)) }
                }
            }
            pairs.sort { $0.distance < $1.distance }
            var usedRows = Set<Int>()
            var usedCandidates = Set<Int>()
            for pair in pairs where !usedRows.contains(pair.row) && !usedCandidates.contains(pair.candidate) {
                usedRows.insert(pair.row)
                usedCandidates.insert(pair.candidate)
                let tx = candidates[pair.candidate]
                let row = fresh[pair.row]
                tx.externalId = row.externalId
                tx.valueAt = row.completedAt
                tx.updatedAt = now
                summary.matchedManual += 1
            }

            let isEur = account.currency.uppercased() == "EUR"
            var insertedIds: [UUID] = []
            for (r, row) in fresh.enumerated() where !usedRows.contains(r) {
                let tx = Transaction(
                    account: account,
                    externalId: row.externalId,
                    bookedAt: row.startedAt,
                    valueAt: row.completedAt,
                    amount: row.amount,
                    currency: account.currency,
                    amountEur: isEur ? row.amount : nil,
                    fxRateUsed: isEur ? 1 : nil,
                    direction: row.amount < 0 ? .debit : .credit,
                    description: row.description,
                    categorySource: .bank,
                    createdAt: now)
                ctx.insert(tx)
                insertedIds.append(tx.id)
            }
            summary.inserted = insertedIds.count
            try ctx.saveTouchingChanges()
            if !insertedIds.isEmpty {
                summary.categorized = try Categorize.applyRulesToTransactions(in: ctx, txIds: insertedIds).updated
            }
            return summary
        }
    }
}
