import XCTest
import Foundation
import SwiftData
import CloudKit
@testable import CoreModel
@testable import CoreLogic
@testable import CoreSync

@MainActor
final class PullPipelineTests: XCTestCase {
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

    func test_insertNew_recordsArrive() throws {
        let ctx = try makeContext()
        let snap = Build.connection(updatedAt: Build.epoch)
        let record = RecordCoding.encode(snap)
        let report = try PullPipeline.apply(
            modifications: [record], deletions: [], in: ctx
        )
        XCTAssertEqual(report.inserted, 1)
        XCTAssertNotNil(ModelSnapshots.find(connection: snap.id, in: ctx))
    }

    func test_pull_cachesSystemFieldsTag_forMaterializedRecord() throws {
        let ctx = try makeContext()
        let snap = Build.connection(updatedAt: Build.epoch)
        XCTAssertNil(SyncRecordStore.lastKnownRecord(for: snap.id, in: ctx))

        _ = try PullPipeline.apply(
            modifications: [RecordCoding.encode(snap)], deletions: [], in: ctx
        )
        // A pulled record now has its lastKnownRecord cached, so a later edit pushes as an
        // update rather than a tagless insert.
        let cached = SyncRecordStore.lastKnownRecord(for: snap.id, in: ctx)
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.recordID.recordName, snap.id.uuidString)
    }

    func test_pull_skipsTagCache_forUndecodableRecord() throws {
        let ctx = try makeContext()
        // Known type but no fields → fails to decode → not materialized, so no tag cached.
        let bogus = CKRecord(
            recordType: RecordType.connection,
            recordID: SyncZone.recordID(for: UUID())
        )
        let report = try PullPipeline.apply(modifications: [bogus], deletions: [], in: ctx)
        XCTAssertEqual(report.skippedDecodeError, 1)
        XCTAssertNil(SyncRecordStore.lastKnownRecord(
            for: UUID(uuidString: bogus.recordID.recordName)!, in: ctx
        ))
    }

    func test_pullDeletion_removesCachedTag() throws {
        let ctx = try makeContext()
        let snap = Build.connection(updatedAt: Build.epoch)
        _ = try PullPipeline.apply(
            modifications: [RecordCoding.encode(snap)], deletions: [], in: ctx
        )
        XCTAssertNotNil(SyncRecordStore.lastKnownRecord(for: snap.id, in: ctx))

        let deletion = PullDeletion(
            recordID: SyncZone.recordID(for: snap.id),
            recordType: RecordType.connection
        )
        _ = try PullPipeline.apply(modifications: [], deletions: [deletion], in: ctx)
        XCTAssertNil(SyncRecordStore.lastKnownRecord(for: snap.id, in: ctx))
        XCTAssertNil(ModelSnapshots.find(connection: snap.id, in: ctx))
    }

    func test_updateExisting_remoteNewer_appliesRemote() throws {
        let ctx = try makeContext()
        let original = Build.connection(updatedAt: Build.epoch)
        _ = ModelSnapshots.insertOrUpdate(original, in: ctx)
        try ctx.save()

        let updated = ConnectionSnapshot(
            id: original.id, connector: .trading212,
            institutionId: "NEW_INST", institutionName: "New Name",
            status: .active,
            createdAt: original.createdAt, updatedAt: Build.later
        )
        let record = RecordCoding.encode(updated)
        let report = try PullPipeline.apply(
            modifications: [record], deletions: [], in: ctx
        )
        XCTAssertEqual(report.updatedRemote, 1)

        let local = ModelSnapshots.find(connection: original.id, in: ctx)
        XCTAssertEqual(local?.connector, .trading212)
        XCTAssertEqual(local?.institutionId, "NEW_INST")
    }

    func test_updateExisting_localNewer_keepsLocal() throws {
        let ctx = try makeContext()
        let local = Build.connection(updatedAt: Build.later)
        _ = ModelSnapshots.insertOrUpdate(local, in: ctx)
        try ctx.save()

        let staleRemote = ConnectionSnapshot(
            id: local.id, connector: .revolutx,
            institutionId: "STALE", institutionName: nil,
            status: .expired,
            createdAt: local.createdAt, updatedAt: Build.epoch
        )
        let record = RecordCoding.encode(staleRemote)
        let report = try PullPipeline.apply(
            modifications: [record], deletions: [], in: ctx
        )
        XCTAssertEqual(report.keptLocal, 1)

        let after = ModelSnapshots.find(connection: local.id, in: ctx)
        XCTAssertEqual(after?.connector, local.connector)
    }

    func test_transaction_localManualOverridesRemoteCategory_merged() throws {
        let ctx = try makeContext()
        let acc = ModelSnapshots.insertOrUpdate(
            AccountSnapshot(
                id: UUID(), externalId: "EXT", type: .bank,
                institution: "B", name: "N", currency: "EUR",
                archived: false, excluded: false,
                createdAt: Build.epoch, clock: Build.epoch
            ),
            in: ctx
        )
        let localCat = ModelSnapshots.insertOrUpdate(Build.category(), in: ctx)
        let remoteCat = ModelSnapshots.insertOrUpdate(Build.category(), in: ctx)

        let txId = UUID()
        let localSnap = Build.transaction(
            id: txId, accountId: acc.id,
            categoryId: localCat.id, categorySource: .manual,
            clock: Build.epoch
        )
        _ = ModelSnapshots.insertOrUpdate(localSnap, in: ctx)
        try ctx.save()

        let remoteSnap = Build.transaction(
            id: txId, accountId: acc.id,
            categoryId: remoteCat.id, categorySource: .rule,
            clock: Build.later
        )
        let record = RecordCoding.encode(remoteSnap)
        let report = try PullPipeline.apply(
            modifications: [record], deletions: [], in: ctx
        )
        XCTAssertEqual(report.merged, 1)

        let after = ModelSnapshots.find(transaction: txId, in: ctx)
        XCTAssertEqual(after?.category?.id, localCat.id, "local manual category survives")
        XCTAssertEqual(after?.categorySource, .manual)
    }

    func test_transaction_compositeDedupe_incomingOlderWins() throws {
        let ctx = try makeContext()
        let acc = ModelSnapshots.insertOrUpdate(
            AccountSnapshot(
                id: UUID(), externalId: "ACC", type: .bank,
                institution: "B", name: "N", currency: "EUR",
                archived: false, excluded: false,
                createdAt: Build.epoch, clock: Build.epoch
            ),
            in: ctx
        )

        let staleLocal = Build.transaction(
            id: UUID(), accountId: acc.id, externalId: "DUP_EXT",
            createdAt: Build.later
        )
        _ = ModelSnapshots.insertOrUpdate(staleLocal, in: ctx)
        try ctx.save()

        let canonicalIncoming = Build.transaction(
            id: UUID(), accountId: acc.id, externalId: "DUP_EXT",
            createdAt: Build.epoch
        )
        let record = RecordCoding.encode(canonicalIncoming)
        let report = try PullPipeline.apply(
            modifications: [record], deletions: [], in: ctx
        )

        XCTAssertEqual(report.duplicatesResolved, 1)
        XCTAssertEqual(report.inserted, 1)
        XCTAssertNotNil(ModelSnapshots.find(transaction: canonicalIncoming.id, in: ctx))
        XCTAssertNil(ModelSnapshots.find(transaction: staleLocal.id, in: ctx))
    }

    func test_transaction_compositeDedupe_existingWins_incomingDropped() throws {
        let ctx = try makeContext()
        let acc = ModelSnapshots.insertOrUpdate(
            AccountSnapshot(
                id: UUID(), externalId: "ACC", type: .bank,
                institution: "B", name: "N", currency: "EUR",
                archived: false, excluded: false,
                createdAt: Build.epoch, clock: Build.epoch
            ),
            in: ctx
        )

        let canonicalLocal = Build.transaction(
            id: UUID(), accountId: acc.id, externalId: "DUP_EXT",
            createdAt: Build.epoch
        )
        _ = ModelSnapshots.insertOrUpdate(canonicalLocal, in: ctx)
        try ctx.save()

        let staleIncoming = Build.transaction(
            id: UUID(), accountId: acc.id, externalId: "DUP_EXT",
            createdAt: Build.later
        )
        let record = RecordCoding.encode(staleIncoming)
        let report = try PullPipeline.apply(
            modifications: [record], deletions: [], in: ctx
        )

        XCTAssertEqual(report.duplicatesResolved, 1)
        XCTAssertEqual(report.inserted, 0)
        XCTAssertNotNil(ModelSnapshots.find(transaction: canonicalLocal.id, in: ctx))
        XCTAssertNil(ModelSnapshots.find(transaction: staleIncoming.id, in: ctx))
    }

    func test_fxRate_compositeDedupe() throws {
        let ctx = try makeContext()
        let date = Build.epoch
        let canonicalLocal = Build.fxRate(
            id: UUID(), currency: "USD", date: date,
            createdAt: Build.epoch
        )
        _ = ModelSnapshots.insertOrUpdate(canonicalLocal, in: ctx)
        try ctx.save()

        let staleIncoming = Build.fxRate(
            id: UUID(), currency: "USD", date: date,
            createdAt: Build.later
        )
        let record = RecordCoding.encode(staleIncoming)
        let report = try PullPipeline.apply(
            modifications: [record], deletions: [], in: ctx
        )

        XCTAssertEqual(report.duplicatesResolved, 1)
        XCTAssertEqual(report.inserted, 0)
        XCTAssertNotNil(ModelSnapshots.find(fxRate: canonicalLocal.id, in: ctx))
    }

    func test_dependencyOrder_accountInsertedBeforeTransaction() throws {
        let ctx = try makeContext()
        let acc = AccountSnapshot(
            id: UUID(), externalId: "EXT", type: .bank,
            institution: "B", name: "N", currency: "EUR",
            archived: false, excluded: false,
            createdAt: Build.epoch, clock: Build.epoch
        )
        let tx = Build.transaction(accountId: acc.id)
        // Note: passing transaction BEFORE account in the modifications array.
        let records = [RecordCoding.encode(tx), RecordCoding.encode(acc)]
        let report = try PullPipeline.apply(
            modifications: records, deletions: [], in: ctx
        )
        XCTAssertEqual(report.inserted, 2)

        let txLocal = ModelSnapshots.find(transaction: tx.id, in: ctx)
        XCTAssertEqual(txLocal?.account?.id, acc.id, "tx.account linked despite arrival order")
    }

    func test_sharedExpenseGroupCycle_relinkAfterSecondPass() throws {
        let ctx = try makeContext()
        let acc = AccountSnapshot(
            id: UUID(), externalId: "EXT", type: .bank,
            institution: "B", name: "N", currency: "EUR",
            archived: false, excluded: false,
            createdAt: Build.epoch, clock: Build.epoch
        )
        let segId = UUID()
        let txId = UUID()
        let tx = TransactionSnapshot(
            id: txId, accountId: acc.id,
            externalId: "EXT_TX", bookedAt: Build.epoch,
            amount: Decimal(-10), currency: "EUR",
            direction: .debit,
            categorySource: .bank, isTransfer: false,
            sharedExpenseGroupId: segId,
            createdAt: Build.epoch, clock: Build.epoch
        )
        let seg = SharedExpenseGroupSnapshot(
            id: segId, label: "Split",
            primaryTxId: txId, attributionMonth: Build.epoch,
            createdAt: Build.epoch, updatedAt: Build.epoch
        )

        let records = [
            RecordCoding.encode(tx),
            RecordCoding.encode(seg),
            RecordCoding.encode(acc),
        ]
        _ = try PullPipeline.apply(
            modifications: records, deletions: [], in: ctx
        )

        let txLocal = ModelSnapshots.find(transaction: txId, in: ctx)
        let segLocal = ModelSnapshots.find(sharedExpenseGroup: segId, in: ctx)
        XCTAssertEqual(segLocal?.primaryTx?.id, txId)
        XCTAssertEqual(txLocal?.sharedExpenseGroup?.id, segId,
                       "cycle should be relinked in second pass")
    }

    func test_deletion_byRecordType() throws {
        let ctx = try makeContext()
        let conn = ModelSnapshots.insertOrUpdate(Build.connection(), in: ctx)
        try ctx.save()
        XCTAssertNotNil(ModelSnapshots.find(connection: conn.id, in: ctx))

        let recordID = SyncZone.recordID(for: conn.id)
        let report = try PullPipeline.apply(
            modifications: [],
            deletions: [PullDeletion(recordID: recordID, recordType: RecordType.connection)],
            in: ctx
        )
        XCTAssertEqual(report.deleted, 1)
        XCTAssertNil(ModelSnapshots.find(connection: conn.id, in: ctx))
    }

    func test_unknownRecordType_skipped() throws {
        let ctx = try makeContext()
        let bogus = CKRecord(
            recordType: "Unknown",
            recordID: CKRecord.ID(recordName: UUID().uuidString)
        )
        let report = try PullPipeline.apply(
            modifications: [bogus], deletions: [], in: ctx
        )
        XCTAssertEqual(report.skippedUnknownType, 1)
    }

    func test_decodeFailure_recorded() throws {
        let ctx = try makeContext()
        // Connection record missing required fields → decode fails.
        let bad = CKRecord(
            recordType: RecordType.connection,
            recordID: CKRecord.ID(recordName: UUID().uuidString)
        )
        let report = try PullPipeline.apply(
            modifications: [bad], deletions: [], in: ctx
        )
        XCTAssertEqual(report.skippedDecodeError, 1)
    }
}
