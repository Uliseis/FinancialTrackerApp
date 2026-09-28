import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

// Picks the opposite leg for a manual transfer pair. Candidates are exactly the legs
// pairManual would accept (opposite direction, same space, amounts within €0.01, …) and not
// already a transfer, newest first. Near-misses used to be listed and failed on tap.
struct TransferPartnerPickerView: View {
    let tx: CoreModel.Transaction
    let onSelect: (CoreModel.Transaction) -> Void

    @Query(sort: [SortDescriptor(\CoreModel.Transaction.bookedAt, order: .reverse)])
    private var allTx: [CoreModel.Transaction]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    // Cached: the filter walks every transaction, so run it per input change
    // (task below), never per body render.
    @State private var candidates: [CoreModel.Transaction] = []

    private func rebuildCandidates() {
        let wantDirection: TxDirection = tx.direction == .debit ? .credit : .debit
        candidates = allTx.filter { c in
            c.direction == wantDirection
                && !c.isTransfer
                && matchesSearch(c)
                && CoreLogic.Transfers.canPairManual(tx, c)
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
                                           description: Text("Nothing in this space moves the same amount the other way."))
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
                Text("\(tx.bookedAt.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits))) · \(tx.account?.displayName ?? "—")")
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
