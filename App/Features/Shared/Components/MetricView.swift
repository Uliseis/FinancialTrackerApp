import SwiftUI

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
