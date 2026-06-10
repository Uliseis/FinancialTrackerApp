import SwiftUI
import UniformTypeIdentifiers
import CoreIntegrations

// One-time Enable Banking provisioning: application ID + the RSA app key (.pem) go into
// the iCloud-synced Keychain. Security posture: the key arrives via file import only —
// no paste field (Universal Clipboard leaks across devices) — its contents are never
// rendered, and it must parse as a usable RSA key before anything is stored.
struct EnableBankingSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var appId = ""
    @State private var importedPEM: String?
    @State private var keyStatus = ""
    @State private var importing = false
    @State private var confirmingRemove = false
    @State private var saveError: String?

    private let keychain = EBKeychain()

    private var hasStoredKey: Bool { keychain.isConfigured }

    private var isValid: Bool {
        !appId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (importedPEM != nil || hasStoredKey)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Application") {
                    TextField("Application ID", text: $appId)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.body.monospaced())
                }
                Section {
                    Button(importedPEM == nil ? "Import Key File…" : "Replace Key File…",
                           systemImage: "key") { importing = true }
                    if !keyStatus.isEmpty {
                        Label(keyStatus, systemImage: "checkmark.seal")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Private key")
                } footer: {
                    Text("The .pem file from the Enable Banking control panel. It is stored only in your iCloud Keychain and never shown again. Delete the file after setup.")
                }
                if hasStoredKey {
                    Section {
                        Button("Remove Key & Application ID", role: .destructive) {
                            confirmingRemove = true
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Enable Banking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.data, .text, .item]) { result in
                importKey(result)
            }
            .confirmationDialog("Remove the key and application ID?",
                                isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { removeAll() }
            } message: {
                Text("Bank sync stops working until a key is imported again. Enable Banking never re-shows a private key.")
            }
            .saveErrorAlert($saveError)
            .task { prefill() }
        }
    }

    private func prefill() {
        if let stored = try? keychain.loadApplicationId() { appId = stored }
        if hasStoredKey { keyStatus = "Using the stored key" }
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["EB_SETUP_KEY_PATH"],
           let pem = try? String(contentsOfFile: NSString(string: path).expandingTildeInPath,
                                 encoding: .utf8) {
            acceptPEM(pem)
        }
        if let id = ProcessInfo.processInfo.environment["EB_SETUP_APP_ID"] { appId = id }
        if ProcessInfo.processInfo.environment["EB_SETUP_AUTOSAVE"] == "1", isValid { save() }
        #endif
    }

    private func importKey(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            saveError = "Couldn’t open the file."
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let pem = try? String(contentsOf: url, encoding: .utf8) else {
            saveError = "Couldn’t read the file."
            return
        }
        acceptPEM(pem)
    }

    private func acceptPEM(_ pem: String) {
        guard (try? EBRSAKey.from(pem: pem)) != nil else {
            saveError = "That file isn’t a usable RSA private key (PEM)."
            return
        }
        importedPEM = pem
        keyStatus = "Key file loaded and validated"
    }

    private func save() {
        do {
            if let pem = importedPEM {
                try keychain.storeKeyPEM(pem)
            }
            try keychain.storeApplicationId(
                appId.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } catch {
            saveError = "The key wasn’t saved to the Keychain."
        }
    }

    private func removeAll() {
        keychain.removeAll()
        importedPEM = nil
        keyStatus = ""
        appId = ""
    }
}

#if DEBUG
#Preview {
    EnableBankingSetupView()
}
#endif
