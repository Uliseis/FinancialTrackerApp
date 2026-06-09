import SwiftUI
import SwiftData
import CoreModel

struct ConnectionsView: View {
    @Query(sort: [SortDescriptor(\Connection.institutionName)])
    private var connections: [Connection]

    var body: some View {
        NavigationStack {
            List {
                ForEach(connections) { conn in
                    NavigationLink {
                        ConnectionDetailView(connection: conn)
                    } label: {
                        ConnectionRow(connection: conn)
                    }
                }
            }
            .navigationTitle("Connections")
            .overlay {
                if connections.isEmpty {
                    ContentUnavailableView(
                        "No Connections",
                        systemImage: "link",
                        description: Text("Linked banks appear here.")
                    )
                }
            }
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
                        .font(.caption2)
                        .foregroundStyle(hint.warn ? .orange : .secondary)
                }
            }
        }
    }
}

struct StatusBadge: View {
    let status: ConnectionStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.tint.opacity(0.18), in: Capsule())
            .foregroundStyle(status.tint)
    }
}

extension ConnectionStatus {
    var tint: Color {
        switch self {
        case .active: .green
        case .pending: .orange
        case .expired, .error, .revoked: .red
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
    ConnectionsView()
        .modelContainer(PreviewData.container)
}
#endif
