import Foundation

enum Money {
    static func format(_ amount: Decimal, currency: String) -> String {
        amount.formatted(.currency(code: currency))
    }

    // Seed text for an editable amount field: no grouping, no symbol, locale decimal
    // separator so it round-trips through CoreLogic.Transactions.parseAmount.
    // Whole amounts stay bare ("20"); anything with cents shows both digits ("123,40").
    static func plainAmountText(_ amount: Decimal) -> String {
        var whole = Decimal()
        var copy = amount
        NSDecimalRound(&whole, &copy, 0, .plain)
        let digits = whole == amount ? 0 : 2
        return amount.formatted(.number.grouping(.never).precision(.fractionLength(digits)))
    }
}
