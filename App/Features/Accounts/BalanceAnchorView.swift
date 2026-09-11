import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

struct BalanceAnchorView: View {
    let account: Account
    // Text + parseAmount: a locale-bound numeric field reads "196.03" as 19603 under es-ES.
    @State private var amountText: String
    @State private var date: Date
    @State private var confirmingClear = false
    @State private var saveError: String?
    @State private var shownNow: Decimal?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    init(account: Account) {
        self.account = account
        _amountText = State(initialValue: Money.plainAmountText(account.balanceAnchor ?? account.balance ?? 0))
        _date = State(initialValue: account.balanceAnchorAt ?? .now)
    }

    private var hasAnchor: Bool { CoreLogic.Accounts.hasAnchor(account) }
    private var amount: Decimal? { CoreLogic.Transactions.parseAmount(amountText) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Amount (\(account.currency))") {
                        TextField("Amount", text: $amountText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("As of", selection: $date)
                } footer: {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        if let shownNow, let amount {
                            Text("The app currently shows \(Money.format(shownNow, currency: account.currency)); the difference is \(Money.format(amount - shownNow, currency: account.currency)).")
                        }
                        Text("The balance will show as this amount plus transactions after this date. Older transactions stay but stop affecting the balance.")
                    }
                }
                if hasAnchor {
                    Section {
                        Button("Clear Anchor", role: .destructive) { confirmingClear = true }
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Set Current Balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(amount == nil)
                }
            }
            .confirmationDialog("Clear the balance anchor?", isPresented: $confirmingClear,
                                titleVisibility: .visible) {
                Button("Clear Anchor", role: .destructive) { clear() }
            } message: {
                Text("The balance reverts to opening balance plus all transactions.")
            }
            .saveErrorAlert($saveError)
            .task { shownNow = CoreLogic.Accounts.computeNativeBalances([account], in: ctx)[account.id] }
        }
    }

    private func save() {
        guard let amount else { return }
        do {
            try CoreLogic.Accounts.setAnchor(account, balance: amount, at: date, in: ctx)
            dismiss()
        } catch {
            saveError = "The anchor wasn’t saved."
        }
    }

    private func clear() {
        do {
            try CoreLogic.Accounts.clearAnchor(account, in: ctx)
            dismiss()
        } catch {
            saveError = "The anchor wasn’t cleared."
        }
    }
}

#if DEBUG
#Preview {
    BalanceAnchorView(account: PreviewData.sampleAccount)
        .modelContainer(PreviewData.container)
}
#endif
