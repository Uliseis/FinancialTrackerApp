import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CoreModel
import CoreLogic

// One account's transactions. Tapping a row on the Accounts tab used to jump straight to
// the edit form, which meant there was no way to see what was actually in an account.
struct AccountDetailView: View {
    let account: Account
    @Query(sort: [SortDescriptor(\CoreModel.Transaction.bookedAt, order: .reverse),
                  SortDescriptor(\CoreModel.Transaction.createdAt, order: .reverse)])
    private var allTx: [CoreModel.Transaction]
    @Environment(\.modelContext) private var ctx
    @State private var search = ""
    @State private var editing: AccountEdit?
    @State private var adding: TransactionEdit?
    @State private var visibleLimit = pageSize
    @State private var nativeBalance: Decimal?
    @State private var importing = false
    @State private var importSummary: CoreLogic.StatementImport.Summary?
    @State private var saveError: String?
    private static let pageSize = 100

    private var accountIsLive: Bool { account.modelContext != nil && !account.isDeleted }
    private var isManual: Bool { accountIsLive && CoreLogic.Accounts.isManual(account) }

    private var accountTx: [CoreModel.Transaction] {
        guard accountIsLive else { return [] }
        let id = account.id
        return allTx.filter { $0.account?.id == id && $0.routedFromTx == nil }
    }

    private var rows: [CoreModel.Transaction] {
        guard !search.isEmpty else { return accountTx }
        return accountTx.filter { tx in
            (tx.transactionDescription?.localizedStandardContains(search) ?? false)
                || (tx.counterparty?.localizedStandardContains(search) ?? false)
        }
    }

    // Only manual accounts have charges nobody else records; a synced account's
    // subscriptions arrive from the bank.
    private var recurring: [CoreLogic.Recurring.Item] {
        isManual ? CoreLogic.Recurring.detect(accountTx) : []
    }

