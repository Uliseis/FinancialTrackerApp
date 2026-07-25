import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

// Create or edit a transaction. Bank-sourced rows are editable too — EBSync skips
// (accountId, externalId) pairs it already holds, so an edit survives the next sync.
struct TransactionFormView: View {
    @State private var edit: TransactionEdit
    @Query(sort: [SortDescriptor(\Account.name)]) private var accounts: [Account]
    @Query(sort: [SortDescriptor(\CoreModel.Category.name)])
    private var categories: [CoreModel.Category]
    @AppStorage(SpaceSelection.key) private var currentSpaceId = ""
    @Query(sort: [SortDescriptor(\AccountSpace.sortOrder),
                  SortDescriptor(\AccountSpace.createdAt)])
    private var spaces: [AccountSpace]
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var saveError: String?

    init(edit: TransactionEdit) { _edit = State(initialValue: edit) }

    private var selectableAccounts: [Account] {
        let scope = SpaceScope.resolve(rawCurrentId: currentSpaceId, spaces: spaces)
        return accounts.filter { !$0.archived && scope.includes($0) }
    }

    private var currency: String {
        selectableAccounts.first { $0.id == edit.accountId }?.currency ?? "EUR"
    }

    private var amount: Decimal? { CoreLogic.Transactions.parseAmount(edit.amountText) }
    private var isValid: Bool { edit.accountId != nil && amount != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $edit.direction) {
                        Text("Expense").tag(TxDirection.debit)
                        Text("Income").tag(TxDirection.credit)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section("Amount") {
                    LabeledContent(currency) {
                        // Free text + a lenient parse: a locale-bound numeric field reads
                        // "42.50" as 42500 in es-ES.
                        TextField("0", text: $edit.amountText)
                            .multilineTextAlignment(.trailing)
                            .font(.title3.monospacedDigit())
                            .fontDesign(.rounded)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Details") {
                    LabeledContent("Description") {
                        TextField("What was it?", text: $edit.description)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Counterparty") {
                        TextField("Who?", text: $edit.counterparty)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("Date", selection: $edit.bookedAt, displayedComponents: .date)
                }

                Section {
                    Picker("Account", selection: $edit.accountId) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(selectableAccounts) {
                            Text($0.displayName).tag(UUID?.some($0.id))
                        }
                    }
                    Picker("Category", selection: $edit.categoryId) {
                        Text("Uncategorized").tag(UUID?.none)
                        ForEach(categories) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }

                if edit.existing != nil {
                    Section {
                        Button("Delete Transaction", role: .destructive) {
                            edit.confirmingDelete = true
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    } footer: {
                        if edit.blocksDelete {
                            Text("This is part of a transfer. Remove the transfer first.")
                        }
                    }
                }
            }
            .navigationTitle(edit.existing == nil ? "New Transaction" : "Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
            .confirmationDialog("Delete this transaction?",
                                isPresented: $edit.confirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteTx() }
            } message: {
                Text("This can’t be undone.")
            }
            .task { if edit.accountId == nil { edit.accountId = selectableAccounts.first?.id } }
            .saveErrorAlert($saveError)
        }
    }

    private func save() {
        guard let account = selectableAccounts.first(where: { $0.id == edit.accountId }),
              let amount else { return }
        let category = categories.first { $0.id == edit.categoryId }
        do {
            if let existing = edit.existing {
                try CoreLogic.Transactions.update(
                    existing, amount: amount, direction: edit.direction,
                    bookedAt: edit.bookedAt, description: edit.description,
                    counterparty: edit.counterparty, category: category, in: ctx)
            } else {
                try CoreLogic.Transactions.createManual(
                    account: account, amount: amount, direction: edit.direction,
                    bookedAt: edit.bookedAt, description: edit.description,
                    counterparty: edit.counterparty, category: category, in: ctx)
            }
            dismiss()
        } catch {
            saveError = "The transaction wasn’t saved. Check the amount and try again."
        }
    }

    private func deleteTx() {
        guard let existing = edit.existing else { return }
        do {
            try CoreLogic.Transactions.delete(existing, in: ctx)
            dismiss()
        } catch CoreLogic.Transactions.MutationError.isMirrorLeg {
            saveError = "This is the mirrored half of a transfer. Remove the transfer instead."
        } catch CoreLogic.Transactions.MutationError.isPairedTransfer {
            saveError = "This is paired as a transfer. Remove the transfer first, then delete."
        } catch {
            saveError = "The transaction wasn’t deleted."
        }
    }
}

// Identifiable form payload: nil existing ⇒ create, non-nil ⇒ edit.
struct TransactionEdit: Identifiable {
    let id: UUID
    let existing: CoreModel.Transaction?
    var direction: TxDirection
    var amountText: String
    var description: String
    var counterparty: String
    var bookedAt: Date
    var accountId: UUID?
    var categoryId: UUID?
    var confirmingDelete = false

    var blocksDelete: Bool {
        guard let existing else { return false }
        return existing.routedFromTx != nil || existing.transferGroup != nil
    }

    init(accountId: UUID? = nil) {
        id = UUID()
        existing = nil
        direction = .debit
        amountText = ""
        description = ""
        counterparty = ""
        bookedAt = .now
        self.accountId = accountId
        categoryId = nil
    }

    init(_ tx: CoreModel.Transaction) {
        id = tx.id
        existing = tx
        direction = tx.direction
        amountText = Money.plainAmountText(abs(tx.amount))
        description = tx.transactionDescription ?? ""
        counterparty = tx.counterparty ?? ""
        bookedAt = tx.bookedAt
        accountId = tx.account?.id
        categoryId = tx.category?.id
    }
}

#if DEBUG
#Preview {
    TransactionFormView(edit: TransactionEdit())
        .modelContainer(PreviewData.container)
}
#endif
