import Foundation
import SwiftData
import CloudKit
import CoreModel

// Bridges SwiftData save notifications to the push pipeline so callers don't have to
// enqueue changes by hand from every save path. Deletes lose their UUIDs once the row
// is gone, so the to-push set is captured at `willSave` (models still alive) and only
// flushed at `didSave` (post-commit, so a failed save enqueues nothing).
//
// Observe ONLY a UI/main context. The sync engine writes pulled remote changes to its
// own separate context; observing that would echo remote writes straight back as local
// pushes. The observed context must save on the main actor.
@MainActor
public final class SaveObserver {
    private let observed: ModelContext
    private let onCommit: ([CKSyncEngine.PendingRecordZoneChange]) -> Void
    private var captured: [CKSyncEngine.PendingRecordZoneChange] = []
    // Read from the nonisolated deinit; NotificationCenter token removal is thread-safe.
    nonisolated(unsafe) private var tokens: [NSObjectProtocol] = []

    public init(
        observing context: ModelContext,
        onCommit: @escaping ([CKSyncEngine.PendingRecordZoneChange]) -> Void
    ) {
        self.observed = context
        self.onCommit = onCommit
        let nc = NotificationCenter.default

        tokens.append(nc.addObserver(
            forName: ModelContext.willSave, object: context, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.captured = PushPipeline.pendingChanges(
                    inserted: self.observed.insertedModelsArray,
                    updated: self.observed.changedModelsArray,
                    deleted: self.observed.deletedModelsArray
                )
            }
        })

        tokens.append(nc.addObserver(
            forName: ModelContext.didSave, object: context, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let changes = self.captured
                self.captured = []
                if !changes.isEmpty { self.onCommit(changes) }
            }
        })
    }

    deinit {
        for t in tokens { NotificationCenter.default.removeObserver(t) }
    }
}
