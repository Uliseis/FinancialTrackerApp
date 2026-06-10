import SwiftUI
import SwiftData
import CoreModel
import CoreLogic
import CoreIntegrations

// Bank picker for first-time links (ports the web connect form). Spain-only, like the
// web's default. Tapping a bank runs the full BankLink round trip in place.
struct ConnectBankView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var aspsps: [Aspsp] = []
    @State private var search = ""
    @State private var loadError: String?
    @State private var loading = true
    @State private var linking: String?
    @State private var resultMessage = ""
    @State private var showingResult = false
    @State private var linkSucceeded = false

    private static let country = "ES"

    private var filtered: [Aspsp] {
        guard !search.isEmpty else { return aspsps }
        return aspsps.filter { $0.name.localizedStandardContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered, id: \.name) { aspsp in
                    Button { start(aspsp) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(aspsp.name)
                                if let bic = aspsp.bic {
                                    Text(bic).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if linking == aspsp.name {
                                ProgressView()
                            }
                        }
                    }
                    .tint(.primary)
                    .disabled(linking != nil)
                }
            }
            .searchable(text: $search, prompt: "Search banks")
            .navigationTitle("Link a Bank")
            .navigationBarTitleDisplayMode(.inline)
            .overlay { overlayContent }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadAspsps() }
            .alert("Bank Link", isPresented: $showingResult) {
                Button("OK") { if linkSucceeded { dismiss() } }
            } message: {
                Text(resultMessage)
            }
        }
        .interactiveDismissDisabled(linking != nil)
    }

    @ViewBuilder private var overlayContent: some View {
        if loading {
            ProgressView("Loading banks…")
        } else if let loadError {
            ContentUnavailableView("Couldn’t Load Banks", systemImage: "wifi.exclamationmark",
                                   description: Text(loadError))
        } else if filtered.isEmpty {
            ContentUnavailableView.search
        }
    }

    private func loadAspsps() async {
        loading = true
        defer { loading = false }
        do {
            let signer = try EBKeychain().loadSigner()
            let client = EBClient(tokenProvider: signer)
            aspsps = try await client.listAspsps(country: Self.country, psuType: "personal")
            loadError = nil
        } catch EBKeyError.notFound {
            loadError = "Set up the Enable Banking key first."
        } catch {
            loadError = "Enable Banking didn’t respond. Check the key and try again."
        }
    }

    private func start(_ aspsp: Aspsp) {
        linking = aspsp.name
        Task {
            defer { linking = nil }
            do {
                let outcome = try await BankLink.link(
                    aspspName: aspsp.name, country: aspsp.country, in: ctx)
                resultMessage = outcome.authorized
                    ? "Connected. ^[\(outcome.accountCount) account](inflect: true) authorized."
                    : "Authorization is still pending at the bank."
                linkSucceeded = true
                showingResult = true
            } catch let error where error.isAuthCancellation {
                // User closed the bank's page — keep the picker open.
            } catch CoreLogic.EBConnect.CallbackError.bankReported(let reason) {
                resultMessage = "The bank declined the connection (\(reason))."
                showingResult = true
            } catch {
                resultMessage = "Couldn’t connect to \(aspsp.name)."
                showingResult = true
            }
        }
    }
}

#if DEBUG
#Preview {
    ConnectBankView()
        .modelContainer(PreviewData.container)
}
#endif
