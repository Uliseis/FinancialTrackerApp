import Foundation
import SwiftData
import CoreModel

extension CoreLogic {
    public enum Transactions {
        public enum MutationError: Swift.Error, Equatable {
            case amountMustBePositive
            case isMirrorLeg
            case isPairedTransfer
        }

        // A user-entered transaction (quick-add / manual form). externalId "manual-tx:<uuid>";
        // `amount` is passed as a positive magnitude and STORED SIGNED to match the rest of the
        // store (debits negative, credits positive — the display/balance math keys off the sign,
        // see TransactionsView). Mirrors addInterest's FX shape: EUR rows are their own EUR value,
        // others get amountEur backfilled by the FX pass. categorySource stays .bank when no
        // category is chosen so the rule engine can classify it (applyRulesToTransactions skips
        // .manual); an explicitly chosen category is .manual.
        @MainActor @discardableResult
        public static func createManual(
            account: Account,
            amount: Decimal,
            direction: TxDirection = .debit,
            bookedAt: Date,
            description: String? = nil,
            counterparty: String? = nil,
            category: CoreModel.Category? = nil,
            in ctx: ModelContext,
            now: Date = .now
        ) throws -> Transaction {
            guard amount > 0 else { throw MutationError.amountMustBePositive }
            let signed: Decimal = direction == .debit ? -amount : amount
            let clean = description?.trimmingCharacters(in: .whitespacesAndNewlines)
            let isEur = account.currency.uppercased() == "EUR"
            let tx = Transaction(
                account: account,
                externalId: "manual-tx:\(UUID().uuidString)",
                bookedAt: bookedAt,
                amount: signed,
                currency: account.currency,
                amountEur: isEur ? signed : nil,
                fxRateUsed: isEur ? 1 : nil,
                direction: direction,
                description: (clean?.isEmpty == false ? clean : nil),
                counterparty: counterparty,
                category: category,
                categorySource: category == nil ? .bank : .manual,
                createdAt: now)
            ctx.insert(tx)
            try ctx.saveTouchingChanges()
            return tx
        }

        // Edits the user-correctable fields of any transaction, bank-sourced included:
        // EBSync skips (accountId, externalId) rows it already has, so an edit is never
        // clobbered by a later sync. `amount` is a positive magnitude like createManual;
        // the stored value is signed from `direction`. Changing the amount re-derives
        // amountEur only for EUR accounts — a foreign-currency row keeps its booked FX
        // rate, since we can't re-fetch the rate that applied on the day.
        @MainActor
        public static func update(
            _ tx: Transaction,
            amount: Decimal,
            direction: TxDirection,
            bookedAt: Date,
            description: String?,
            counterparty: String?,
            category: CoreModel.Category?,
            in ctx: ModelContext,
            now: Date = .now
        ) throws {
            guard amount > 0 else { throw MutationError.amountMustBePositive }
            let signed: Decimal = direction == .debit ? -amount : amount
            let categoryChanged = tx.category?.id != category?.id

            tx.amount = signed
            tx.direction = direction
            tx.bookedAt = bookedAt
            tx.transactionDescription = cleaned(description)
            tx.counterparty = cleaned(counterparty)
            if tx.currency.uppercased() == "EUR" {
                tx.amountEur = signed
                tx.fxRateUsed = 1
            } else if let rate = tx.fxRateUsed, rate != 0 {
                tx.amountEur = signed / rate
            }
            if categoryChanged {
                tx.category = category
                // A hand-picked category outranks the rule engine and wins sync conflicts.
                tx.categorySource = category == nil ? .bank : .manual
            }
            tx.updatedAt = now
            try ctx.saveTouchingChanges()
        }

        // Refuses on transfer legs: deleting half a pair would leave the other side
        // orphaned and break the transfer invariants. Unpair first, then delete.
        // Own mirrors and an owned shared-expense group cascade away with the row.
        @MainActor
        public static func delete(_ tx: Transaction, in ctx: ModelContext) throws {
            if tx.routedFromTx != nil { throw MutationError.isMirrorLeg }
            if tx.transferGroup != nil { throw MutationError.isPairedTransfer }
            ctx.delete(tx)
            try ctx.saveTouchingChanges()
        }

        // Locale-agnostic money parse. "42.50", "42,50", "1.234,56" and "1,234.56" all mean
        // what a human means by them: the LAST separator followed by 1-2 digits is the
        // decimal point, everything else is grouping. A locale-bound numeric TextField gets
        // this wrong in both directions — in es-ES "42.50" parses as forty-two thousand five
        // hundred — and it's a money path, so we don't leave it to the formatter.
        public static func parseAmount(_ raw: String) -> Decimal? {
            var s = raw.trimmingCharacters(in: .whitespaces)
            s.removeAll { $0 == " " || $0 == "€" || $0 == "$" || $0 == "\u{00A0}" }
            guard !s.isEmpty else { return nil }

            let lastComma = s.lastIndex(of: ",")
            let lastDot = s.lastIndex(of: ".")
            let decimalSep: Character?
            switch (lastComma, lastDot) {
            case let (c?, d?): decimalSep = c > d ? "," : "."
            case (let c?, nil): decimalSep = s[c...].count <= 3 ? "," : nil
            case (nil, let d?): decimalSep = s[d...].count <= 3 ? "." : nil
            case (nil, nil): decimalSep = nil
            }

            var normalized = ""
            var seenDecimal = false
            for (offset, ch) in s.enumerated() {
                let idx = s.index(s.startIndex, offsetBy: offset)
                if ch == "," || ch == "." {
                    // Only the final separator survives, and only as the decimal point.
                    let isDecimal = decimalSep == ch && !seenDecimal
                        && !s[s.index(after: idx)...].contains(where: { $0 == "," || $0 == "." })
                    if isDecimal { normalized.append("."); seenDecimal = true }
                    continue
                }
                normalized.append(ch)
            }
            guard let d = Decimal(string: normalized), d > 0 else { return nil }
            return d
        }

        // Quantities are not money: 0,06033031 BTC is eight decimals, and parseAmount's
        // "1-2 digits after the separator" rule would read that comma as grouping and return
        // 6033031. Here the LAST separator is always the decimal point, whatever follows it.
        public static func parseQuantity(_ raw: String) -> Decimal? {
            var s = raw.trimmingCharacters(in: .whitespaces)
            s.removeAll { $0 == " " || $0 == "\u{00A0}" }
            guard !s.isEmpty else { return nil }

            var normalized = ""
            let lastSeparator = s.lastIndex(where: { $0 == "," || $0 == "." })
            for idx in s.indices {
                let ch = s[idx]
                if ch == "," || ch == "." {
                    if idx == lastSeparator { normalized.append(".") }
                    continue
                }
                normalized.append(ch)
            }
            guard let d = Decimal(string: normalized), d > 0 else { return nil }
            return d
        }

        private static func cleaned(_ s: String?) -> String? {
            let t = s?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t?.isEmpty ?? true) ? nil : t
        }
    }
}
