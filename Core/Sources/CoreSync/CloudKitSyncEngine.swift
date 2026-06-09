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
        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: saved,
            delegate: makeDelegate()
        )
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        enqueueZoneIfNeeded(engine: engine)
        observeSaves(on: modelContainer.mainContext)
    }

    // Installs a single save observer so UI saves push automatically. Observes the
    // main context only — the engine's own `ctx` holds pulled remote writes and must
    // not be observed, or remote changes would echo back as local pushes.
    public func observeSaves(on context: ModelContext) {
        saveObserver = SaveObserver(observing: context) { [weak self] changes in
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

    public func sendPendingChanges() async {
        guard let engine else { return }
        do {
            try await engine.sendChanges()
        } catch {
            lastError = error
        }
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

        case .sentRecordZoneChanges, .sentDatabaseChanges,
             .willFetchChanges, .willFetchRecordZoneChanges,
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
        return await PushPipeline.nextBatch(pending: changes, in: ctx)
    }

    private func enqueueZoneIfNeeded(engine: CKSyncEngine) {
        let knownZones = Set(engine.state.zoneIDsWithUnfetchedServerChanges)
        if !knownZones.contains(SyncZone.id) {
            engine.state.add(pendingDatabaseChanges: [
                .saveZone(CKRecordZone(zoneID: SyncZone.id))
            ])
        }
    }

    private func makeDelegate() -> CKSyncEngineDelegate {
        Delegate(owner: self)
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
