import SwiftUI
import SwiftData
import LocalAuthentication
import CoreModel

@main
struct FinancialTrackerApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema(CoreModelSchema.allTypes)
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer init failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}

struct RootView: View {
    @State private var unlocked = false
    @State private var authError: String?

    var body: some View {
        Group {
            if unlocked {
                ContentView()
            } else {
                LockScreen(error: authError, onUnlock: authenticate)
            }
        }
        .task { authenticate() }
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authError = error?.localizedDescription ?? "Biometrics unavailable"
            return
        }
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock FinancialTracker"
        ) { success, evalError in
            Task { @MainActor in
                if success {
                    unlocked = true
                    authError = nil
                } else {
                    authError = evalError?.localizedDescription
                }
            }
        }
    }
}

struct LockScreen: View {
    let error: String?
    let onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("FinancialTracker")
                .font(.title2.weight(.semibold))
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Unlock", action: onUnlock)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Coming soon") {
                    Text("Accounts")
                    Text("Transactions")
                    Text("Transfers")
                    Text("Investments")
                    Text("Budgets")
                }
            }
            .navigationTitle("FinancialTracker")
        }
    }
}
