import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

struct TransactionsView: View {
    @Query(sort: [SortDescriptor(\AccountSpace.sortOrder),
                  SortDescriptor(\AccountSpace.createdAt)])
    private var spaces: [AccountSpace]
    @Query private var accounts: [Account]
    @Query(sort: [SortDescriptor(\CoreModel.Category.name)])
    private var categories: [CoreModel.Category]

    @AppStorage(SpaceSelection.key) private var currentSpaceId = ""
    @Environment(\.modelContext) private var ctx
    @State private var search = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var showTransfers = false
    @State private var showExcluded = false
    // nil = no filter; .some(nil) = uncategorized only.
    @State private var categoryFilter: UUID??

    // Only the loaded pages live here; the store does the filtering, sorting and totals.
    @State private var rows: [CoreModel.Transaction] = []
    @State private var sections: [MonthSection] = []
    @State private var matchCount = 0
    @State private var searchTotalEur: Decimal = 0
    // Per-month net over every match, filled in as a month first appears.
    @State private var monthNets: [Date: Decimal] = [:]
    private static let pageSize = 100

    @State private var categorizing: CoreModel.Transaction?
    @State private var adding: TransactionEdit?
    @State private var path: [CoreModel.Transaction] = []
    #if DEBUG
    @State private var debugPartnerTx: CoreModel.Transaction?
    @State private var debugSharedTx: CoreModel.Transaction?
    @State private var debugIncomeTx: CoreModel.Transaction?
    #endif

    private var hasMore: Bool { rows.count < matchCount }

    // Web parity: current space only, excluded accounts only when asked, no mirror legs,
    // transfers only when toggled.
    private var filter: CoreLogic.TransactionFeed.Filter {
        let scope = SpaceScope.resolve(rawCurrentId: currentSpaceId, spaces: spaces)
        let ids = accounts
            .filter { scope.includes($0) && (showExcluded || !$0.excluded) }
            .map(\.id)
        let category: CoreLogic.TransactionFeed.CategoryFilter = switch categoryFilter {
        case .none: .all
        case .some(.none): .uncategorized
        case .some(.some(let id)): .category(id)
        }
        return .init(accountIds: ids, includeTransfers: showTransfers, category: category, search: search)
    }

    // A filter change starts from the top; a store change re-reads what's already loaded so
    // the list doesn't jump.
    private func reload(keepingLoaded: Bool) {
        let f = filter
        let count = keepingLoaded ? max(rows.count, Self.pageSize) : Self.pageSize
        rows = (try? CoreLogic.TransactionFeed.page(f, offset: 0, limit: count, in: ctx)) ?? []
        matchCount = (try? CoreLogic.TransactionFeed.count(f, in: ctx)) ?? rows.count
        searchTotalEur = search.isEmpty ? 0
            : rows.count == matchCount ? rows.reduce(Decimal(0)) { $0 + ($1.amountEur ?? 0) }
            : ((try? CoreLogic.TransactionFeed.netEur(f, in: ctx)) ?? 0)
        monthNets = [:]
        rebuildSections()
    }

    private func loadMore() {
        let next = (try? CoreLogic.TransactionFeed.page(
            filter, offset: rows.count, limit: Self.pageSize, in: ctx)) ?? []
        guard !next.isEmpty else { return }
        rows += next
        rebuildSections()
    }

