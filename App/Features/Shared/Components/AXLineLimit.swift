import SwiftUI

// A line limit that lifts at accessibility sizes, where one line holds a few characters
// and truncation hides the whole name.
private struct AXLineLimit: ViewModifier {
    let limit: Int
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content.lineLimit(typeSize.isAccessibilitySize ? nil : limit)
    }
}

extension View {
    func axLineLimit(_ limit: Int) -> some View {
        modifier(AXLineLimit(limit: limit))
    }
}
