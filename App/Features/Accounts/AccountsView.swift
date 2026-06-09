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

    private var scope: SpaceScope {
        SpaceScope.resolve(rawCurrentId: currentSpaceId, spaces: spaces)
    }

    // In the current space, non-archived; grouped by AccountGroup (sortOrder), nil ⇒ Other.
    private var visible: [Account] {
        accounts.filter { !$0.archived && scope.includes($0) }
    }

    private var spaceTotal: Decimal {
        visible.filter { CoreLogic.AccountStatus.isCountedInCashNetWorth($0) }
            .reduce(Decimal(0)) { $0 + (eurBalances[$1.id] ?? 0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Cash net worth",
                                   value: Money.format(spaceTotal, currency: "EUR"))
                        .font(.headline)
                }
                ForEach(groups) { group in
                    let rows = visible.filter { $0.group?.id == group.id }
                    if !rows.isEmpty {
                        Section(group.name) {
                            ForEach(rows) { AccountRow(account: $0, eur: eurBalances[$0.id]) }
                        }
                    }
                }
                let ungrouped = visible.filter { $0.group == nil }
                if !ungrouped.isEmpty {
                    Section("Other") {
                        ForEach(ungrouped) { AccountRow(account: $0, eur: eurBalances[$0.id]) }
                    }
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SpacePicker() }
            }
            .overlay {
                if visible.isEmpty {
                    ContentUnavailableView("No Accounts", systemImage: "creditcard")
                }
            }
        }
        .task { reload() }
    }

    private func reload() {
        eurBalances = (try? CoreLogic.Accounts.computeEurBalances(accounts, in: ctx)) ?? [:]
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
            Text(eur.map { Money.format($0, currency: "EUR") } ?? "—")
                .font(.body.monospacedDigit())
        }
        .opacity(account.excluded ? 0.55 : 1)
    }
}

#if DEBUG
#Preview {
    AccountsView()
        .modelContainer(PreviewData.container)
}
#endif
