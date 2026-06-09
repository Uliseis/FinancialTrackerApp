import SwiftUI
import SwiftData
import CoreModel

// Picks the opposite leg for a manual transfer pair. Candidates are the opposite direction,
// same space, not already a transfer/mirror/shared-expense, sorted by amount closeness then
// recency. pairManual still validates on selection (e.g. the €0.01 tolerance).
struct TransferPartnerPickerView: View {
    let tx: CoreModel.Transaction
    let onSelect: (CoreModel.Transaction) -> Void

    @Query(sort: [SortDescriptor(\CoreModel.Transaction.bookedAt, order: .reverse)])
    private var allTx: [CoreModel.Transaction]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    // Cached: the filter+sort walks every transaction, so run it per input change
    // (task below), never per body render.
    @State private var candidates: [CoreModel.Transaction] = []

    private func rebuildCandidates() {
        let wantDirection: TxDirection = tx.direction == .debit ? .credit : .debit
        let spaceId = tx.account?.space?.id
        let target = tx.amountEur.map { abs($0) }
        candidates = allTx
            .filter { c in
                c.id != tx.id
                    && c.direction == wantDirection
                    && !c.isTransfer
                    && c.routedFromTx == nil
                    && c.sharedExpenseGroup == nil
                    && c.account?.space?.id == spaceId
                    && matchesSearch(c)
            }
            .sorted { lhs, rhs in
                guard let target else { return lhs.bookedAt > rhs.bookedAt }
                let l = abs((lhs.amountEur.map { abs($0) } ?? 0) - target)
                let r = abs((rhs.amountEur.map { abs($0) } ?? 0) - target)
                return l == r ? lhs.bookedAt > rhs.bookedAt : l < r
            }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(candidates) { candidate in
                    Button { choose(candidate) } label: {
                        PartnerRow(tx: candidate)
                    }
                    .tint(.primary)
                }
            }
            .searchable(text: $search, prompt: "Description or counterparty")
            .navigationTitle("Pair With")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if candidates.isEmpty {
                    ContentUnavailableView("No Candidates", systemImage: "arrow.left.arrow.right",
                                           description: Text("No opposite-direction transactions in this space."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: search) { rebuildCandidates() }
        }
    }

    private func matchesSearch(_ c: CoreModel.Transaction) -> Bool {
        guard !search.isEmpty else { return true }
        return (c.transactionDescription?.localizedStandardContains(search) ?? false)
            || (c.counterparty?.localizedStandardContains(search) ?? false)
    }

    private func choose(_ candidate: CoreModel.Transaction) {
        onSelect(candidate)
        dismiss()
    }
}

private struct PartnerRow: View {
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
            Text(tx.amountEur.map { Money.format($0, currency: "EUR") }
                 ?? Money.format(tx.amount, currency: tx.currency))
                .font(.body.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    TransferPartnerPickerView(tx: PreviewData.sampleTransaction) { _ in }
        .modelContainer(PreviewData.container)
}
#endif
