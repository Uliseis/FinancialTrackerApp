import SwiftUI
import SwiftData
import CoreModel

struct AccountsView: View {
    @Query(sort: [SortDescriptor(\AccountSpace.sortOrder)])
    private var spaces: [AccountSpace]

    @Query(sort: [SortDescriptor(\Account.name)])
    private var accounts: [Account]

    private var visible: [Account] { accounts.filter { !$0.archived } }
    private var orphaned: [Account] { visible.filter { $0.space == nil } }

    var body: some View {
        NavigationStack {
            List {
                ForEach(spaces) { space in
                    let rows = visible.filter { $0.space?.id == space.id }
                    if !rows.isEmpty {
                        Section(space.name) {
                            ForEach(rows) { AccountRow(account: $0) }
                        }
                    }
                }
                if !orphaned.isEmpty {
                    Section("No Space") {
                        ForEach(orphaned) { AccountRow(account: $0) }
                    }
                }
            }
            .navigationTitle("Accounts")
            .overlay {
                if visible.isEmpty {
                    ContentUnavailableView("No Accounts", systemImage: "creditcard")
                }
            }
        }
    }
}

private struct AccountRow: View {
    @Environment(\.modelContext) private var ctx
    let account: Account

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
            VStack(alignment: .trailing, spacing: 2) {
                Text(nativeBalance)
                    .font(.body.monospacedDigit())
                if let eur = eurLine {
                    Text(eur)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .opacity(account.excluded ? 0.55 : 1)
    }

    private var nativeBalance: String {
        guard let bal = account.balance else { return "—" }
        return Money.format(bal, currency: account.currency)
    }

    // Shown only for non-EUR accounts; for EUR it's identical to the native line.
    private var eurLine: String? {
        guard account.currency.uppercased() != "EUR",
              let eur = Money.eurBalance(of: account, in: ctx)
        else { return nil }
        return "≈ " + Money.format(eur, currency: "EUR")
    }
}

#if DEBUG
#Preview {
    AccountsView()
        .modelContainer(PreviewData.container)
}
#endif
