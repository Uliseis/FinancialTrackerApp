import Foundation
import SwiftData
import CoreModel

extension CoreLogic {
    // Things the app books on its own and asks about afterwards, instead of waiting for a
    // tap: a subscription on its expected day, and the fixed pension slice of a broker
    // top-up. Every booking is marked so it can be found, undone, and never re-proposed.
    public enum Automations {
        public static let recurringPrefix = "auto-recurring:v1:"
        public static let splitMarkerKey = "autoSplitOf"

        // MARK: - Recurring charges

        public struct BookedRecurring: Equatable, Sendable {
            public let transactionId: UUID
            public let externalId: String
            public let key: String
            public let merchant: String
            public let amount: Decimal
            public let currency: String
            public let accountName: String
        }

        public static func recurringExternalId(key: String, month: Date, calendar: Calendar = .current) -> String {
            let c = calendar.dateComponents([.year, .month], from: month)
            return recurringPrefix + String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0) + ":" + RevolutCSV.slug(key)
        }

        // Books every due, unbooked recurring item on manual accounts. `muted` are keys the
        // user stopped; `declined` are externalIds the user deleted this month, so a deleted
        // booking doesn't come straight back. Idempotent: the id is (month, key).
        @MainActor @discardableResult
        public static func bookDueRecurring(
            in ctx: ModelContext, muted: Set<String>, declined: Set<String>,
            now: Date = .now, calendar: Calendar = .current
        ) throws -> [BookedRecurring] {
            let accounts = try ctx.fetch(FetchDescriptor<Account>())
                .filter { $0.connection == nil && !$0.archived }
            let today = calendar.component(.day, from: now)
            var booked: [BookedRecurring] = []
            for account in accounts {
                let accountId = account.id
                let txs = try ctx.fetch(FetchDescriptor<Transaction>(
                    predicate: #Predicate { $0.account?.id == accountId }))
                let items = Recurring.detect(txs, month: now, calendar: calendar)
                for item in items where item.bookedAt == nil && today >= item.expectedDay && !muted.contains(item.key) {
                    let eid = recurringExternalId(key: item.key, month: now, calendar: calendar)
                    if declined.contains(eid) || txs.contains(where: { $0.externalId == eid }) { continue }
                    let isEur = account.currency.uppercased() == "EUR"
                    let tx = Transaction(
                        account: account,
                        externalId: eid,
                        bookedAt: now,
                        amount: item.amount,
                        currency: account.currency,
                        amountEur: isEur ? item.amount : nil,
                        fxRateUsed: isEur ? 1 : nil,
                        direction: .debit,
                        description: item.merchant,
                        counterparty: item.merchant,
                        categorySource: .bank,
                        createdAt: now)
                    ctx.insert(tx)
                    booked.append(BookedRecurring(
                        transactionId: tx.id, externalId: eid, key: item.key, merchant: item.merchant,
                        amount: item.amount, currency: account.currency, accountName: account.displayName))
                }
            }
            if !booked.isEmpty {
                try ctx.saveTouchingChanges()
                _ = try Categorize.applyRulesToTransactions(in: ctx, txIds: booked.map(\.transactionId))
            }
            return booked
        }

        // MARK: - Pension split

        public struct SplitRule: Equatable, Sendable {
            public let sourceAccountId: UUID
            public let targetAccountId: UUID
            public let amountEur: Decimal
            public let since: Date
            public init(sourceAccountId: UUID, targetAccountId: UUID, amountEur: Decimal, since: Date) {
                self.sourceAccountId = sourceAccountId
                self.targetAccountId = targetAccountId
                self.amountEur = amountEur
                self.since = since
            }
        }

        public struct BookedSplit: Equatable, Sendable {
            public let debitTxId: UUID
            public let arrivalTxId: UUID
            public let arrivedEur: Decimal
            public let arrivedAt: Date
            public let amountEur: Decimal
        }

        // For every transfer that arrived in the source account since `since` and hasn't been
        // split (or declined), moves the fixed amount to the target as an internal transfer
        // dated with the arrival. The debit leg carries the arrival id in rawJSON — that is
        // the idempotency key and what Undo reads back.
        @MainActor @discardableResult
        public static func bookSplits(
            rule: SplitRule, in ctx: ModelContext, declined: Set<UUID>, now: Date = .now
        ) throws -> [BookedSplit] {
            let sourceId = rule.sourceAccountId
            let targetId = rule.targetAccountId
            guard let source = try ctx.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == sourceId })).first,
                  let target = try ctx.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == targetId })).first
            else { return [] }
            let since = rule.since
            let rows = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.account?.id == sourceId && $0.bookedAt >= since }))
            let handled = Set(rows.compactMap(splitSource(of:)))
            let arrivals = rows.filter {
                $0.direction == .credit && $0.isTransfer
                    && !$0.externalId.hasPrefix(Transfers.internalPrefix)
                    && ($0.amountEur ?? 0) >= rule.amountEur
                    && !handled.contains($0.id) && !declined.contains($0.id)
            }.sorted { $0.bookedAt < $1.bookedAt }

            var out: [BookedSplit] = []
            for arrival in arrivals {
                let group = try Transfers.createInternalTransfer(
                    from: source, to: target, amountEur: rule.amountEur,
                    bookedAt: arrival.bookedAt, note: "Pension split", in: ctx, now: now)
                let gid = group.id
                let members = try ctx.fetch(FetchDescriptor<Transaction>(
                    predicate: #Predicate { $0.transferGroup?.id == gid }))
                guard let debit = members.first(where: { $0.direction == .debit }) else { continue }
                debit.rawJSON = try JSONEncoder().encode([splitMarkerKey: arrival.id.uuidString])
                out.append(BookedSplit(
                    debitTxId: debit.id, arrivalTxId: arrival.id,
                    arrivedEur: arrival.amountEur ?? 0, arrivedAt: arrival.bookedAt,
                    amountEur: rule.amountEur))
            }
            if !out.isEmpty { try ctx.saveTouchingChanges() }
            return out
        }

        public static func splitSource(of tx: Transaction) -> UUID? {
            guard tx.externalId.hasPrefix(Transfers.internalPrefix), let data = tx.rawJSON,
                  let dict = try? JSONDecoder().decode([String: String].self, from: data),
                  let raw = dict[splitMarkerKey] else { return nil }
            return UUID(uuidString: raw)
        }

        // Removes both legs. Returns the arrival id so the caller can remember the refusal.
        @MainActor @discardableResult
        public static func undoSplit(debitTxId: UUID, in ctx: ModelContext) throws -> UUID? {
            guard let debit = try ctx.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.id == debitTxId })).first else { return nil }
            let arrival = splitSource(of: debit)
            var legs = [debit]
            if let gid = debit.transferGroup?.id {
                legs = try ctx.fetch(FetchDescriptor<Transaction>(
                    predicate: #Predicate { $0.transferGroup?.id == gid }))
            }
            try Transfers.unpair(debit, in: ctx)
            for leg in legs { ctx.delete(leg) }
            try ctx.saveTouchingChanges()
            return arrival
        }
    }
}
