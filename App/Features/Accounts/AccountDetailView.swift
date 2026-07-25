import SwiftUI
import SwiftData
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
    private static let pageSize = 100

    private var accountIsLive: Bool { account.modelContext != nil && !account.isDeleted }

    private var rows: [CoreModel.Transaction] {
        guard accountIsLive else { return [] }
        let id = account.id
        return allTx.filter { tx in
            guard tx.account?.id == id else { return false }
            guard tx.routedFromTx == nil else { return false }
            guard !search.isEmpty else { return true }
            return (tx.transactionDescription?.localizedStandardContains(search) ?? false)
                || (tx.counterparty?.localizedStandardContains(search) ?? false)
        }
    }

    var body: some View {
        List {
            Section {
                AccountDetailHeader(account: account)
                    .instrumentPanelRow()
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
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editing = AccountEdit(account) }
            }
        }
        .sheet(item: $editing, content: AccountFormView.init)
        .sheet(item: $adding) { TransactionFormView(edit: $0) }
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
}

private struct AccountDetailHeader: View {
    let account: Account

    private var balance: Decimal { account.balance ?? account.manualOpeningBalance ?? 0 }

    var body: some View {
        InstrumentPanel {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                PanelLabel(text: account.institution)
                Text(Money.format(balance, currency: account.currency))
                    .font(.readout(.largeTitle, weight: .bold))
                    .foregroundStyle(balance < 0 ? Theme.heroAccent : .white)
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
