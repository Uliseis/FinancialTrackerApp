import Foundation
import SwiftData
import CloudKit
import CoreModel

public enum PushPipeline {

    @MainActor
    public static func nextBatch(
        pending: [CKSyncEngine.PendingRecordZoneChange],
        in ctx: ModelContext
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let prebuilt: [CKRecord.ID: CKRecord] = {
            var d: [CKRecord.ID: CKRecord] = [:]
            for change in pending {
                if case .saveRecord(let recordID) = change,
                   let record = buildRecord(for: recordID, in: ctx) {
                    d[recordID] = record
                }
            }
            return d
        }()
        return await CKSyncEngine.RecordZoneChangeBatch(
            pendingChanges: pending,
            recordProvider: { recordID in
                prebuilt[recordID]
            }
        )
    }

    @MainActor
    public static func prebuildRecords(
        pending: [CKSyncEngine.PendingRecordZoneChange],
        in ctx: ModelContext
    ) -> (records: [CKRecord], deletions: [CKRecord.ID]) {
        var records: [CKRecord] = []
        var deletions: [CKRecord.ID] = []
        for change in pending {
            switch change {
            case .saveRecord(let recordID):
                if let record = buildRecord(for: recordID, in: ctx) {
                    records.append(record)
                }
            case .deleteRecord(let recordID):
                deletions.append(recordID)
            @unknown default:
                continue
            }
        }
        return (records, deletions)
    }

    @MainActor
    public static func pendingChanges(
        inserted: [any PersistentModel],
        updated: [any PersistentModel],
        deleted: [any PersistentModel]
    ) -> [CKSyncEngine.PendingRecordZoneChange] {
        var out: [CKSyncEngine.PendingRecordZoneChange] = []
        for m in inserted + updated {
            if let uuid = uuidOf(m) {
                out.append(.saveRecord(SyncZone.recordID(for: uuid)))
            }
        }
        // Include cascade descendants: SwiftData deletes .cascade children during the save,
        // but they aren't in the deleted set captured at willSave. Without enqueuing their
        // deletions too, their CloudKit records survive and resurrect on the next pull.
        var deletedIDs = Set<UUID>()
        for m in deleted {
            guard let uuid = uuidOf(m) else { continue }
            for id in [uuid] + cascadeDescendantIDs(m) where deletedIDs.insert(id).inserted {
                out.append(.deleteRecord(SyncZone.recordID(for: id)))
            }
        }
        return out
    }

    // UUIDs of records deleted transitively by SwiftData .cascade rules when `m` is
    // deleted. Mirrors the @Relationship(deleteRule: .cascade) declarations on the models
    // (.nullify children survive and are not included).
    @MainActor
    static func cascadeDescendantIDs(_ m: any PersistentModel) -> [UUID] {
        if let a = m as? Account {
            return a.transactions.flatMap { [$0.id] + cascadeDescendantIDs($0) }
                + a.valuations.map(\.id)
                + a.incomingRoutes.map(\.id) + a.outgoingRoutes.map(\.id)
        }
        if let t = m as? Transaction {
            return t.mirrors.flatMap { [$0.id] + cascadeDescendantIDs($0) }
                + (t.primaryForGroup.map { [$0.id] } ?? [])
        }
        if let c = m as? CoreModel.Category {
            return c.rules.map(\.id) + c.budgets.map(\.id)
        }
        if let conn = m as? Connection {
            return conn.accounts.flatMap { [$0.id] + cascadeDescendantIDs($0) }
        }
        return []
    }

    // Builds the record to push: the current field values applied onto the persisted
    // lastKnownRecord (which carries the server change tag), so edits save as updates.
    // Keys the snapshot omits (nil'd optionals) are cleared on the base so an edit that
    // removes a value isn't masked by the server's stale value.
    @MainActor
    public static func buildRecord(for recordID: CKRecord.ID, in ctx: ModelContext) -> CKRecord? {
        guard let values = currentValues(for: recordID, in: ctx),
              let uuid = UUID(uuidString: values.recordID.recordName) else { return nil }
        let base = SyncRecordStore.lastKnownRecord(for: uuid, in: ctx)
            ?? CKRecord(recordType: values.recordType, recordID: values.recordID)
        merge(values: values, into: base)
        return base
    }

