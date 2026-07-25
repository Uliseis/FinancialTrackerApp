import SwiftUI

// The app's signature surface: a deep teal→charcoal wash that stays dark in both
// appearances, so a headline figure always reads as a precise instrument. Extracted from
// the Dashboard net-worth card so second-level screens can carry the same idiom instead of
// each inventing its own header.
struct InstrumentPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.heroFill)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                    .strokeBorder(.white.opacity(0.07), lineWidth: 1)
            )
    }
}

extension View {
    // Drops a panel into a Form/List row without the surrounding chrome fighting it.
    func instrumentPanelRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: Theme.Space.s, leading: Theme.Space.m,
                                      bottom: Theme.Space.m, trailing: Theme.Space.m))
    }
}

// Small-caps label for use on the panel, where secondary greys are too dim.
struct PanelLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(1.1)
            .foregroundStyle(.white.opacity(0.55))
    }
}
