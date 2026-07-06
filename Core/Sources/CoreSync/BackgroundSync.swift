import Foundation

#if os(iOS) || os(visionOS)
import BackgroundTasks
import SwiftData
import CoreLogic
import CoreIntegrations

public enum BackgroundSync {
    public static let taskIdentifier = "com.uliseis.odysseyfinance.refresh"

    @MainActor
    public static func register(engine: CloudKitSyncEngine) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            handle(task: task, engine: engine)
        }
    }

    public static func schedule(earliestBeginIn seconds: TimeInterval = 3_600) {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: seconds)
        request.requiresNetworkConnectivity = true
        try? BGTaskScheduler.shared.submit(request)
    }

    // BGTask is non-Sendable but its methods are safe to call across threads; carry it
    // over the actor hop explicitly. setTaskCompleted is reported from a single MainActor
    // site (exactly once); expirationHandler captures only the Sendable work handle.
    private struct TaskBox: @unchecked Sendable { let task: BGTask }

    private static func handle(task: BGTask, engine: CloudKitSyncEngine) {
        let box = TaskBox(task: task)
        let work = Task { @MainActor in
            await syncEnableBanking(engine.modelContainer)
            await engine.fetchOnLaunch()
            await engine.sendPendingChanges()
            schedule()
            box.task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }

    // Pull bank transactions before the CloudKit push so new ones ride out the same run.
    // Writes to mainContext → SaveObserver enqueues the inserts for push. Dedupe is on
    // (accountId, externalId) in EBSync, so replays insert nothing.
    // ponytail: try? skips silently when the key is absent or unreadable (device locked,
    // AccessibleWhenUnlocked) — it just syncs on the next unlocked run.
    @MainActor
    private static func syncEnableBanking(_ container: ModelContainer) async {
        guard let signer = try? EBKeychain().loadSigner() else { return }
        _ = await CoreLogic.EBSync.syncAll(api: EBClient(tokenProvider: signer), in: container.mainContext)
    }
}

#else

public enum BackgroundSync {
    public static let taskIdentifier = "com.uliseis.odysseyfinance.refresh"

    @MainActor
    public static func register(engine: CloudKitSyncEngine) {}

    public static func schedule(earliestBeginIn seconds: TimeInterval = 3_600) {}
}

#endif
