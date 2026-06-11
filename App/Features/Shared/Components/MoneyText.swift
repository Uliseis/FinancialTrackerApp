import SwiftUI

// Currency value rendered as a rounded tabular "readout", optionally sign-colored.
struct MoneyText: View {
    let amount: Decimal
    var currency = "EUR"
    var signed = false
    var font: Font = .body

    var body: some View {
        Text(Money.format(amount, currency: currency))
            .font(font.monospacedDigit())
            .fontDesign(.rounded)
            .foregroundStyle(signed ? Theme.amountColor(amount) : Color.primary)
            .lineLimit(1)
    }
}
