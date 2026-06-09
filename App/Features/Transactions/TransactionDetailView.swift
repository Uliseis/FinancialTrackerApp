import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

struct TransactionDetailView: View {
    let tx: CoreModel.Transaction
    @Environment(\.modelContext) private var ctx
    @State private var picking = false

    var body: some View {
        Form {
            Section("Amount") {
                row("Amount", Money.format(tx.amount, currency: tx.currency))
                if let eur = tx.amountEur {
                    row("EUR", Money.format(eur, currency: "EUR"))
                }
                if let fx = tx.fxRateUsed {
                    row("FX rate", fx.formatted(.number.precision(.fractionLength(0...6))))
                }
                row("Direction", tx.direction.rawValue.capitalized)
            }

            Section("When & where") {
                row("Booked", tx.bookedAt.formatted(date: .abbreviated, time: .omitted))
                if let valueAt = tx.valueAt {
                    row("Value", valueAt.formatted(date: .abbreviated, time: .omitted))
                }
                if let account = tx.account {
                    row("Account", account.name)
                    row("Institution", account.institution)
                }
            }

            Section("Classification") {
                Button { picking = true } label: {
                    LabeledContent("Category") {
                        HStack(spacing: 8) {
                            Text(tx.category?.name ?? "Uncategorized")
                                .foregroundStyle(tx.category == nil ? .secondary : .primary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .tint(.primary)
                row("Source", tx.categorySource.rawValue.capitalized)
                if let cp = tx.counterparty, !cp.isEmpty {
                    row("Counterparty", cp)
                }
                if let d = tx.transactionDescription, !d.isEmpty {
                    row("Description", d)
                }
            }

            if tx.isTransfer || tx.transferGroup != nil || tx.route != nil
                || tx.routedFromTx != nil || !tx.mirrors.isEmpty {
                Section("Transfer") {
                    row("Marked transfer", tx.isTransfer ? "Yes" : "No")
                    if let paired = tx.transferGroup?.pairedAt {
                        row("Paired", paired.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let route = tx.route {
                        row("Route", route.pattern)
                    }
                    if let from = tx.routedFromTx {
                        row("Routed from", from.account?.name ?? "—")
                    }
                    if !tx.mirrors.isEmpty {
                        row("Mirror legs", "\(tx.mirrors.count)")
                    }
                }
            }

            if let seg = tx.sharedExpenseGroup {
                Section("Shared expense") {
                    row("Group", seg.label)
                    row("Attribution", seg.attributionMonth.formatted(.dateTime.month(.wide).year()))
                }
            }

            Section("Metadata") {
                row("External ID", tx.externalId)
                row("Created", tx.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .navigationTitle(tx.amountEur.map { Money.format($0, currency: "EUR") } ?? "Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $picking) {
            CategoryPickerView(selectedId: tx.category?.id) { category in
                try? CoreLogic.Categories.recategorize(tx, to: category, in: ctx)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        TransactionDetailView(tx: PreviewData.sampleTransaction)
    }
}
#endif
