import SwiftUI

// Discrete hex-palette picker bound to an optional hex string (nil ⇒ no color).
// Discrete swatches round-trip cleanly with Color(hex:) — avoids lossy Color→hex
// conversion that a system ColorPicker would force.
struct ColorSwatchPicker: View {
    @Binding var selection: String?

    static let palette = [
        "#ef4444", "#f97316", "#eab308", "#22c55e", "#14b8a6",
        "#3b82f6", "#6366f1", "#a855f7", "#ec4899", "#64748b",
    ]

    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            swatch(nil)
            ForEach(Self.palette, id: \.self) { swatch($0) }
        }
    }

    private func swatch(_ hex: String?) -> some View {
        let isSelected = selection == hex
        return Button {
            selection = hex
        } label: {
            ZStack {
                Circle()
                    .fill(Color(hex: hex) ?? Color(.systemGray5))
                    .frame(width: 32, height: 32)
                if hex == nil {
                    Image(systemName: "slash.circle")
                        .foregroundStyle(.secondary)
                }
                if isSelected {
                    Circle()
                        .strokeBorder(.tint, lineWidth: 3)
                        .frame(width: 40, height: 40)
                }
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hex == nil ? "No color" : "Color \(hex!)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
