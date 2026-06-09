import Foundation
import SwiftData
import CoreModel
import CoreLogic

enum Money {
    static func format(_ amount: Decimal, currency: String) -> String {
        amount.formatted(.currency(code: currency))
    }

    // EUR value of an account's stored balance. EUR passes through; other currencies
    // convert at today's rate via the FX table. nil when no balance or no rate.
    @MainActor
    static func eurBalance(of account: Account, in ctx: ModelContext) -> Decimal? {
        guard let balance = account.balance else { return nil }
        if account.currency.uppercased() == "EUR" { return balance }
        return (try? FX.toEur(
            amount: balance, currency: account.currency, date: .now, in: ctx
        ))??.amountEur
    }
}
