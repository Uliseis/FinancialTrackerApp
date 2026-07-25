import Foundation

enum Money {
    static func format(_ amount: Decimal, currency: String) -> String {
        amount.formatted(.currency(code: currency))
    }

    // Seed text for an editable amount field: no grouping, no symbol, locale decimal
    // separator so it round-trips through CoreLogic.Transactions.parseAmount.
    static func plainAmountText(_ amount: Decimal) -> String {
        amount.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
    }
}
