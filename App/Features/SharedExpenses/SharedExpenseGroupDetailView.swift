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
    @State private var expenses: [CoreModel.Transaction] = []
    @State private var incoming: [CoreModel.Transaction] = []
    @State private var title = ""
    @State private var adding = false
    @State private var renaming = false
    @State private var newLabel = ""
    @State private var confirmingDelete = false

    private var groupIsLive: Bool { group.modelContext != nil && !group.isDeleted }

    var body: some View {
        Form {
            Section {
                InstrumentPanel {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        PanelLabel(text: "Net still spent")
                        Text(Money.format(net?.net ?? 0, currency: "EUR"))
                            .font(.readout(.largeTitle, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        HStack(spacing: Theme.Space.l) {
                            panelStat("Expenses", net?.gross ?? 0)
                            panelStat("Covered by", net?.reimbursed ?? 0)
                        }
                    }
                }
                .instrumentPanelRow()
            }

            // Split by direction, not by is-it-the-primary: a match can hold several
            // expenses on one side and several incoming payments on the other.
            Section("Expenses") {
                ForEach(expenses) { tx in
                    MemberRow(tx: tx)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { remove(tx) } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                        }
                }
            }

            Section("Incoming money") {
                if incoming.isEmpty {
                    Text("Nothing offsetting these yet.").foregroundStyle(.secondary)
                }
                ForEach(incoming) { tx in
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
                    Label("Add Incoming Money", systemImage: "plus")
                }
            }

            Section {
                Button("Delete Match", role: .destructive) { confirmingDelete = true }
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
        .confirmationDialog("Delete this match?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteGroup() }
        } message: {
            Text("The transactions stay; only the grouping is removed.")
        }
    }

    private func panelStat(_ label: String, _ value: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            PanelLabel(text: label)
            Text(Money.format(value, currency: "EUR"))
                .font(.readout(.subheadline, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private func reload() {
        guard groupIsLive else { return }
        title = group.label
        net = try? CoreLogic.SharedExpenses.netForGroup(group.id, in: ctx)
        let sorted = group.members.sorted { $0.bookedAt > $1.bookedAt }
        expenses = sorted.filter { $0.direction == .debit }
        incoming = sorted.filter { $0.direction == .credit }
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
                Text("\(tx.bookedAt.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits))) · \(tx.account?.displayName ?? "—")")
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
                    Text("No matching income near these expenses.")
                        .foregroundStyle(.secondary)
                }
                ForEach(candidates, id: \.id) { candidate in
                    Button { toggle(candidate.id) } label: {
                        ReimbursementCandidateRow(candidate: candidate, selected: selected.contains(candidate.id))
                    }
                    .tint(.primary)
                }
            }
            .searchable(text: $search, prompt: "Search income")
            .navigationTitle("Add Incoming Money")
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
