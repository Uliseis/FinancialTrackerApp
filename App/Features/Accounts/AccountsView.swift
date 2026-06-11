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
    @State private var accountCount: Int = 0
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
                    AccountsSummaryHeader(total: spaceTotal, accountCount: accountCount)
                        .listRowInsets(EdgeInsets(top: Theme.Space.s, leading: Theme.Space.m,
                                                  bottom: Theme.Space.s, trailing: Theme.Space.m))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
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
                                .tint(.brand)
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
        accountCount = visible.count
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

// Cash net worth readout for the current space — the Accounts counterpart to
// the Dashboard hero (light, type-on-surface; the dark panel stays unique to
// the Dashboard).
private struct AccountsSummaryHeader: View {
    let total: Decimal
    let accountCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("CASH NET WORTH")
                .font(.caption2.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            Text(Money.format(total, currency: "EUR"))
                .font(.readout(.largeTitle, weight: .bold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("^[\(accountCount) account](inflect: true) in this space")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct AccountRow: View {
    let account: Account
    let eur: Decimal?

    private var tint: Color { Color(hex: account.group?.color) ?? .brand }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            AccountTypeChip(type: account.type, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.body)
                    .lineLimit(1)
                Text(account.institution)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            if let eur {
                MoneyText(amount: eur)
            } else {
                Text("—")
                    .font(.body.monospacedDigit())
                    .fontDesign(.rounded)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(account.excluded ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}

private struct AccountTypeChip: View {
    let type: AccountType
    let tint: Color
    @ScaledMetric(relativeTo: .body) private var dimension: CGFloat = 36

    var body: some View {
        Image(systemName: type.icon)
            .font(.system(size: dimension * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: dimension, height: dimension)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: dimension * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    AccountsView()
        .modelContainer(PreviewData.container)
}
#endif
