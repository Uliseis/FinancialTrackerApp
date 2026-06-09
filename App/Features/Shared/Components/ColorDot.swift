import SwiftUI

struct ColorDot: View {
    let hex: String?
    var size: CGFloat = Theme.Size.dot

    var body: some View {
        Circle()
            .fill(Color(hex: hex) ?? .categoryFallback)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
