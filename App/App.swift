import SwiftUI
import SwiftData
import LocalAuthentication
import CoreModel
import CoreSync

private let iCloudContainerID = "iCloud.com.uliseis.financialtracker"

@main
struct FinancialTrackerApp: App {
    let modelContainer: ModelContainer
    @State private var syncEngine: CloudKitSyncEngine

    init() {
        let container: ModelContainer
        do {
            let schema = Schema(CoreModelSchema.allTypes)
            // DO NOT change cloudKitDatabase. SwiftData drops @Attribute(.unique) the moment
            // CloudKit mirroring is enabled, which would force a destructive migration on
            // every model. Sync to iCloud is handled out-of-band by CoreSync (CKSyncEngine).
            let config: ModelConfiguration
            #if DEBUG
            if let dev = DevStore.url {
                config = ModelConfiguration(schema: schema, url: dev, cloudKitDatabase: .none)
            } else {
                config = ModelConfiguration(
                    schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none
                )
            }
            #else
            config = ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none
            )
            #endif
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer init failed: \(error)")
        }
        self.modelContainer = container

        let store: SyncStateStore
        do {
            store = SyncStateStore(fileURL: try SyncStateStore.defaultLocation())
        } catch {
            fatalError("CoreSync state store init failed: \(error)")
        }
        let engine = CloudKitSyncEngine(
            containerIdentifier: iCloudContainerID,
            modelContainer: container,
            stateStore: store
        )
        _syncEngine = State(initialValue: engine)

        // BGTaskScheduler.register MUST be called exactly once per identifier before the
        // app finishes launching. Done here, in init, before Scene body is evaluated.
        // Skip when CloudKit is unavailable (unsigned dev build) — see CloudKitGate.
        if CloudKitGate.isAvailable {
            BackgroundSync.register(engine: engine)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(syncEngine)
                .task {
                    // CKContainer init traps without the iCloud entitlement (unsigned dev
                    // builds). Only start sync when CloudKit is actually provisioned; the app
                    // runs fully locally otherwise.
                    guard CloudKitGate.isAvailable else { return }
                    do {
                        try syncEngine.start()
                    } catch {
                        // Engine may fail to start if iCloud isn't available; the app still works
                        // locally. Log and carry on; next launch retries.
                        print("CoreSync start failed: \(error)")
                    }
                    BackgroundSync.schedule()
                }
        }
        .modelContainer(modelContainer)
    }
}

// DEBUG-only screenshot/UI-test hook: launch with UITEST_DISABLE_AUTH=1 to skip the
// biometric gate. Never compiled into release builds.
#if DEBUG
let authGateBypassed = ProcessInfo.processInfo.environment["UITEST_DISABLE_AUTH"] == "1"
// Show the locked screen without firing biometrics, so the lock UI can be captured.
let authShowLockOnly = ProcessInfo.processInfo.environment["UITEST_SHOW_LOCK"] == "1"
#else
let authGateBypassed = false
let authShowLockOnly = false
#endif

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(CloudKitSyncEngine.self) private var syncEngine
    @State private var unlocked = authGateBypassed
    @State private var authError: String?

    var body: some View {
        Group {
            if unlocked {
                RootTabView()
                    .task {
                        await syncEngine.fetchOnLaunch()
                    }
            } else {
                LockScreen(error: authError, onUnlock: authenticate)
            }
        }
        .task { if !authGateBypassed && !authShowLockOnly { authenticate() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, !authGateBypassed {
                unlocked = false
                authError = nil
            }
        }
    }

    private func authenticate() {
        let context = LAContext()
        context.localizedFallbackTitle = "Enter passcode"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authError = error?.localizedDescription ?? "Biometrics unavailable"
            return
        }
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock Odyssey Finance"
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
        GlassEffectContainer {
            VStack(spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("Odyssey Finance")
                    .font(.title2).bold()
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button("Unlock", systemImage: "faceid", action: onUnlock)
                    .buttonStyle(.glassProminent)
            }
            .padding(28)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

