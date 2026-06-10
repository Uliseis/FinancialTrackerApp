import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

struct AccountsView: View {
    @Query(sort: [SortDescriptor(\AccountSpace.sortOrder),
                  SortDescriptor(\AccountSpace.createdAt)])
    private var spaces: [AccountSpace]

    @Query(sort: [SortDescriptor(\AccountGroup.sortOrder)])
    private var groups: [AccountGroup]

    @Query(sort: [SortDescriptor(\Account.name)])
    private var accounts: [Account]

    @AppStorage(SpaceSelection.key) private var currentSpaceId = ""
    @Environment(\.modelContext) private var ctx
    @State private var eurBalances: [UUID: Decimal] = [:]
    @State private var sections: [GroupSection] = []
    @State private var spaceTotal: Decimal = 0
    @State private var editingAccount: AccountEdit?
    @State private var anchoringAccount: Account?

    // Cached current-space layout: non-archived accounts grouped by AccountGroup
    // (sortOrder), nil ⇒ Other. Built in rebuild() so grouping runs only on input or
    // store changes — not on every body render.
    private struct GroupSection: Identifiable {
        let id: String
        let title: String
        let accounts: [Account]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Cash net worth",
                                   value: Money.format(spaceTotal, currency: "EUR"))
                        .font(.headline)
                }
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.accounts) { account in
                            Button {
                                editingAccount = AccountEdit(account)
                            } label: {
                                AccountRow(account: account, eur: eurBalances[account.id])
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading) {
                                Button {
                                    anchoringAccount = account
                                } label: {
                                    Label("Set Balance", systemImage: "scalemass")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .refreshable { reload() }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SpacePicker() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editingAccount = AccountEdit() } label: {
                        Label("New Account", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editingAccount, content: AccountFormView.init)
            .sheet(item: $anchoringAccount, content: BalanceAnchorView.init)
            .overlay {
                if sections.isEmpty {
                    ContentUnavailableView("No Accounts", systemImage: "creditcard")
                }
            }
        }
        .task {
            reload()
            #if DEBUG
            if UITestHooks.presentSheet == "account-new" { editingAccount = AccountEdit() }
            if UITestHooks.presentSheet == "account-edit",
               let first = accounts.first(where: { !$0.archived }) {
                editingAccount = AccountEdit(first)
            }
            if UITestHooks.presentSheet == "anchor",
               let first = accounts.first(where: { !$0.archived }) {
                anchoringAccount = first
            }
            #endif
        }
        .onChange(of: currentSpaceId) { rebuild() }
        .reloadOnModelChange { reload() }
    }

    private func reload() {
        eurBalances = (try? CoreLogic.Accounts.computeEurBalances(accounts, in: ctx)) ?? [:]
        rebuild()
    }

    private func rebuild() {
        let scope = SpaceScope.resolve(rawCurrentId: currentSpaceId, spaces: spaces)
        let visible = accounts.filter { !$0.archived && scope.includes($0) }
        spaceTotal = visible
            .filter { CoreLogic.AccountStatus.isCountedInCashNetWorth($0) }
            .reduce(Decimal(0)) { $0 + (eurBalances[$1.id] ?? 0) }

        var built: [GroupSection] = []
        for group in groups {
            let rows = visible.filter { $0.group?.id == group.id }
            if !rows.isEmpty {
                built.append(GroupSection(id: group.id.uuidString, title: group.name, accounts: rows))
            }
        }
        let ungrouped = visible.filter { $0.group == nil }
        if !ungrouped.isEmpty {
            built.append(GroupSection(id: "ungrouped", title: "Other", accounts: ungrouped))
        }
        sections = built
    }
}

private struct AccountRow: View {
    let account: Account
    let eur: Decimal?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.body)
                Text(account.institution)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if let eur {
                MoneyText(amount: eur)
            } else {
                Text("—").font(.body.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .opacity(account.excluded ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    AccountsView()
        .modelContainer(PreviewData.container)
}
#endif