    var body: some View {
        List {
            Section {
                AccountDetailHeader(account: account, balance: nativeBalance)
                    .instrumentPanelRow()
            }
            if !recurring.isEmpty, search.isEmpty {
                recurringSection
            }
            Section("Transactions") {
                ForEach(rows.prefix(visibleLimit)) { tx in
                    NavigationLink(value: tx) { TransactionRow(tx: tx, showsAccount: false) }
                }
                if visibleLimit < rows.count {
                    HStack {
                        Spacer()
                        Text("\(visibleLimit) of \(rows.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .onAppear { visibleLimit = min(visibleLimit + Self.pageSize, rows.count) }
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .searchable(text: $search, prompt: "Description or counterparty")
        .navigationTitle(accountIsLive ? account.displayName : "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: CoreModel.Transaction.self) { TransactionDetailView(tx: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = TransactionEdit(accountId: account.id) } label: {
                    Label("New Transaction", systemImage: "plus")
                }
            }
            if isManual {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importing = true } label: {
                        Label("Import Statement", systemImage: "square.and.arrow.down")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editing = AccountEdit(account) }
            }
        }
        .task { reloadBalance() }
        .reloadOnModelChange { reloadBalance() }
        .sheet(item: $editing, content: AccountFormView.init)
        .sheet(item: $adding) { TransactionFormView(edit: $0) }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            importStatement(result)
        }
        .alert("Statement Imported", isPresented: Binding(
            get: { importSummary != nil }, set: { if !$0 { importSummary = nil } }),
               presenting: importSummary) { summary in
            if !summary.unmatched.isEmpty {
                Button("Delete \(summary.unmatched.count) unmatched", role: .destructive) {
                    do {
                        try CoreLogic.StatementImport.deleteUnmatched(ids: summary.unmatched.map(\.id), in: ctx)
                    } catch {
                        saveError = "The unmatched charges weren’t deleted."
                    }
                }
            }
            Button("OK") {}
        } message: { summary in
            Text(summaryText(summary))
        }
        .saveErrorAlert($saveError)
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? "No Transactions" : "No Matches",
                    systemImage: "list.bullet.rectangle",
                    description: Text(search.isEmpty
                        ? "Nothing booked to this account yet."
                        : "Nothing matches “\(search)”."))
            }
        }
    }

    private var recurringSection: some View {
        Section {
            ForEach(recurring) { item in
                RecurringRow(item: item, currency: account.currency) { book(item) }
            }
        } header: {
            HStack {
                Text("Recurring")
                Spacer()
                let unbooked = recurring.filter { $0.bookedAt == nil }.reduce(Decimal(0)) { $0 + $1.amount }
                if unbooked != 0 {
                    Text("\(Money.format(unbooked, currency: account.currency)) not booked yet")
                }
            }
        }
    }

    private func book(_ item: CoreLogic.Recurring.Item) {
        do {
            let tx = try CoreLogic.Transactions.createManual(
                account: account, amount: -item.amount, bookedAt: .now,
                description: item.merchant, counterparty: item.merchant, in: ctx)
            _ = try? CoreLogic.Categorize.applyRulesToTransactions(in: ctx, txIds: [tx.id])
        } catch {
            saveError = "The charge wasn’t booked."
        }
    }

    private func importStatement(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            importSummary = try CoreLogic.StatementImport.importRevolutCSV(text, into: account, in: ctx)
        } catch CoreLogic.RevolutCSV.ParseError.missingColumns(let columns) {
            saveError = "That doesn’t look like a Revolut statement (missing \(columns.joined(separator: ", ")))."
        } catch {
            saveError = "The statement wasn’t imported."
        }
    }

    private func summaryText(_ s: CoreLogic.StatementImport.Summary) -> String {
        var lines = [
            "\(s.inserted) new charges added.",
            "\(s.matchedManual) already logged by hand, now linked to the statement.",
        ]
        if s.skippedDuplicate > 0 { lines.append("\(s.skippedDuplicate) already imported.") }
        if s.skippedTransfers > 0 { lines.append("\(s.skippedTransfers) top-ups skipped (they come in as transfers).") }
        if s.skippedNotCompleted > 0 { lines.append("\(s.skippedNotCompleted) pending/reverted rows ignored.") }
        if !s.errors.isEmpty { lines.append("\(s.errors.count) rows couldn’t be read.") }
        if !s.unmatched.isEmpty {
            lines.append("\(s.unmatched.count) logged charges aren’t on the statement:")
            for u in s.unmatched.prefix(8) {
                let label = [u.bookedAt.formatted(date: .abbreviated, time: .omitted),
                             Money.format(u.amount, currency: account.currency), u.description]
                lines.append(label.compactMap { $0 }.joined(separator: " · "))
            }
            if s.unmatched.count > 8 { lines.append("…") }
        }
        return lines.joined(separator: "\n")
    }

    private func reloadBalance() {
        guard accountIsLive else { return }
        nativeBalance = CoreLogic.Accounts.computeNativeBalances([account], in: ctx)[account.id]
    }
}

private struct RecurringRow: View {
    let item: CoreLogic.Recurring.Item
    let currency: String
    let onBook: () -> Void

    private var isOverdue: Bool {
        item.bookedAt == nil && Calendar.current.component(.day, from: .now) > item.expectedDay + 3
    }

    private var status: String {
        if let booked = item.bookedAt {
            return "Booked \(booked.formatted(.dateTime.day().month()))"
        }
        return (isOverdue ? "Overdue · " : "") + "Expected around day \(item.expectedDay)"
    }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.merchant).lineLimit(1)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(isOverdue ? Color.orange : Color.secondary)
            }
            Spacer()
            Text(Money.format(item.amount, currency: currency))
                .font(.readout(.body))
            if item.bookedAt == nil {
                Button("Book", action: onBook)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

private struct AccountDetailHeader: View {
    let account: Account
    // Computed by CoreLogic (anchor + Σ since anchor, or opening + Σ all). Reading
    // `account.balance` here showed 0,00 on every manual/anchored account, because that
    // column only holds a bank-reported figure.
    let balance: Decimal?

    var body: some View {
        InstrumentPanel {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                PanelLabel(text: account.institution)
                Text(balance.map { Money.format($0, currency: account.currency) } ?? "—")
                    .font(.readout(.largeTitle, weight: .bold))
                    .foregroundStyle((balance ?? 0) < 0 ? Theme.heroAccent : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(spacing: Theme.Space.s) {
                    Text(account.type.label)
                    if account.alias != nil {
                        Text("· \(account.name)").lineLimit(1)
                    }
                    if account.excluded {
                        Text("· excluded")
                    }
                    if account.archived {
                        Text("· archived")
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        AccountDetailView(account: PreviewData.sampleAccount)
    }
    .modelContainer(PreviewData.container)
}
#endif
