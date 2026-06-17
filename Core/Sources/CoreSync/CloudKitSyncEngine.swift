import Foundation
import CloudKit
import SwiftData
import CoreModel
import Observation

@MainActor
@Observable
public final class CloudKitSyncEngine {
    public let containerIdentifier: String
    public let modelContainer: ModelContainer
    public let stateStore: SyncStateStore

    private var engine: CKSyncEngine?
    private var saveObserver: SaveObserver?
    // Conflict-resolved records carrying the server change tag, returned by the next
    // batch instead of a freshly-built record. See resolveFailedSave.
    private var resolvedRecords: [CKRecord.ID: CKRecord] = [:]
    // CKSyncEngine holds its delegate weakly. This strong reference keeps it alive —
    // without it the delegate deallocs right after start(), so nextRecordZoneChangeBatch
    // is never called (records never push) and no events are delivered.
    private var syncDelegate: (any CKSyncEngineDelegate)?

    public private(set) var lastPullReport: PullReport?
    public private(set) var lastError: Error?

    public init(
        containerIdentifier: String,
        modelContainer: ModelContainer,
        stateStore: SyncStateStore
    ) {
        self.containerIdentifier = containerIdentifier
        self.modelContainer = modelContainer
        self.stateStore = stateStore
    }

    // A fresh context per sync operation, so push reads see the latest committed values
    // (a long-lived context can serve stale materialized copies of UI-edited rows) and
    // pulls don't accumulate state. Never the observed main context.
    private func makeContext() -> ModelContext { ModelContext(modelContainer) }

