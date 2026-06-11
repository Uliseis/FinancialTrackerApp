import SwiftUI

extension Color {
    static let positiveAmount = Color("PositiveAmount")
    static let negativeAmount = Color("NegativeAmount")
    static let categoryFallback = Color("CategoryFallback")

    // Brand teal (the compass). Mirrors AccentColor; named for intent at call sites.
    static let brand = Color.accentColor
}

enum Theme {
    // 8pt spacing grid — every gap in the app should come from here.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }
    enum Radius {
        static let card: CGFloat = 16
        static let hero: CGFloat = 24
    }
    enum Size {
        static let dot: CGFloat = 10
    }

    // The signature "instrument panel": a deep teal→charcoal wash used for the
    // net-worth hero in BOTH light and dark, so the readout always reads as a
    // precise dark instrument and the teal accent pops.
    static let heroFill = LinearGradient(
        colors: [
            Color(.sRGB, red: 0.059, green: 0.239, blue: 0.220),
            Color(.sRGB, red: 0.031, green: 0.118, blue: 0.110)
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // Bright mint-teal for accents that sit ON the always-dark hero (the
    // mode-aware accent would be too dim there). Matches the icon's gem.
    static let heroAccent = Color(.sRGB, red: 0.271, green: 0.839, blue: 0.776)

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

extension Font {
    // Tabular rounded "readout" digits, sized off a Dynamic Type style so it
    // scales for accessibility. The instrument look comes from .rounded + tabular.
    static func readout(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded).weight(weight).monospacedDigit()
    }
}

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
