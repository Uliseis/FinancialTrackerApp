import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

struct AddInterestView: View {
    let account: Account
    @State private var amount: Decimal = 0
    @State private var date: Date = .now
    @State private var note: String = ""
    @State private var saveError: String?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Amount (\(account.currency))") {
                        TextField("Amount", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                } footer: {
                    Text("Adds an interest credit to \(account.name).")
                }
            }
            .navigationTitle("Add Interest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }.disabled(amount <= 0)
                }
            }
            .saveErrorAlert($saveError)
        }
    }

    private func save() {
        do {
            try CoreLogic.Accounts.addInterest(
                account, amount: amount, at: date,
                note: note.isEmpty ? nil : note, in: ctx)
            dismiss()
        } catch {
            saveError = "The interest wasn’t added. Check the amount and try again."
        }
    }
}

#if DEBUG
#Preview {
    AddInterestView(account: PreviewData.sampleAccount)
        .modelContainer(PreviewData.container)
}
#endif