    public func start() throws {
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase
        let saved = try? stateStore.load()
        let delegate = Delegate(owner: self)
        self.syncDelegate = delegate
        // automaticallySync stays at its default (true), per Apple's CKSyncEngine sample:
        // the engine schedules sends/fetches itself. Records now carry the server change
        // tag (lastKnownRecord), so edits save as updates — no duplicate-insert race.
        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: saved,
            delegate: delegate
        )
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        enqueueZoneIfNeeded(engine: engine)
        observeSaves(on: modelContainer.mainContext)
        SyncLog.log("start: engine up, observing main context")
        Task {
            let status = try? await container.accountStatus()
            SyncLog.log("accountStatus: \(String(describing: status)) (available=\(status == .available))")
        }
    }

    // Installs a single save observer so UI saves push automatically. Observes the
    // main context only — the engine's own `ctx` holds pulled remote writes and must
    // not be observed, or remote changes would echo back as local pushes.
    public func observeSaves(on context: ModelContext) {
        saveObserver = SaveObserver(observing: context) { [weak self] changes in
            SyncLog.log("save observed: enqueue \(changes.count) record change(s)")
            // Enqueue only; CKSyncEngine's automatic sync schedules the send.
            self?.engine?.state.add(pendingRecordZoneChanges: changes)
        }
    }

    public func fetchOnLaunch() async {
        guard let engine else { return }
        do {
            try await engine.fetchChanges()
        } catch {
            lastError = error
        }
    }

    // Explicit flush, used by the background task. Normal UI saves push via automatic sync.
    public func sendPendingChanges() async {
        guard let engine else { return }
        SyncLog.log("send: pendingRecords=\(engine.state.pendingRecordZoneChanges.count) pendingDB=\(engine.state.pendingDatabaseChanges.count)")
        do {
            try await engine.sendChanges()
        } catch {
            lastError = error
            SyncLog.log("send error: \(error)")
        }
    }

    // One-shot: enqueue every existing local row for an initial push. Normal operation
    // pushes via SaveObserver, but a store populated out-of-band (the data cutover copies a
    // store file straight into the app container) fires no save events, so its rows would
    // never push. Trigger this exactly once on the cutover launch. Idempotent if repeated:
    // CKSyncEngine dedupes pending changes by recordID and the lastKnownRecord tag makes a
    // re-send a no-op update.
    public func seedInitialPush() {
        guard let engine else { return }
        let pending = PushPipeline.allLocalSaves(in: makeContext())
        guard !pending.isEmpty else {
            SyncLog.log("seed: store empty, nothing to enqueue")
            return
        }
        engine.state.add(pendingRecordZoneChanges: pending)
        SyncLog.log("seed: enqueued \(pending.count) record(s) for initial push")
    }

    public func enqueueLocalChanges(
        inserted: [any PersistentModel],
        updated: [any PersistentModel],
        deleted: [any PersistentModel]
    ) {
        guard let engine else { return }
        let pending = PushPipeline.pendingChanges(
            inserted: inserted, updated: updated, deleted: deleted
        )
        engine.state.add(pendingRecordZoneChanges: pending)
    }

    // MARK: - delegate handling

    func handle(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let evt):
            try? stateStore.save(evt.stateSerialization)

        case .fetchedRecordZoneChanges(let evt):
            let mods = evt.modifications.map(\.record)
            let dels = evt.deletions.map {
                PullDeletion(recordID: $0.recordID, recordType: $0.recordType)
            }
            do {
                // PullPipeline.apply saves the fresh context, which posts ModelContext.didSave;
                // the UI's reloadOnModelChange observes that globally and refreshes.
                lastPullReport = try PullPipeline.apply(
                    modifications: mods, deletions: dels, in: makeContext()
                )
            } catch {
                lastError = error
            }

        case .fetchedDatabaseChanges(let evt):
            // Re-enqueue our zone if the server reports it was deleted.
            let deletedZoneIDs = evt.deletions.map(\.zoneID)
            if deletedZoneIDs.contains(SyncZone.id) {
                syncEngine.state.add(pendingDatabaseChanges: [
                    .saveZone(CKRecordZone(zoneID: SyncZone.id))
                ])
            }

        case .sentRecordZoneChanges(let evt):
            SyncLog.log("sent: saved=\(evt.savedRecords.count) deleted=\(evt.deletedRecordIDs.count) failedSaves=\(evt.failedRecordSaves.count) failedDeletes=\(evt.failedRecordDeletes.count)")
            let ctx = makeContext()
            // Cache each saved record's system fields (the change tag) so the next edit
            // saves as an update, not a duplicate insert — the lastKnownRecord pattern.
            for saved in evt.savedRecords {
                SyncRecordStore.store(saved, in: ctx)
            }
            for deletedID in evt.deletedRecordIDs {
                if let uuid = UUID(uuidString: deletedID.recordName) {
                    SyncRecordStore.remove(uuid, in: ctx)
                }
            }
            for f in evt.failedRecordSaves {
                resolveFailedSave(f, syncEngine: syncEngine, in: ctx)
            }
            try? ctx.save()

        case .sentDatabaseChanges(let evt):
            SyncLog.log("sentDB: savedZones=\(evt.savedZones.count) failedZoneSaves=\(evt.failedZoneSaves.count)")
            for f in evt.failedZoneSaves {
                SyncLog.log("  FAIL zone \(f.zone.zoneID.zoneName): \(f.error)")
            }

        case .willFetchChanges, .willFetchRecordZoneChanges,
             .didFetchChanges, .didFetchRecordZoneChanges,
             .willSendChanges, .didSendChanges,
             .accountChange:
            // Routine progress events; nothing to do for v1.
            break

        @unknown default:
            break
        }
    }

    func nextBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        let ctx = makeContext()
        // Prefer a conflict-resolved record (carries the server change tag) over a
        // freshly-built one, which is tagless and only valid as a first insert.
        var building: [CKRecord.ID: CKRecord] = [:]
        for change in changes {
            if case .saveRecord(let rid) = change {
                if let record = resolvedRecords[rid] ?? PushPipeline.buildRecord(for: rid, in: ctx) {
                    building[rid] = record
                }
            }
        }
        let prebuilt = building
        let batch = await CKSyncEngine.RecordZoneChangeBatch(
            pendingChanges: changes,
            recordProvider: { prebuilt[$0] }
        )
        for rid in prebuilt.keys { resolvedRecords[rid] = nil }
        SyncLog.log("nextBatch: pending=\(changes.count) built=\(batch?.recordsToSave.count ?? 0)")
        return batch
    }

    // Resolve push failures (CKSyncEngine requires the delegate to do this). For
    // serverRecordChanged we apply the locked conflict policy — LWW, except a manual
    // categorySource always wins for Transaction — via ConflictResolver, then either
    // re-push the winning values onto the server's record (carrying its change tag) or
    // accept the server's version locally and drop the push.
    private func resolveFailedSave(
        _ failed: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave,
        syncEngine: CKSyncEngine,
        in ctx: ModelContext
    ) {
        let recordID = failed.record.recordID
        let ckError = failed.error
        SyncLog.log("  FAIL save \(failed.record.recordType)/\(recordID.recordName): code=\(ckError.code.rawValue)")
        switch ckError.code {
        case .serverRecordChanged:
            guard let serverRecord = ckError.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord else {
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return
            }
            if let winner = pushWinner(for: recordID, serverRecord: serverRecord, in: ctx) {
                // Our side (or a merge) wins: push the winning values onto the server's
                // record so the save carries the correct change tag.
                PushPipeline.merge(values: winner, into: serverRecord)
                SyncRecordStore.store(serverRecord, in: ctx)
                resolvedRecords[recordID] = serverRecord
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            } else {
                // Server wins: apply its version locally, cache its tag, drop our push.
                _ = try? PullPipeline.apply(modifications: [serverRecord], deletions: [], in: ctx)
                SyncRecordStore.store(serverRecord, in: ctx)
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            }
        case .zoneNotFound, .userDeletedZone:
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncZone.id))])
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        case .unknownItem:
            if let uuid = UUID(uuidString: recordID.recordName) {
                SyncRecordStore.remove(uuid, in: ctx)  // server has no such record
            }
            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
        case .batchRequestFailed, .serverRejectedRequest, .networkFailure,
             .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])  // transient; retry
        default:
            lastError = ckError
        }
    }

    // The values to push when our local record conflicts with the server's, or nil to
    // accept the server's version. Transaction uses the manual-aware resolver; everything
    // else is pure last-writer-wins on the clock.
    private func pushWinner(for recordID: CKRecord.ID, serverRecord: CKRecord, in ctx: ModelContext) -> CKRecord? {
        guard let localValues = PushPipeline.currentValues(for: recordID, in: ctx) else {
            return nil  // local record is gone — accept the server's version
        }
        if serverRecord.recordType == RecordType.transaction,
           let local = try? RecordCoding.decodeTransaction(localValues),
           let remote = try? RecordCoding.decodeTransaction(serverRecord) {
            switch ConflictResolver.resolveTransaction(local: local, remote: remote) {
            case .keepLocal: return localValues
            case .applyRemote: return nil
            case .merge(let merged): return RecordCoding.encode(merged)
            }
        }
        let localClock = localValues["clock"] as? Date ?? .distantPast
        let remoteClock = serverRecord["clock"] as? Date ?? .distantPast
        return localClock > remoteClock ? localValues : nil
    }

    private func enqueueZoneIfNeeded(engine: CKSyncEngine) {
        let knownZones = Set(engine.state.zoneIDsWithUnfetchedServerChanges)
        if !knownZones.contains(SyncZone.id) {
            engine.state.add(pendingDatabaseChanges: [
                .saveZone(CKRecordZone(zoneID: SyncZone.id))
            ])
        }
    }

    private final class Delegate: NSObject, CKSyncEngineDelegate, @unchecked Sendable {
        weak var owner: CloudKitSyncEngine?

        init(owner: CloudKitSyncEngine) {
            self.owner = owner
            super.init()
        }

        func handleEvent(
            _ event: CKSyncEngine.Event,
            syncEngine: CKSyncEngine
        ) async {
            guard let owner else { return }
            await owner.handle(event, syncEngine: syncEngine)
        }

        func nextRecordZoneChangeBatch(
            _ context: CKSyncEngine.SendChangesContext,
            syncEngine: CKSyncEngine
        ) async -> CKSyncEngine.RecordZoneChangeBatch? {
            guard let owner else { return nil }
            return await owner.nextBatch(context, syncEngine: syncEngine)
        }
    }
}
