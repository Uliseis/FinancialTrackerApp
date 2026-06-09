import Foundation

#if os(iOS) || os(visionOS)
import BackgroundTasks

public enum BackgroundSync {
    public static let taskIdentifier = "com.uliseis.financialtracker.refresh"

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

    private static func handle(task: BGTask, engine: CloudKitSyncEngine) {
        let work = Task { @MainActor in
            await engine.fetchOnLaunch()
            await engine.sendPendingChanges()
            schedule()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}

#else

public enum BackgroundSync {
    public static let taskIdentifier = "com.uliseis.financialtracker.refresh"

    @MainActor
    public static func register(engine: CloudKitSyncEngine) {}

    public static func schedule(earliestBeginIn seconds: TimeInterval = 3_600) {}
}

#endif
