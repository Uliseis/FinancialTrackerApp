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
        for m in deleted {
            if let uuid = uuidOf(m) {
                out.append(.deleteRecord(SyncZone.recordID(for: uuid)))
            }
        }
        return out
    }

    @MainActor
    public static func buildRecord(for recordID: CKRecord.ID, in ctx: ModelContext) -> CKRecord? {
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
