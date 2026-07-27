import SwiftUI
import CoreIntegrations

// Holds the Trading 212 API credentials so the broker's value refreshes itself. The key is
// generated in the Trading 212 app and stored in the Keychain, never in the SwiftData store
// (and so never in CloudKit).
struct Trading212SettingsView: View {
    @State private var key = ""
    @State private var secret = ""
    @State private var stored = MarketKeychain().hasTrading212
    @State private var testResult: String?
    @State private var testing = false

    private let keychain = MarketKeychain()

    var body: some View {
        Form {
            Section {
                LabeledContent("API key") {
                    SecureField("Paste key", text: $key)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                LabeledContent("API secret") {
                    SecureField("Paste secret", text: $secret)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Button("Save Credentials") { save() }
                    .disabled(key.isEmpty || secret.isEmpty)
            } header: {
                Text(stored ? "Stored" : "Not set up")
            } footer: {
                Text("In the Trading 212 app: Settings → API. Generate a read-only key, then paste both halves here. They're kept in the Keychain on this device.")
            }

            if stored {
                Section {
                    Button {
                        Task { await test() }
                    } label: {
                        HStack {
                            Text("Test Connection")
                            if testing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(testing)
                    if let testResult {
                        Text(testResult).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Remove Credentials", role: .destructive) {
                        keychain.removeTrading212()
                        stored = false
                        testResult = nil
                    }
                }
            }

            Section {
                Text("Once saved, open the Trading 212 account under Investments and set its value source to Trading 212.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Trading 212")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        do {
            try keychain.storeTrading212(
                key: key.trimmingCharacters(in: .whitespacesAndNewlines),
                secret: secret.trimmingCharacters(in: .whitespacesAndNewlines))
            key = ""
            secret = ""
            stored = true
            testResult = nil
        } catch {
            testResult = "Couldn't save to the Keychain."
        }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        do {
            let creds = try keychain.loadTrading212()
            let summary = try await Trading212Client(credentials: creds).accountSummary()
            testResult = "Account value \(Money.format(summary.totalValueEur, currency: summary.currency))."
        } catch let error as Trading212Error {
            testResult = error.status == 401
                ? "Trading 212 rejected the key (401). Check both halves."
                : "Trading 212 returned \(error.status)."
        } catch {
            testResult = "Couldn't reach Trading 212."
        }
    }
}
