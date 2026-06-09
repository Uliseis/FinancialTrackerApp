import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

struct BalanceAnchorView: View {
    let account: Account
    @State private var amount: Decimal
    @State private var date: Date
    @State private var confirmingClear = false
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    init(account: Account) {
        self.account = account
        _amount = State(initialValue: account.balanceAnchor ?? account.balance ?? 0)
        _date = State(initialValue: account.balanceAnchorAt ?? .now)
    }

    private var hasAnchor: Bool { CoreLogic.Accounts.hasAnchor(account) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Amount (\(account.currency))") {
                        TextField("Amount", value: $amount, format: .number)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("As of", selection: $date)
                } footer: {
                    Text("The balance will show as this amount plus transactions after this date. Older transactions stay but stop affecting the balance.")
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
                    Button("Save") { save() }
                }
            }
            .confirmationDialog("Clear the balance anchor?", isPresented: $confirmingClear,
                                titleVisibility: .visible) {
                Button("Clear Anchor", role: .destructive) { clear() }
            } message: {
                Text("The balance reverts to opening balance plus all transactions.")
            }
        }
    }

    private func save() {
        try? CoreLogic.Accounts.setAnchor(account, balance: amount, at: date, in: ctx)
        dismiss()
    }

    private func clear() {
        try? CoreLogic.Accounts.clearAnchor(account, in: ctx)
        dismiss()
    }
}

#if DEBUG
#Preview {
    BalanceAnchorView(account: PreviewData.sampleAccount)
        .modelContainer(PreviewData.container)
}
#endif
