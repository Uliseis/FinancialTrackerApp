import SwiftUI
import SwiftData
import CoreModel
import CoreLogic
import CoreIntegrations

struct ConnectionDetailView: View {
    let connection: Connection
    @Environment(\.modelContext) private var ctx
    @State private var reconnecting = false
    @State private var resultMessage = ""
    @State private var showingResult = false

    private var accounts: [Account] {
        connection.accounts.sorted { $0.name < $1.name }
    }

    private var canReconnect: Bool {
        connection.connector == .enablebanking && connection.institutionId != nil
            && EBKeychain().isConfigured
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
                if canReconnect {
                    Button(action: reconnect) {
                        HStack {
                            Label("Reconnect", systemImage: "arrow.clockwise")
                            if reconnecting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(reconnecting)
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
        .alert("Reconnect", isPresented: $showingResult) {} message: {
            Text(resultMessage)
        }
    }

    private func reconnect() {
        guard let aspspName = connection.institutionId else { return }
        let country = CoreLogic.EBConnect.storedCountry(of: connection) ?? "ES"
        reconnecting = true
        Task {
            defer { reconnecting = false }
            do {
                let outcome = try await BankLink.link(
                    aspspName: aspspName, country: country,
                    existing: connection, in: ctx)
                resultMessage = outcome.authorized
                    ? "Reconnected. ^[\(outcome.accountCount) account](inflect: true) authorized."
                    : "Authorization is still pending at the bank."
                showingResult = true
            } catch let error where error.isAuthCancellation {
                // User closed the bank's page.
            } catch CoreLogic.EBConnect.CallbackError.bankReported(let reason) {
                resultMessage = "The bank declined the connection (\(reason))."
                showingResult = true
            } catch {
                resultMessage = "Couldn’t reconnect."
                showingResult = true
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ConnectionDetailView(connection: PreviewData.sampleConnection)
    }
}
#endif
