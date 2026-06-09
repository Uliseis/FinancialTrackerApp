import SwiftUI

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
