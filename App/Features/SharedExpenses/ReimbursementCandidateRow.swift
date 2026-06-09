import SwiftUI
import CoreLogic

// A selectable reimbursement candidate (a credit that could offset a primary expense).
struct ReimbursementCandidateRow: View {
    let candidate: CoreLogic.SharedExpenses.CandidateReimbursement
    let selected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.description ?? candidate.counterparty ?? "—").lineLimit(1)
                Text(candidate.bookedAt.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let eur = candidate.amountEur {
                MoneyText(amount: eur)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
