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

// Currency value, monospaced, optionally sign-colored.
struct MoneyText: View {
    let amount: Decimal
    var currency = "EUR"
    var signed = false
    var font: Font = .body

    var body: some View {
        Text(Money.format(amount, currency: currency))
            .font(font.monospacedDigit())
            .foregroundStyle(signed ? Theme.amountColor(amount) : Color.primary)
            .lineLimit(1)
    }
}

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

// Stacked label + value, used for compact metric pairs.
struct MetricView: View {
    let label: String
    let value: String
    var color: Color = .primary
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit()).foregroundStyle(color)
        }
    }
}

// Large KPI header: caption title over a prominent amount.
struct StatHeader: View {
    let title: String
    let amount: Decimal
    var currency = "EUR"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            MoneyText(amount: amount, currency: currency,
                      font: .largeTitle.weight(.semibold))
                .contentTransition(.numericText())
        }
    }
}

// Leading content + trailing value, with an optional progress bar beneath.
struct ProgressRow<Leading: View>: View {
    let value: String
    var fraction: Double?
    var tint: Color = .accentColor
    var valueColor: Color = .primary
    @ViewBuilder var leading: Leading

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                leading
                Spacer(minLength: 8)
                Text(value)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(valueColor)
            }
            if let fraction {
                ProgressView(value: fraction).tint(tint)
            }
        }
    }
}
