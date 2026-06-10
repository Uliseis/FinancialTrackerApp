import SwiftUI
import SwiftData
import CoreModel
import CoreLogic
import CoreIntegrations

// Pushed from SettingsView, which registers the Connection destination.
struct ConnectionsListView: View {
    @Query(sort: [SortDescriptor(\Connection.institutionName)])
    private var connections: [Connection]
    @Environment(\.modelContext) private var ctx
    @State private var settingUp = false
    @State private var linkingBank = false
    @State private var ebConfigured = false
    @State private var syncingAll = false
    @State private var syncMessage = ""
    @State private var showingSyncResult = false

    var body: some View {
        List {
            Section {
                Button { settingUp = true } label: {
                    LabeledContent("Enable Banking") {
                        HStack(spacing: 8) {
                            Text(ebConfigured ? "Configured" : "Not set up")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .tint(.primary)
            } footer: {
                Text("Bank sync uses an app key stored in your iCloud Keychain.")
            }
            if !connections.isEmpty {
                Section("Linked banks") {
                    ForEach(connections) { conn in
                        NavigationLink(value: conn) {
                            ConnectionRow(connection: conn)
                        }
                    }
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .navigationTitle("Connections")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: syncAll) {
                    if syncingAll {
                        ProgressView()
                    } else {
                        Label("Sync All", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(!ebConfigured || syncingAll || connections.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { linkingBank = true } label: {
                    Label("Link a Bank", systemImage: "plus")
                }
                .disabled(!ebConfigured)
            }
        }
        .alert("Sync", isPresented: $showingSyncResult) {} message: {
            Text(syncMessage)
        }
        .sheet(isPresented: $settingUp, onDismiss: refreshConfigured) {
            EnableBankingSetupView()
        }
        .sheet(isPresented: $linkingBank) {
            ConnectBankView()
        }
        .task {
            refreshConfigured()
            #if DEBUG
            // Presenting while the push transition is in flight gets dropped silently.
            switch UITestHooks.presentSheet {
            case "eb-setup":
                try? await Task.sleep(for: .milliseconds(700))
                settingUp = true
            case "connect-bank":
                try? await Task.sleep(for: .milliseconds(700))
                linkingBank = true
            case "eb-sync-all":
                syncAll()
            default: break
            }
            #endif
        }
    }

    private func refreshConfigured() {
        ebConfigured = EBKeychain().isConfigured
    }

    private func syncAll() {
        syncingAll = true
        Task {
            defer { syncingAll = false }
            do {
                let signer = try EBKeychain().loadSigner()
                let results = await CoreLogic.EBSync.syncAll(
                    api: EBClient(tokenProvider: signer), in: ctx)
                let inserted = results.reduce(0) { $0 + $1.transactionsInserted }
                let failed = results.filter { !$0.errors.isEmpty }.count
                syncMessage = failed == 0
                    ? "Synced \(pluralized(results.count, "connection")). \(pluralized(inserted, "new transaction"))."
                    : "Synced with issues on \(pluralized(failed, "connection")). \(pluralized(inserted, "new transaction"))."
            } catch {
                syncMessage = "Sync failed — check the Enable Banking key."
            }
            showingSyncResult = true
        }
    }
}

private struct ConnectionRow: View {
    let connection: Connection

    private var subtitle: String {
        let n = connection.accounts.count
        return "\(connection.connector.displayName) · \(n) account\(n == 1 ? "" : "s")"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.institutionName ?? connection.institutionId ?? "—")
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(status: connection.status)
                if let hint = ExpiryHint.make(connection.expiresAt) {
                    Text(hint.label)
                        .font(.caption)
                        .foregroundStyle(hint.warn ? .orange : .secondary)
                }
            }
        }
    }
}

struct StatusBadge: View {
    let status: ConnectionStatus

    var body: some View {
        TagChip(text: status.rawValue.capitalized, tint: status.tint)
    }
}

extension ConnectionStatus {
    var tint: Color {
        switch self {
        case .active: .positiveAmount
        case .pending: .orange
        case .expired, .error, .revoked: .negativeAmount
        }
    }
}

extension Connector {
    var displayName: String {
        switch self {
        case .enablebanking: "Enable Banking"
        case .trading212: "Trading 212"
        case .revolutx: "Revolut X"
        case .manual: "Manual"
        }
    }
}

enum ExpiryHint {
    static func make(_ expiresAt: Date?, now: Date = .now) -> (label: String, warn: Bool)? {
        guard let expiresAt else { return nil }
        let days = Int((expiresAt.timeIntervalSince(now) / 86_400).rounded())
        if days < 0 { return ("Expired \(abs(days))d ago", true) }
        if days <= 14 { return ("Re-auth in \(days)d", true) }
        return ("\(days)d left", false)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ConnectionsListView()
            .navigationDestination(for: Connection.self) { ConnectionDetailView(connection: $0) }
    }
    .modelContainer(PreviewData.container)
}
#endif
