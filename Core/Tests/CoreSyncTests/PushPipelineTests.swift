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
}
