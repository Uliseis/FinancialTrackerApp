import Foundation
import SwiftData
import CoreModel

extension CoreLogic {
    public enum Transactions {
        public enum MutationError: Swift.Error, Equatable {
            case amountMustBePositive
        }

        // A user-entered transaction (quick-add / manual form). externalId "manual-tx:<uuid>";
        // amount is always positive, sign carried by `direction`. Mirrors addInterest's FX shape:
        // EUR rows are their own EUR value, others get amountEur backfilled by the FX pass.
        // categorySource stays .bank when no category is chosen so the rule engine can classify
        // it (applyRulesToTransactions skips .manual); an explicitly chosen category is .manual.
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
            let clean = description?.trimmingCharacters(in: .whitespacesAndNewlines)
            let isEur = account.currency.uppercased() == "EUR"
            let tx = Transaction(
                account: account,
                externalId: "manual-tx:\(UUID().uuidString)",
                bookedAt: bookedAt,
                amount: amount,
                currency: account.currency,
                amountEur: isEur ? amount : nil,
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
    }
}
