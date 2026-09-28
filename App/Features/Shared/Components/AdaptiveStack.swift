import SwiftUI

// A row that stacks at accessibility text sizes. Side-by-side columns at AX5 leave each
// label a few characters wide, so words hyphenate mid-syllable and amounts truncate to "8…".
struct AdaptiveStack<Content: View>: View {
    var alignment: VerticalAlignment = .center
    var spacing: CGFloat?
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
        // Ideal height when stacked, so a Spacer meant for horizontal slack stays at its
        // minimum instead of soaking up the card's spare height.
        layout { content }
            .fixedSize(horizontal: false, vertical: stacked)
    }
}
