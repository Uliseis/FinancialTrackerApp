import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

// Creates a shared-expense group from a primary debit + selected reimbursement credits.
struct SharedExpenseCreateView: View {
    let primaryTx: CoreModel.Transaction
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var search = ""
    @State private var selected: Set<UUID> = []
    @State private var candidates: [CoreLogic.SharedExpenses.CandidateReimbursement] = []
    @State private var errorMessage = ""
    @State private var showingError = false

    private var isValid: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !selected.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Label") {
                    TextField("e.g. Dinner split", text: $label)
                }
                Section("Reimbursements") {
                    if candidates.isEmpty {
                        Text("No matching credits near this expense.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(candidates, id: \.id) { candidate in
                        Button { toggle(candidate.id) } label: {
                            ReimbursementCandidateRow(candidate: candidate, selected: selected.contains(candidate.id))
                        }
                        .tint(.primary)
                    }
                }
            }
            .searchable(text: $search, prompt: "Filter credits")
            .navigationTitle("Match Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }.disabled(!isValid)
                }
            }
            .task { label = defaultLabel }
            .task(id: search) { reloadCandidates() }
            .alert("Couldn’t Create", isPresented: $showingError) {} message: {
                Text(errorMessage)
            }
        }
    }

    private var defaultLabel: String {
        primaryTx.transactionDescription ?? primaryTx.counterparty ?? ""
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func reloadCandidates() {
        candidates = (try? CoreLogic.SharedExpenses.findCandidateReimbursements(
            primaryTxId: primaryTx.id, query: search, in: ctx)) ?? []
    }

    private func create() {
        do {
            try CoreLogic.SharedExpenses.createGroup(
                .init(label: label, primaryTxId: primaryTx.id, reimbursementTxIds: Array(selected)),
                in: ctx)
            dismiss()
        } catch {
            errorMessage = SharedExpenseMessages.describe(error)
            showingError = true
        }
    }
}

enum SharedExpenseMessages {
    static func describe(_ error: Error) -> String {
        guard let e = error as? CoreLogic.SharedExpenses.Error else {
            return "Something went wrong."
        }
        switch e {
        case .labelRequired: return "Enter a label."
        case .noReimbursements: return "Pick at least one reimbursement."
        case .primaryIsAlsoReimbursement: return "The expense can’t also be a reimbursement."
        case .primaryMustBeDebit: return "The primary must be an expense (debit)."
        case .primaryIsTransfer: return "The primary is a transfer."
        case .primaryAlreadyInGroup: return "That expense is already matched."
        case .primaryHasNoEurAmount: return "The primary has no EUR amount yet."
        case .reimbursementNotCredit: return "A reimbursement must be a credit."
        case .reimbursementIsTransfer: return "A reimbursement is a transfer."
        case .reimbursementAlreadyInGroup: return "A reimbursement is already in a group."
        case .reimbursementOutsideWindow(_, let days): return "A reimbursement is outside the \(days)-day window."
        case .reimbursementHasNoEurAmount: return "A reimbursement has no EUR amount yet."
        case .crossSpace: return "All transactions must be in the same space."
        case .overcoverage(let reimbursed, let primary):
            return "Reimbursements (\(Money.format(reimbursed, currency: "EUR"))) exceed the expense (\(Money.format(primary, currency: "EUR")))."
        case .txNotFound: return "A transaction was not found."
        case .groupNotFound: return "Group not found."
        case .cannotRemovePrimary: return "A match needs at least one expense."
        case .startingTxNotCredit: return "Start from a credit transaction."
        case .noExpenses: return "Pick at least one expense."
        case .creditIsAlsoExpense: return "The income can’t also be one of the expenses."
        case .creditMustBeCredit: return "The starting transaction must be income."
        case .creditIsTransfer: return "The income is a transfer."
        case .creditAlreadyInGroup: return "The income is already matched."
        case .creditHasNoEurAmount: return "The income has no EUR amount yet."
        case .expenseNotDebit: return "Only expenses can go on the expense side."
        case .expenseIsTransfer: return "An expense is a transfer."
        case .expenseAlreadyInGroup: return "An expense is already matched."
        case .expenseOutsideWindow(_, let days): return "An expense is outside the \(days)-day window."
        case .expenseHasNoEurAmount: return "An expense has no EUR amount yet."
        case .undercoverage(let expenses, let credited):
            return "The expenses (\(Money.format(expenses, currency: "EUR"))) don’t cover the income (\(Money.format(credited, currency: "EUR")))."
        }
    }
}

#if DEBUG
#Preview {
    SharedExpenseCreateView(primaryTx: PreviewData.sampleTransaction)
        .modelContainer(PreviewData.container)
}
#endif
