import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

// Records a move between two accounts the bank can't see. The case that needs it: one
// transfer arrives at a broker and is then split internally — money lands in MyInvestor and
// part of it goes to the pension wrapper, with only the arrival showing up as a bank row.
struct InternalTransferView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Account.name)]) private var allAccounts: [Account]
    @Query(sort: [SortDescriptor(\CoreModel.Category.name)]) private var categories: [CoreModel.Category]
    @AppStorage(SpaceSelection.key) private var currentSpaceId = ""

    @State private var sourceId: UUID?
    @State private var targetId: UUID?
    @State private var amountText = ""
    @State private var note = ""
    @State private var bookedAt = Date.now
    @State private var categoryId: UUID?
    @State private var saveError: String?

    private var accounts: [Account] {
        allAccounts.filter { !$0.archived }
    }
    private var source: Account? { accounts.first { $0.id == sourceId } }
    private var target: Account? { accounts.first { $0.id == targetId } }
    private var amount: Decimal? { CoreLogic.Transactions.parseAmount(amountText) }

    // Cross-space moves are rejected by the transfer invariants, so don't offer them.
    private var targetChoices: [Account] {
        guard let source else { return accounts }
        return accounts.filter { $0.id != source.id && $0.space?.id == source.space?.id }
    }

    private var isValid: Bool {
        source != nil && target != nil && amount != nil && source?.id != target?.id
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("From", selection: $sourceId) {
                        Text("Choose").tag(UUID?.none)
                        ForEach(accounts) { Text($0.displayName).tag(UUID?.some($0.id)) }
                    }
                    Picker("To", selection: $targetId) {
                        Text("Choose").tag(UUID?.none)
                        ForEach(targetChoices) { Text($0.displayName).tag(UUID?.some($0.id)) }
                    }
                    LabeledContent("Amount") {
                        TextField("0", text: $amountText)
                            .multilineTextAlignment(.trailing)
                            .font(.readout(.title3))
                            .keyboardType(.decimalPad)
                    }
                    DatePicker("Date", selection: $bookedAt, displayedComponents: .date)
                } footer: {
                    Text("Books both halves at once and pairs them, so what leaves one account is exactly what arrives in the other.")
                }

                Section {
                    TextField("Note (optional)", text: $note)
                    Picker("Category", selection: $categoryId) {
                        Text("None").tag(UUID?.none)
                        ForEach(categories) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                } footer: {
                    Text("Leave the category off for a plain move of capital. Choose an income category when this is rent, a dividend or a coupon — that keeps it out of cost basis and counts it as return.")
                }
            }
            .navigationTitle("Move Money")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
            .saveErrorAlert($saveError)
        }
    }

    private func save() {
        guard let source, let target, let amount else { return }
        do {
            try CoreLogic.Transfers.createInternalTransfer(
                from: source, to: target, amountEur: amount, bookedAt: bookedAt,
                note: note, category: categories.first { $0.id == categoryId }, in: ctx)
            dismiss()
        } catch CoreLogic.Transfers.PairError.differentSpace {
            saveError = "Those two accounts are in different spaces."
        } catch {
            saveError = "The transfer wasn’t saved."
        }
    }
}

#if DEBUG
#Preview {
    InternalTransferView().modelContainer(PreviewData.container)
}
#endif
