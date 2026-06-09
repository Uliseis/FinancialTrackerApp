import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

struct SharedExpenseGroupDetailView: View {
    let group: SharedExpenseGroup
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    // Body renders only this cached state, never the model directly: deleteGroup()'s save
    // fires reloadOnModelChange before dismiss() lands, so the view must survive a render
    // cycle while `group` is already deleted.
    @State private var net: CoreLogic.SharedExpenses.GroupNet?
    @State private var members: [CoreModel.Transaction] = []
    @State private var title = ""
    @State private var primary: CoreModel.Transaction?
    @State private var adding = false
    @State private var renaming = false
    @State private var newLabel = ""
    @State private var confirmingDelete = false

    private var groupIsLive: Bool { group.modelContext != nil && !group.isDeleted }

    var body: some View {
        Form {
            Section("Summary") {
                LabeledContent("Expense", value: Money.format(net?.gross ?? 0, currency: "EUR"))
                LabeledContent("Reimbursed", value: Money.format(net?.reimbursed ?? 0, currency: "EUR"))
                LabeledContent("Net") { MoneyText(amount: net?.net ?? 0) }
                    .font(.headline)
            }

            if let primary {
                Section("Primary expense") {
                    MemberRow(tx: primary)
                }
            }

            Section("Reimbursements") {
                if members.isEmpty {
                    Text("No reimbursements.").foregroundStyle(.secondary)
                }
                ForEach(members) { tx in
                    MemberRow(tx: tx)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { remove(tx) } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                        }
                }
                Button {
                    adding = true
                } label: {
                    Label("Add Reimbursements", systemImage: "plus")
                }
            }

            Section {
                Button("Delete Shared Expense", role: .destructive) { confirmingDelete = true }
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Rename") { newLabel = title; renaming = true }
            }
        }
        .task { reload() }
        .reloadOnModelChange { reload() }
        .sheet(isPresented: $adding) {
            AddReimbursementsView(group: group)
        }
        .alert("Rename", isPresented: $renaming) {
            TextField("Label", text: $newLabel)
            Button("Cancel", role: .cancel) {}
            Button("Save") { rename() }
        }
        .confirmationDialog("Delete this shared expense?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteGroup() }
        } message: {
            Text("The transactions stay; only the grouping is removed.")
        }
    }

    private func reload() {
        guard groupIsLive else { return }
        title = group.label
        primary = group.primaryTx
        net = try? CoreLogic.SharedExpenses.netForGroup(group.id, in: ctx)
        members = group.members
            .filter { $0.id != group.primaryTx?.id }
            .sorted { $0.bookedAt > $1.bookedAt }
    }

    private func remove(_ tx: CoreModel.Transaction) {
        try? CoreLogic.SharedExpenses.removeReimbursement(groupId: group.id, txId: tx.id, in: ctx)
    }

    private func rename() {
        try? CoreLogic.SharedExpenses.renameGroup(group, label: newLabel, in: ctx)
    }

    private func deleteGroup() {
        try? CoreLogic.SharedExpenses.deleteGroup(group, in: ctx)
        dismiss()
    }
}

private struct MemberRow: View {
    let tx: CoreModel.Transaction

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.transactionDescription ?? tx.counterparty ?? "—").lineLimit(1)
                Text("\(tx.bookedAt.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits))) · \(tx.account?.name ?? "—")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let eur = tx.amountEur {
                MoneyText(amount: eur)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AddReimbursementsView: View {
    let group: SharedExpenseGroup
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selected: Set<UUID> = []
    @State private var candidates: [CoreLogic.SharedExpenses.CandidateReimbursement] = []
    @State private var errorMessage = ""
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            List {
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
            .searchable(text: $search, prompt: "Filter credits")
            .navigationTitle("Add Reimbursements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }.disabled(selected.isEmpty)
                }
            }
            .task(id: search) { reloadCandidates() }
            .alert("Couldn’t Add", isPresented: $showingError) {} message: {
                Text(errorMessage)
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func reloadCandidates() {
        guard let primaryId = group.primaryTx?.id else { return }
        candidates = (try? CoreLogic.SharedExpenses.findCandidateReimbursements(
            primaryTxId: primaryId, query: search, in: ctx)) ?? []
    }

    private func add() {
        do {
            try CoreLogic.SharedExpenses.addReimbursements(
                groupId: group.id, txIds: Array(selected), in: ctx)
            dismiss()
        } catch {
            errorMessage = SharedExpenseMessages.describe(error)
            showingError = true
        }
    }
}
