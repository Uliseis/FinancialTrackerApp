import SwiftUI
import SwiftData
import CoreModel

struct ConnectionDetailView: View {
    let connection: Connection

    private var accounts: [Account] {
        connection.accounts.sorted { $0.name < $1.name }
    }

    private var recentRuns: [SyncRun] {
        connection.syncRuns.sorted { $0.startedAt > $1.startedAt }.prefix(8).map { $0 }
    }

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Status") { StatusBadge(status: connection.status) }
                LabeledContent("Connector", value: connection.connector.displayName)
                if let expires = connection.expiresAt {
                    LabeledContent("Expires",
                                   value: expires.formatted(date: .abbreviated, time: .omitted))
                }
                LabeledContent("Last sync", value: connection.lastSyncAt
                    .map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
                if let err = connection.lastError, !err.isEmpty {
                    LabeledContent("Last error", value: err)
                        .foregroundStyle(Color.negativeAmount)
                }
            }

            Section("Accounts (\(accounts.count))") {
                if accounts.isEmpty {
                    Text("No accounts").foregroundStyle(.secondary)
                } else {
                    ForEach(accounts) { account in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name).lineLimit(1)
                            Text([account.type.rawValue.capitalized, account.iban]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !recentRuns.isEmpty {
                Section("Recent syncs") {
                    ForEach(recentRuns) { run in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.callout)
                                Text(run.status.rawValue.capitalized)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if run.insertedTransactions > 0 {
                                Text("+\(run.insertedTransactions)")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(Color.positiveAmount)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(connection.institutionName ?? "Connection")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ConnectionDetailView(connection: PreviewData.sampleConnection)
    }
}
#endif
