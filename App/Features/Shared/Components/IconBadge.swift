import SwiftUI

// Rounded-square symbol chip: tinted glyph on a soft wash of the same tint.
// Shared idiom across Accounts rows and Settings rows. Decorative.
struct IconBadge: View {
    let systemName: String
    var tint: Color = .brand
    var size: CGFloat = 30
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    private var dimension: CGFloat { size * scale }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: dimension * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: dimension, height: dimension)
            .background(tint.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: dimension * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}