    // Copy field values onto a base record (which may carry a server change tag), clearing
    // keys the values omit so a cleared optional isn't masked by the base's stale value.
    public static func merge(values: CKRecord, into base: CKRecord) {
        let incoming = Set(values.allKeys())
        for key in base.allKeys() where !incoming.contains(key) { base[key] = nil }
        for key in values.allKeys() { base[key] = values[key] }
    }

    // The current local field values for a record (a fresh, tagless CKRecord in the sync
    // zone). Used as push values and as the local side of push-conflict resolution.
    @MainActor
    public static func currentValues(for recordID: CKRecord.ID, in ctx: ModelContext) -> CKRecord? {
        guard let uuid = UUID(uuidString: recordID.recordName) else { return nil }

        if let m = ModelSnapshots.find(transaction: uuid, in: ctx) {
            return RecordCoding.encode(ModelSnapshots.snapshot(m))
        }
        if let m = ModelSnapshots.find(account: uuid, in: ctx) {
            return RecordCoding.encode(ModelSnapshots.snapshot(m))
        }
        if let m = ModelSnapshots.find(category: uuid, in: ctx) {
            return RecordCoding.encode(ModelSnapshots.snapshot(m))
        }
        if let m = ModelSnapshots.find(fxRate: uuid, in: ctx) {
            return RecordCoding.encode(ModelSnapshots.snapshot(m))
        }
        if let m = ModelSnapshots.find(transferGroup: uuid, in: ctx) {
            return RecordCoding.encode(ModelSnapshots.snapshot(m))
        }
        if let m = ModelSnapshots.find(sharedExpenseGroup: uuid, in: ctx) {
            return RecordCoding.encode(ModelSnapshots.snapshot(m))
        }
        if let m = ModelSnapshots.find(transferRoute: uuid, in: ctx) {
            return RecordCoding.encode(ModelSnapshots.snapshot(m))
        }
        if let m = ModelSnapshots.find(categoryRule: uuid, in: ctx) {
            return RecordCoding.encode(ModelSnapshots.snapshot(m))
        }
        if let m = ModelSnapshots.find(budget: uuid, in: ctx) {
            return RecordCoding.encode(ModelSnapshots.snapshot(m))
        }
        if let m = ModelSnapshots.find(portfolioValuation: uuid, in: ctx) {
            return RecordCoding.encode(ModelSnapshots.snapshot(m))
        }
        if let m = ModelSnapshots.find(accountGroup: uuid, in: ctx) {
            return RecordCoding.encode(ModelSnapshots.snapshot(m))
        }
        if let m = ModelSnapshots.find(accountSpace: uuid, in: ctx) {
            return RecordCoding.encode(ModelSnapshots.snapshot(m))
        }
        if let m = ModelSnapshots.find(connection: uuid, in: ctx) {
            return RecordCoding.encode(ModelSnapshots.snapshot(m))
        }
        if let m = ModelSnapshots.find(syncRun: uuid, in: ctx) {
            return RecordCoding.encode(ModelSnapshots.snapshot(m))
        }
        return nil
    }

    @MainActor
    private static func uuidOf(_ m: any PersistentModel) -> UUID? {
        if let x = m as? Transaction { return x.id }
        if let x = m as? Account { return x.id }
        if let x = m as? CoreModel.Category { return x.id }
        if let x = m as? FxRate { return x.id }
        if let x = m as? TransferGroup { return x.id }
        if let x = m as? SharedExpenseGroup { return x.id }
        if let x = m as? TransferRoute { return x.id }
        if let x = m as? CategoryRule { return x.id }
        if let x = m as? Budget { return x.id }
        if let x = m as? PortfolioValuation { return x.id }
        if let x = m as? AccountGroup { return x.id }
        if let x = m as? AccountSpace { return x.id }
        if let x = m as? Connection { return x.id }
        if let x = m as? SyncRun { return x.id }
        return nil
    }
}
