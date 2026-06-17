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
    private let ctx: ModelContext
    private var saveObserver: SaveObserver?
    private var sendDebounce: Task<Void, Never>?
    private var isSending = false
    private var pendingResend = false
    // Conflict-resolved records carrying the server change tag, returned by the next
    // batch instead of a freshly-built (tagless) record. See sentRecordZoneChanges.
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
        self.ctx = ModelContext(modelContainer)
    }

    public func start() throws {
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase
        let saved = try? stateStore.load()
        let delegate = Delegate(owner: self)
        self.syncDelegate = delegate
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: saved,
            delegate: delegate
        )
        // Own all sends deterministically (single-flight, see sendPendingChanges) rather
        // than letting CKSyncEngine's automatic sync race our explicit sends — concurrent
        // sends of the same freshly-built record collide as "record already exists".
        configuration.automaticallySync = false
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        enqueueZoneIfNeeded(engine: engine)
        observeSaves(on: modelContainer.mainContext)
        SyncLog.log("start: engine up, observing main context")
        Task {
            let status = try? await container.accountStatus()
            SyncLog.log("accountStatus: \(String(describing: status)) (available=\(status == .available))")
        }
        // Flush anything enqueued in a prior session (restored from saved state) that
        // automatic sync never sent.
        scheduleSend()
    }

    // Installs a single save observer so UI saves push automatically. Observes the
    // main context only — the engine's own `ctx` holds pulled remote writes and must
    // not be observed, or remote changes would echo back as local pushes.
    public func observeSaves(on context: ModelContext) {
        saveObserver = SaveObserver(observing: context) { [weak self] changes in
            SyncLog.log("save observed: enqueue \(changes.count) record change(s)")
            self?.engine?.state.add(pendingRecordZoneChanges: changes)
            // CKSyncEngine's automatic sync defers heavily and may not fire for a long
            // time; nudge an explicit send so a local edit reaches iCloud promptly.
            // Debounced to coalesce a burst of saves into one push.
            self?.scheduleSend()
        }
    }

    private func scheduleSend() {
        sendDebounce?.cancel()
        sendDebounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.sendPendingChanges()
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

    // Single-flight: never run two sends at once (that races the same record into a
    // "record already exists" collision). A request arriving mid-send sets a flag so we
    // loop once more after the current send — coalescing a burst into the fewest sends.
    public func sendPendingChanges() async {
        guard let engine else { return }
        if isSending { pendingResend = true; return }
        isSending = true
        defer { isSending = false }
        var iterations = 0
        repeat {
            pendingResend = false
            SyncLog.log("send: pendingRecords=\(engine.state.pendingRecordZoneChanges.count) pendingDB=\(engine.state.pendingDatabaseChanges.count)")
            do {
                try await engine.sendChanges()
            } catch {
                lastError = error
                SyncLog.log("send error: \(error)")
            }
            iterations += 1
        } while pendingResend && iterations < 5  // cap conflict-resolution resends
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
                lastPullReport = try PullPipeline.apply(
                    modifications: mods, deletions: dels, in: ctx
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
            for f in evt.failedRecordSaves {
                resolveFailedSave(f, syncEngine: syncEngine)
            }

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

    // CKSyncEngine requires the delegate to resolve push failures. The critical one is
    // serverRecordChanged: a fresh CKRecord we build is tagless, so the server rejects it
    // as a conflict/"already exists". We merge our values onto the server's record (which
    // carries the tag) and re-enqueue — LWW: the local edit wins. Tagless edits therefore
    // take one extra round-trip; persisting CKRecord system fields per model would make
    // edits single-shot (deferred).
    private func resolveFailedSave(
        _ failed: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave,
        syncEngine: CKSyncEngine
    ) {
        let recordID = failed.record.recordID
        let ckError = failed.error
        SyncLog.log("  FAIL save \(failed.record.recordType)/\(recordID.recordName): code=\(ckError.code.rawValue)")
        switch ckError.code {
        case .serverRecordChanged:
            if let serverRecord = ckError.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                if let local = PushPipeline.buildRecord(for: recordID, in: ctx) {
                    for key in local.allKeys() { serverRecord[key] = local[key] }
                }
                resolvedRecords[recordID] = serverRecord
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
                pendingResend = true
            }
        case .zoneNotFound, .userDeletedZone:
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncZone.id))])
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            pendingResend = true
        case .unknownItem:
            break  // server has no such record; nothing to save
        case .batchRequestFailed, .serverRejectedRequest, .networkFailure,
             .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            pendingResend = true
        default:
            lastError = ckError
        }
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
