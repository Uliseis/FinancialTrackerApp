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
        BackgroundSync.register(engine: engine)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(syncEngine)
                .task {
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

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(CloudKitSyncEngine.self) private var syncEngine
    @State private var unlocked = false
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
        .task { authenticate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
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

