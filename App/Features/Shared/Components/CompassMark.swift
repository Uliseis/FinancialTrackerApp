import SwiftUI

// The Odyssey brand mark: a 4-point compass star echoing the app icon.
// Decorative — callers should not rely on it for meaning.
struct CompassMark: View {
    var size: CGFloat = 30
    var tint: Color = Theme.heroAccent
    var ringOpacity: Double = 0.25

    var body: some View {
        ZStack {
            CompassStar()
                .fill(LinearGradient(colors: [tint, tint.opacity(0.45)],
                                     startPoint: .top, endPoint: .bottom))
            Circle()
                .strokeBorder(.white.opacity(ringOpacity), lineWidth: size / 30)
            Circle().fill(tint).frame(width: size * 0.2, height: size * 0.2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// Classic 4-point compass star (sharp N/E/S/W tips, recessed diagonals).
private struct CompassStar: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.30
        var path = Path()
        for i in 0..<8 {
            let angle = (Double(i) * 45.0 - 90.0) * .pi / 180.0
            let r = i.isMultiple(of: 2) ? outer : inner
            let pt = CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 24) {
        CompassMark()
        CompassMark(size: 64)
        CompassMark(size: 64, tint: .brand, ringOpacity: 0.1)
    }
    .padding()
    .background(Theme.heroFill)
}
#endif
