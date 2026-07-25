import SwiftUI
import CoreModel

// A category's icon, derived from its name. Categories carry a colour but no symbol, and
// adding one would mean a model + CloudKit schema change for what is, for a single user
// with fourteen categories, a lookup table.
// ponytail: name-matched. A renamed category falls back to the neutral glyph, which is
// correct-but-plain; give Category a `symbol` field if the set ever churns.
enum CategoryGlyph {
    static let fallback = "circle.dashed"

    static func symbol(for name: String?) -> String {
        guard let name = name?.lowercased(), !name.isEmpty else { return fallback }
        for (needle, symbol) in table where name.contains(needle) {
            return symbol
        }
        return fallback
    }

    // Longest / most specific needles first — "other income" must beat "income".
    private static let table: [(String, String)] = [
        ("other income", "arrow.down.circle"),
        ("entertainment", "theatermasks"),
        ("subscription", "arrow.clockwise"),
        ("restaurant", "fork.knife"),
        ("grocer", "basket"),
        ("transport", "tram"),
        ("housing", "house"),
        ("utilit", "bolt"),
        ("health", "cross.case"),
        ("shopping", "bag"),
        ("travel", "airplane"),
        ("salary", "banknote"),
        ("income", "arrow.down.circle"),
        ("fee", "percent"),
    ]
}

// Category chip for a transaction row: the category's colour, its glyph, muted when the
// transaction has no category at all.
struct CategoryBadge: View {
    let category: CoreModel.Category?
    var size: CGFloat = 34

    private var tint: Color {
        guard let hex = category?.color, let color = Color(hex: hex) else {
            return .categoryFallback
        }
        return color
    }

    var body: some View {
        IconBadge(systemName: CategoryGlyph.symbol(for: category?.name),
                  tint: tint, size: size)
    }
}
