import XCTest
import Foundation
import SwiftData
import CloudKit
@testable import CoreModel
@testable import CoreSync

@MainActor
final class PushPipelineTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema(CoreModelSchema.allTypes)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    func test_buildRecord_findsAndEncodesEachType() throws {
        let ctx = try makeContext()
        let conn = ModelSnapshots.insertOrUpdate(Build.connection(), in: ctx)
        let group = ModelSnapshots.insertOrUpdate(Build.accountGroup(), in: ctx)
        let space = ModelSnapshots.insertOrUpdate(Build.accountSpace(), in: ctx)
        let acc = ModelSnapshots.insertOrUpdate(
            AccountSnapshot(
                id: UUID(),
                connectionId: conn.id, groupId: group.id, spaceId: space.id,
                externalId: "EXT", type: .bank,
                institution: "B", name: "N", currency: "EUR",
                archived: false, excluded: false,
                createdAt: Build.epoch, clock: Build.epoch
            ),
            in: ctx
        )
        let cat = ModelSnapshots.insertOrUpdate(Build.category(), in: ctx)
        let tx = ModelSnapshots.insertOrUpdate(
            Build.transaction(accountId: acc.id, categoryId: cat.id),
            in: ctx
        )
        try ctx.save()

        XCTAssertEqual(
            PushPipeline.buildRecord(for: SyncZone.recordID(for: conn.id), in: ctx)?.recordType,
            RecordType.connection
        )
        XCTAssertEqual(
            PushPipeline.buildRecord(for: SyncZone.recordID(for: acc.id), in: ctx)?.recordType,
            RecordType.account
        )
        XCTAssertEqual(
            PushPipeline.buildRecord(for: SyncZone.recordID(for: tx.id), in: ctx)?.recordType,
            RecordType.transaction
        )
        XCTAssertEqual(
            PushPipeline.buildRecord(for: SyncZone.recordID(for: cat.id), in: ctx)?.recordType,
            RecordType.category
        )
    }

    func test_buildRecord_unknownUUID_returnsNil() throws {
        let ctx = try makeContext()
        let result = PushPipeline.buildRecord(for: SyncZone.recordID(for: UUID()), in: ctx)
        XCTAssertNil(result)
    }

    func test_buildRecord_nonUUIDRecordName_returnsNil() throws {
        let ctx = try makeContext()
        let invalidID = CKRecord.ID(recordName: "not-a-uuid", zoneID: SyncZone.id)
        XCTAssertNil(PushPipeline.buildRecord(for: invalidID, in: ctx))
    }

    func test_pendingChanges_translatesInsertsToSaveRecords() throws {
        let ctx = try makeContext()
        let conn = ModelSnapshots.insertOrUpdate(Build.connection(), in: ctx)
        let acc = ModelSnapshots.insertOrUpdate(
            AccountSnapshot(
                id: UUID(), externalId: "EXT", type: .bank,
                institution: "B", name: "N", currency: "EUR",
                archived: false, excluded: false,
                createdAt: Build.epoch, clock: Build.epoch
            ),
            in: ctx
        )
        try ctx.save()

        let changes = PushPipeline.pendingChanges(
            inserted: [conn, acc], updated: [], deleted: []
        )
        XCTAssertEqual(changes.count, 2)
        let connSave = changes.first { change in
            if case .saveRecord(let id) = change, id.recordName == conn.id.uuidString { return true }
            return false
        }
        let accSave = changes.first { change in
            if case .saveRecord(let id) = change, id.recordName == acc.id.uuidString { return true }
            return false
        }
        XCTAssertNotNil(connSave)
        XCTAssertNotNil(accSave)
    }

    func test_allLocalSaves_enqueuesEveryRowAsSave() throws {
        let ctx = try makeContext()
        let conn = ModelSnapshots.insertOrUpdate(Build.connection(), in: ctx)
        let group = ModelSnapshots.insertOrUpdate(Build.accountGroup(), in: ctx)
        let space = ModelSnapshots.insertOrUpdate(Build.accountSpace(), in: ctx)
        let acc = ModelSnapshots.insertOrUpdate(
            AccountSnapshot(
                id: UUID(),
                connectionId: conn.id, groupId: group.id, spaceId: space.id,
                externalId: "EXT", type: .bank,
                institution: "B", name: "N", currency: "EUR",
                archived: false, excluded: false,
                createdAt: Build.epoch, clock: Build.epoch
            ),
            in: ctx
        )
        let cat = ModelSnapshots.insertOrUpdate(Build.category(), in: ctx)
        let tx = ModelSnapshots.insertOrUpdate(
            Build.transaction(accountId: acc.id, categoryId: cat.id), in: ctx
        )
        try ctx.save()

        let changes = PushPipeline.allLocalSaves(in: ctx)
        let savedNames = Set(changes.compactMap { change -> String? in
            if case .saveRecord(let id) = change { return id.recordName }
            return nil
        })
        // Every inserted row is enqueued, and all are saves (no stray deletes).
        XCTAssertEqual(changes.count, 6)
        XCTAssertEqual(savedNames.count, 6)
        for id in [conn.id, group.id, space.id, acc.id, cat.id, tx.id] {
            XCTAssertTrue(savedNames.contains(id.uuidString), "missing \(id)")
        }
    }

    func test_allLocalSaves_emptyStore_returnsEmpty() throws {
        let ctx = try makeContext()
        XCTAssertTrue(PushPipeline.allLocalSaves(in: ctx).isEmpty)
    }

    func test_pendingChanges_translatesDeletes() throws {
        let ctx = try makeContext()
        let conn = ModelSnapshots.insertOrUpdate(Build.connection(), in: ctx)
        try ctx.save()

        let changes = PushPipeline.pendingChanges(
            inserted: [], updated: [], deleted: [conn]
        )
        XCTAssertEqual(changes.count, 1)
        if case .deleteRecord(let id) = changes[0] {
            XCTAssertEqual(id.recordName, conn.id.uuidString)
        } else {
            XCTFail("expected .deleteRecord, got \(changes[0])")
        }
    }

    func test_prebuildRecords_splitsSavesAndDeletes() throws {
        let ctx = try makeContext()
        let conn = ModelSnapshots.insertOrUpdate(Build.connection(), in: ctx)
        try ctx.save()

        let saveChange = CKSyncEngine.PendingRecordZoneChange.saveRecord(SyncZone.recordID(for: conn.id))
        let deleteChange = CKSyncEngine.PendingRecordZoneChange.deleteRecord(SyncZone.recordID(for: UUID()))
        let (records, deletions) = PushPipeline.prebuildRecords(
            pending: [saveChange, deleteChange], in: ctx
        )
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.recordType, RecordType.connection)
        XCTAssertEqual(deletions.count, 1)
    }

    func test_roundTrip_pushThenPullProducesEquivalentLocal() throws {
        let ctxA = try makeContext()
        let ctxB = try makeContext()
        let snap = Build.connection(updatedAt: Build.later)
        let conn = ModelSnapshots.insertOrUpdate(snap, in: ctxA)
        try ctxA.save()

        let record = PushPipeline.buildRecord(for: SyncZone.recordID(for: conn.id), in: ctxA)
        XCTAssertNotNil(record)
        let report = try PullPipeline.apply(
            modifications: [record!], deletions: [], in: ctxB
        )
        XCTAssertEqual(report.inserted, 1)
        let mirrored = ModelSnapshots.find(connection: conn.id, in: ctxB)
        XCTAssertEqual(mirrored?.connector, snap.connector)
        XCTAssertEqual(mirrored?.institutionId, snap.institutionId)
        XCTAssertEqual(mirrored?.status, snap.status)
    }

    // merge must clear keys the values omit, so an edit that removes an optional isn't
    // masked by the server record's stale value (conflict-path nil-clearing).
    func test_merge_clearsKeysAbsentFromValues() {
        let rid = SyncZone.recordID(for: UUID())
        let base = CKRecord(recordType: RecordType.account, recordID: rid)
        base["iban"] = "ES123" as CKRecordValue
        base["name"] = "Old" as CKRecordValue
        let values = CKRecord(recordType: RecordType.account, recordID: rid)
        values["name"] = "New" as CKRecordValue
        PushPipeline.merge(values: values, into: base)
        XCTAssertEqual(base["name"] as? String, "New")
        XCTAssertNil(base["iban"], "a key absent from values must be cleared on the base")
    }

    // Deleting an Account must enqueue deletions for its cascade-deleted transactions too,
    // or those CloudKit records survive and resurrect on the next pull.
    func test_pendingChanges_enqueuesCascadeDeletedChildren() throws {
        let ctx = try makeContext()
        let acc = ModelSnapshots.insertOrUpdate(Build.account(), in: ctx)
        let tx1 = ModelSnapshots.insertOrUpdate(Build.transaction(accountId: acc.id), in: ctx)
        let tx2 = ModelSnapshots.insertOrUpdate(Build.transaction(accountId: acc.id), in: ctx)
        try ctx.save()

        let changes = PushPipeline.pendingChanges(inserted: [], updated: [], deleted: [acc])
        let deletedNames: [String] = changes.compactMap {
            if case .deleteRecord(let rid) = $0 { return rid.recordName } else { return nil }
        }
        XCTAssertTrue(deletedNames.contains(acc.id.uuidString))
        XCTAssertTrue(deletedNames.contains(tx1.id.uuidString), "cascade child tx1 must be enqueued for deletion")
        XCTAssertTrue(deletedNames.contains(tx2.id.uuidString), "cascade child tx2 must be enqueued for deletion")
    }

    // System fields (recordID + zone + change tag) round-trip through SyncRecordStore so
    // buildRecord can reuse the change tag.
    func test_syncRecordStore_roundTripsSystemFields() throws {
        let ctx = try makeContext()
        let id = UUID()
        let rid = SyncZone.recordID(for: id)
        SyncRecordStore.store(CKRecord(recordType: RecordType.account, recordID: rid), in: ctx)
        try ctx.save()
        let loaded = SyncRecordStore.lastKnownRecord(for: id, in: ctx)
        XCTAssertEqual(loaded?.recordID, rid)
        XCTAssertEqual(loaded?.recordID.zoneID, SyncZone.id)
    }
}