    private func rebuildSections() {
        var order: [Date] = []
        var buckets: [Date: [CoreModel.Transaction]] = [:]
        for tx in rows {
            let key = CoreLogic.TransactionFeed.monthStart(tx.bookedAt)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(tx)
        }
        if hasMore {
            let f = filter
            for key in order where monthNets[key] == nil {
                monthNets[key] = (try? CoreLogic.TransactionFeed.monthNetEur(f, month: key, in: ctx)) ?? 0
            }
        } else {
            // Every match is loaded, so the rows themselves are the whole month.
            monthNets = buckets.mapValues { $0.reduce(Decimal(0)) { $0 + ($1.amountEur ?? 0) } }
        }
        sections = order.map { key in
            MonthSection(id: key,
                         title: key.formatted(.dateTime.month(.wide).year()),
                         net: monthNets[key] ?? 0,
                         rows: buckets[key] ?? [])
        }
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

    // A header's net covers the whole month, not just the rows loaded so far.
    struct MonthSection: Identifiable {
        let id: Date
        let title: String
        let net: Decimal
        let rows: [CoreModel.Transaction]
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(sections) { month in
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
                if hasMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Text("\(rows.count) of \(matchCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .onAppear { loadMore() }
                }
            }
            .navigationDestination(for: CoreModel.Transaction.self) { TransactionDetailView(tx: $0) }
            .task(id: PendingNavigation.shared.transactionId) {
                guard let id = PendingNavigation.shared.transactionId else { return }
                if let tx = (try? ctx.fetch(FetchDescriptor<CoreModel.Transaction>(
                    predicate: #Predicate { $0.id == id })))?.first {
                    path = [tx]
                }
                PendingNavigation.shared.transactionId = nil
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .safeAreaInset(edge: .bottom) {
                if !search.isEmpty && matchCount > 0 {
                    RunningTotalPill(count: matchCount, total: searchTotalEur)
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
            .sheet(item: $debugIncomeTx) { tx in
                MatchIncomeView(incomeTx: tx)
            }
            #endif
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView(
                        search.isEmpty ? "No Transactions" : "No Matches",
                        systemImage: "list.bullet.rectangle",
                        description: Text(search.isEmpty
                            ? "Nothing in this space yet. Sync a bank, or add a transaction with the + button."
                            : "Nothing matches “\(search)”.")
                    )
                }
            }
        }
        .task {
            #if DEBUG
            if let q = UITestHooks.search, !q.isEmpty { search = q }
            #endif
            reload(keepingLoaded: false)
            #if DEBUG
            applyHook()
            #endif
        }
        // Debounced: each keystroke used to refilter every row on the spot.
        .onChange(of: search) {
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                reload(keepingLoaded: false)
            }
        }
        .onChange(of: categoryFilter) { reload(keepingLoaded: false) }
        .onChange(of: showTransfers) { reload(keepingLoaded: false) }
        .onChange(of: showExcluded) { reload(keepingLoaded: false) }
        .onChange(of: currentSpaceId) { reload(keepingLoaded: false) }
        .reloadOnModelChange { reload(keepingLoaded: true) }
    }

    #if DEBUG
    private func applyHook() {
        func firstAny(_ match: (CoreModel.Transaction) -> Bool) -> CoreModel.Transaction? {
            let all = (try? ctx.fetch(FetchDescriptor<CoreModel.Transaction>(
                sortBy: CoreLogic.TransactionFeed.sort))) ?? []
            return all.first(where: match)
        }
        switch UITestHooks.presentSheet {
        case "categorize": categorizing = rows.first
        case "tx-detail":
            if let t = rows.first(where: { !$0.isTransfer && $0.routedFromTx == nil }) { path = [t] }
        case "tx-detail-transfer":
            if let t = firstAny({ $0.isTransfer && $0.routedFromTx == nil }) { path = [t] }
        case "pair-partner":
            debugPartnerTx = rows.first(where: { !$0.isTransfer && $0.routedFromTx == nil })
        case "shared-create":
            debugSharedTx = firstAny {
                $0.direction == .debit && !$0.isTransfer && $0.routedFromTx == nil
                    && $0.sharedExpenseGroup == nil && $0.amountEur != nil
            }
        case "match-income":
            debugIncomeTx = firstAny {
                $0.direction == .credit && !$0.isTransfer && $0.routedFromTx == nil
                    && $0.sharedExpenseGroup == nil && $0.amountEur != nil
            }
        case "tx-new": adding = TransactionEdit()
        case "tx-edit":
            if let t = rows.first(where: { !$0.isTransfer }) { adding = TransactionEdit(t) }
        default: break
        }
    }
    #endif
}

// Serif month heading with the month's net — the one editorial moment on this screen.
private struct MonthHeader: View {
    let title: String
    let net: Decimal

    var body: some View {
        AdaptiveStack(alignment: .firstTextBaseline) {
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
            AdaptiveStack(spacing: Theme.Space.xs) {
                rowText
                Spacer(minLength: Theme.Space.s)
                Text(amount)
                    .font(.readout(.body))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var rowText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .axLineLimit(1)
            HStack(spacing: 6) {
                Text(tx.bookedAt, format: .dateTime.day().month(.abbreviated))
                    .fixedSize()
                if !subtitle.isEmpty {
                    Text("· \(subtitle)").axLineLimit(1)
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
