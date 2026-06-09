import SwiftUI

extension Color {
    static let positiveAmount = Color("PositiveAmount")
    static let negativeAmount = Color("NegativeAmount")
    static let categoryFallback = Color("CategoryFallback")
}

enum Theme {
    enum Radius {
        static let card: CGFloat = 16
    }
    enum Size {
        static let dot: CGFloat = 10
    }

    // Sign-based money color. Income/gains positive, spending/losses negative,
    // zero neutral. Single source so every amount in the app reads the same way.
    static func amountColor(_ value: Decimal) -> Color {
        if value > 0 { return .positiveAmount }
        if value < 0 { return .negativeAmount }
        return .secondary
    }

    static func fraction(_ part: Decimal, of whole: Decimal) -> Double {
        guard whole > 0 else { return 0 }
        return min(1, max(0, NSDecimalNumber(decimal: part / whole).doubleValue))
    }
}

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
