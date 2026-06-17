import Foundation
import CloudKit
import SwiftData
import CoreModel

// Persists each synced record's CKRecord *system fields* (the "lastKnownRecord": recordID,
// zone, and server change tag — NOT the data fields) so the push layer can reuse the change
// tag and save edits as updates instead of duplicate inserts. This is the pattern from
// Apple's CKSyncEngine sample (`setLastKnownRecordIfNewer` / `lastKnownRecord`), adapted to
// our 14-type snapshot model via one local-only side table keyed by record UUID.
@MainActor
enum SyncRecordStore {
    static func lastKnownRecord(for id: UUID, in ctx: ModelContext) -> CKRecord? {
        guard let meta = find(id, in: ctx) else { return nil }
        return decode(meta.systemFields)
    }

    // Cache a record's system fields after a successful save or a server-record merge.
    static func store(_ record: CKRecord, in ctx: ModelContext) {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return }
        let data = encodeSystemFields(record)
        if let meta = find(id, in: ctx) {
            meta.systemFields = data
        } else {
            ctx.insert(SyncRecordMeta(id: id, systemFields: data))
        }
    }

    static func remove(_ id: UUID, in ctx: ModelContext) {
        if let meta = find(id, in: ctx) { ctx.delete(meta) }
    }

    private static func find(_ id: UUID, in ctx: ModelContext) -> SyncRecordMeta? {
        try? ctx.fetch(FetchDescriptor<SyncRecordMeta>(
            predicate: #Predicate { $0.id == id }
        )).first
    }

    static func encodeSystemFields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func decode(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        let record = CKRecord(coder: coder)
        coder.finishDecoding()
        return record
    }
}
