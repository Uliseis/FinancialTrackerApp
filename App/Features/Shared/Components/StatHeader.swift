import SwiftUI

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
