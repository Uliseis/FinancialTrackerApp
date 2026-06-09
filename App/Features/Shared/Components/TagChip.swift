import SwiftUI

// Small capsule label. Neutral by default; pass a tint for a status accent.
struct TagChip: View {
    let text: String
    var tint: Color?

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tint ?? Color.secondary)
            .background(tint.map { AnyShapeStyle($0.opacity(0.18)) } ?? AnyShapeStyle(.quaternary),
                        in: Capsule())
    }
}
