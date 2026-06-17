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
    @State private var filteredTotalEur: Decimal = 0
    // The full filtered set can be thousands of rows; render it a page at a time and grow
    // the window as the user scrolls (see the footer's onAppear). `rows` stays complete so
    // the running total and counts still reflect every match.
    @State private var visibleLimit = pageSize
    private static let pageSize = 100
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
        // Net EUR of the current matches — shown only while searching (see body).
        filteredTotalEur = rows.reduce(Decimal(0)) { $0 + ($1.amountEur ?? 0) }
        // Filter inputs changed → scroll back to the first page.
        visibleLimit = Self.pageSize
    }

    private func matches(_ tx: CoreModel.Transaction) -> Bool {
        guard !search.isEmpty else { return true }
        return (tx.transactionDescription?.localizedStandardContains(search) ?? false)
            || (tx.counterparty?.localizedStandardContains(search) ?? false)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(rows.prefix(visibleLimit)) { tx in
                    NavigationLink(value: tx) {
                        TransactionRow(tx: tx)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            categorizing = tx
                        } label: {
                            Label("Categorize", systemImage: "tag")
                        }
                        .tint(.brand)
                    }
                }
                if visibleLimit < rows.count {
                    HStack {
                        Spacer()
                        ProgressView()
                        Text("\(visibleLimit) of \(rows.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .onAppear {
                        visibleLimit = min(visibleLimit + Self.pageSize, rows.count)
                    }
                }
            }
            .navigationDestination(for: CoreModel.Transaction.self) { TransactionDetailView(tx: $0) }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .safeAreaInset(edge: .bottom) {
                if !search.isEmpty && !rows.isEmpty {
                    RunningTotalPill(count: rows.count, total: filteredTotalEur)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: search.isEmpty)
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
            #if DEBUG
            if let q = UITestHooks.search, !q.isEmpty { search = q }
            #endif
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
        HStack(spacing: Theme.Space.m) {
            ColorDot(hex: tx.category?.color, size: 9)
            VStack(alignment: .leading, spacing: 3) {
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
            Spacer(minLength: Theme.Space.s)
            Text(amount)
                .font(.callout.monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    // Income carries an explicit "+" so the credit/debit distinction survives
    // without relying on color (debits already carry "-").
    private var amount: String {
        let value = tx.amountEur ?? tx.amount
        let currency = tx.amountEur != nil ? "EUR" : tx.currency
        let base = Money.format(value, currency: currency)
        return value > 0 ? "+\(base)" : base
    }

    private var color: Color {
        let value = tx.amountEur ?? tx.amount
        if value > 0 { return .positiveAmount }
        if value < 0 { return .primary }
        return .secondary
    }
}

// Floating glass pill summarising the current search: match count + net EUR.
// The one legitimate manual-glass surface — floating content over the list.
private struct RunningTotalPill: View {
    let count: Int
    let total: Decimal

    private var totalString: String {
        let base = Money.format(total, currency: "EUR")
        return total > 0 ? "+\(base)" : base
    }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Text("^[\(count) match](inflect: true)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: Theme.Space.s)
            Text(totalString)
                .font(.headline.monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(Theme.amountColor(total))
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s + 2)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, Theme.Space.m)
        .padding(.bottom, Theme.Space.s)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("^[\(count) match](inflect: true), net \(Money.format(total, currency: "EUR"))")
    }
}

#if DEBUG
#Preview {
    TransactionsView()
        .modelContainer(PreviewData.container)
}
#endif
