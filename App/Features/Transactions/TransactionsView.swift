import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

struct TransactionsView: View {
    @Query(sort: [SortDescriptor(\CoreModel.Transaction.bookedAt, order: .reverse),
                  SortDescriptor(\CoreModel.Transaction.createdAt, order: .reverse)])
    private var allTx: [CoreModel.Transaction]

    @Query(sort: [SortDescriptor(\AccountSpace.sortOrder),
                  SortDescriptor(\AccountSpace.createdAt)])
    private var spaces: [AccountSpace]

    @AppStorage(SpaceSelection.key) private var currentSpaceId = ""
    @Environment(\.modelContext) private var ctx
    @State private var search = ""
    @State private var showTransfers = false
    @State private var rows: [CoreModel.Transaction] = []
    @State private var categorizing: CoreModel.Transaction?
    @State private var path: [CoreModel.Transaction] = []
    #if DEBUG
    @State private var debugPartnerTx: CoreModel.Transaction?
    @State private var debugSharedTx: CoreModel.Transaction?
    #endif

    // Web parity: current space only, hide mirror legs (routedFromTx != nil) and
    // transfers (unless toggled). Cached in @State so filtering runs only when an
    // input or the store changes — not on every body render.
    private func recompute() {
        let scope = SpaceScope.resolve(rawCurrentId: currentSpaceId, spaces: spaces)
        rows = allTx.filter { tx in
            guard scope.includes(tx.account) else { return false }
            guard tx.routedFromTx == nil else { return false }
            if !showTransfers && tx.isTransfer { return false }
            return matches(tx)
        }
    }

    private func matches(_ tx: CoreModel.Transaction) -> Bool {
        guard !search.isEmpty else { return true }
        return (tx.transactionDescription?.localizedStandardContains(search) ?? false)
            || (tx.counterparty?.localizedStandardContains(search) ?? false)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(rows) { tx in
                    NavigationLink(value: tx) {
                        TransactionRow(tx: tx)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            categorizing = tx
                        } label: {
                            Label("Categorize", systemImage: "tag")
                        }
                        .tint(.indigo)
                    }
                }
            }
            .navigationDestination(for: CoreModel.Transaction.self) { TransactionDetailView(tx: $0) }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .navigationTitle("Transactions")
            .searchable(text: $search, prompt: "Description or counterparty")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SpacePicker() }
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $showTransfers) {
                        Label("Transfers", systemImage: "arrow.left.arrow.right")
                    }
                    .toggleStyle(.button)
                    .sensoryFeedback(.selection, trigger: showTransfers)
                }
            }
            .sheet(item: $categorizing) { tx in
                CategoryPickerView(selectedId: tx.category?.id) { category in
                    try? CoreLogic.Categories.recategorize(tx, to: category, in: ctx)
                }
            }
            #if DEBUG
            .sheet(item: $debugPartnerTx) { tx in
                TransferPartnerPickerView(tx: tx) { _ in }
            }
            .sheet(item: $debugSharedTx) { tx in
                SharedExpenseCreateView(primaryTx: tx)
            }
            #endif
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView(
                        search.isEmpty ? "No Transactions" : "No Matches",
                        systemImage: "list.bullet.rectangle"
                    )
                }
            }
        }
        .task {
            recompute()
            #if DEBUG
            switch UITestHooks.presentSheet {
            case "categorize": categorizing = rows.first
            case "tx-detail":
                if let t = rows.first(where: { !$0.isTransfer && $0.routedFromTx == nil }) { path = [t] }
            case "tx-detail-transfer":
                if let t = allTx.first(where: { $0.isTransfer && $0.routedFromTx == nil }) { path = [t] }
            case "pair-partner":
                debugPartnerTx = rows.first(where: { !$0.isTransfer && $0.routedFromTx == nil })
            case "shared-create":
                debugSharedTx = allTx.first(where: {
                    $0.direction == .debit && !$0.isTransfer && $0.routedFromTx == nil
                        && $0.sharedExpenseGroup == nil && $0.amountEur != nil
                })
            default: break
            }
            #endif
        }
        .onChange(of: search) { recompute() }
        .onChange(of: showTransfers) { recompute() }
        .onChange(of: currentSpaceId) { recompute() }
        .reloadOnModelChange { recompute() }
    }
}

private struct TransactionRow: View {
    let tx: CoreModel.Transaction

    private var title: String {
        let d = tx.transactionDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d, !d.isEmpty { return d }
        let c = tx.counterparty?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let c, !c.isEmpty { return c }
        return "—"
    }

    private var subtitle: String {
        [tx.account?.name, tx.category?.name].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(tx.bookedAt, format: .dateTime.day().month(.abbreviated).year(.twoDigits))
                    if !subtitle.isEmpty {
                        Text("· \(subtitle)").lineLimit(1)
                    }
                    if tx.isTransfer {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    if tx.sharedExpenseGroup != nil {
                        Image(systemName: "person.2")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(amount)
                .font(.body.monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var amount: String {
        if let eur = tx.amountEur { return Money.format(eur, currency: "EUR") }
        return Money.format(tx.amount, currency: tx.currency)
    }

    private var color: Color {
        let value = tx.amountEur ?? tx.amount
        if value > 0 { return .positiveAmount }
        if value < 0 { return .primary }
        return .secondary
    }
}

#if DEBUG
#Preview {
    TransactionsView()
        .modelContainer(PreviewData.container)
}
#endif
