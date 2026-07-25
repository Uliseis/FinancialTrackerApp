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
    @State private var showExcluded = false
    @State private var rows: [CoreModel.Transaction] = []
    @State private var filteredTotalEur: Decimal = 0
    // The full filtered set can be thousands of rows; render it a page at a time and grow
    // the window as the user scrolls (see the footer's onAppear). `rows` stays complete so
    // the running total and counts still reflect every match.
    @State private var visibleLimit = pageSize
    private static let pageSize = 100
    @State private var categorizing: CoreModel.Transaction?
    @State private var adding: TransactionEdit?
    // nil = no filter; .some(nil) = uncategorized only.
    @State private var categoryFilter: UUID??
    @Query(sort: [SortDescriptor(\CoreModel.Category.name)])
    private var categories: [CoreModel.Category]
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
            if !showExcluded && (tx.account?.excluded ?? false) { return false }
            if !showTransfers && tx.isTransfer { return false }
            if let wanted = categoryFilter, tx.category?.id != wanted { return false }
            return matches(tx)
        }
        // Net EUR of the current matches — shown only while searching (see body).
        filteredTotalEur = rows.reduce(Decimal(0)) { $0 + ($1.amountEur ?? 0) }
        // Filter inputs changed → scroll back to the first page.
        visibleLimit = Self.pageSize
    }

    private var categoryFilterMenu: some View {
        Menu {
            Button {
                categoryFilter = nil
            } label: {
                Label("All Categories", systemImage: categoryFilter == nil ? "checkmark" : "")
            }
            Button {
                categoryFilter = .some(nil)
            } label: {
                Label("Uncategorized",
                      systemImage: categoryFilter == .some(nil) ? "checkmark" : "")
            }
            Divider()
            ForEach(categories) { cat in
                Button {
                    categoryFilter = .some(cat.id)
                } label: {
                    Label(cat.name, systemImage: categoryFilter == .some(cat.id) ? "checkmark" : "")
                }
            }
        } label: {
            Label("Filter", systemImage: categoryFilter == nil
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
    }

    // Month buckets over the currently-paged window, newest first. Each header carries the
    // month's net so the list reads as a statement rather than an undifferentiated feed.
    struct MonthSection: Identifiable {
        let id: Date
        let title: String
        let net: Decimal
        let rows: [CoreModel.Transaction]
    }

    private var monthSections: [MonthSection] {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        var order: [Date] = []
        var buckets: [Date: [CoreModel.Transaction]] = [:]
        for tx in rows.prefix(visibleLimit) {
            let key = cal.date(from: cal.dateComponents([.year, .month], from: tx.bookedAt))
                ?? tx.bookedAt
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(tx)
        }
        return order.map { key in
            let rows = buckets[key] ?? []
            return MonthSection(
                id: key,
                title: key.formatted(.dateTime.month(.wide).year()),
                net: rows.reduce(Decimal(0)) { $0 + ($1.amountEur ?? 0) },
                rows: rows)
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
                ForEach(monthSections) { month in
                    Section {
                        ForEach(month.rows) { tx in
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
                    } header: {
                        MonthHeader(title: month.title, net: month.net)
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
                    Button { adding = TransactionEdit() } label: {
                        Label("New Transaction", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $showExcluded) {
                        Label("Excluded", systemImage: "eye.slash")
                    }
                    .toggleStyle(.button)
                    .sensoryFeedback(.selection, trigger: showExcluded)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $showTransfers) {
                        Label("Transfers", systemImage: "arrow.left.arrow.right")
                    }
                    .toggleStyle(.button)
                    .sensoryFeedback(.selection, trigger: showTransfers)
                }
                ToolbarItem(placement: .topBarTrailing) { categoryFilterMenu }
            }
            .sheet(item: $adding) { TransactionFormView(edit: $0) }
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
        .onChange(of: categoryFilter) { recompute() }
        .onChange(of: search) { recompute() }
        .onChange(of: showTransfers) { recompute() }
        .onChange(of: showExcluded) { recompute() }
        .onChange(of: currentSpaceId) { recompute() }
        .reloadOnModelChange { recompute() }
    }
}

// Serif month heading with the month's net — the one editorial moment on this screen.
private struct MonthHeader: View {
    let title: String
    let net: Decimal

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.display(.title3, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: Theme.Space.s)
            Text(Money.format(net, currency: "EUR"))
                .font(.readout(.subheadline, weight: .medium))
                .foregroundStyle(Theme.amountColor(net))
        }
        .textCase(nil)
        .padding(.top, Theme.Space.s)
        .accessibilityElement(children: .combine)
    }
}

struct TransactionRow: View {
    let tx: CoreModel.Transaction
    // Off inside an account's own list, where every row would repeat the same name.
    var showsAccount = true

    private var title: String {
        let d = tx.transactionDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d, !d.isEmpty { return d }
        let c = tx.counterparty?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let c, !c.isEmpty { return c }
        return "—"
    }

    // Category is carried by the badge; repeating its name here only crowded out the
    // account, which is the part you can't infer from the glyph.
    private var subtitle: String {
        showsAccount ? (tx.account?.displayName ?? "") : ""
    }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            CategoryBadge(category: tx.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(tx.bookedAt, format: .dateTime.day().month(.abbreviated))
                    if !subtitle.isEmpty {
                        Text("· \(subtitle)").lineLimit(1)
                    }
                    if tx.isTransfer {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    if tx.sharedExpenseGroup != nil {
                        Image(systemName: "link")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Space.s)
            Text(amount)
                .font(.readout(.body))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
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
