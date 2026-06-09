import XCTest
import Foundation
import SwiftData
@testable import CoreModel
@testable import CoreSync

@MainActor
final class ModelSnapshotsTests: XCTestCase {
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

    func test_connection_insertSnapshotApplyRoundTrip() throws {
        let ctx = try makeContext()
        let snap = Build.connection(updatedAt: Build.later)
        let inserted = ModelSnapshots.insertOrUpdate(snap, in: ctx)
        try ctx.save()

        let roundTrip = ModelSnapshots.snapshot(inserted)
        XCTAssertEqual(roundTrip, snap)
    }

    func test_account_relationshipsResolveByUUID() throws {
        let ctx = try makeContext()
        let conn = ModelSnapshots.insertOrUpdate(Build.connection(), in: ctx)
        let group = ModelSnapshots.insertOrUpdate(Build.accountGroup(), in: ctx)
        let space = ModelSnapshots.insertOrUpdate(Build.accountSpace(), in: ctx)

        let accSnap = AccountSnapshot(
            id: UUID(),
            connectionId: conn.id, groupId: group.id, spaceId: space.id,
            externalId: "EXT", type: .bank,
            institution: "B", name: "N", currency: "EUR",
            archived: false, excluded: false,
            createdAt: Build.epoch, clock: Build.epoch
        )
        let acc = ModelSnapshots.insertOrUpdate(accSnap, in: ctx)
        try ctx.save()

        XCTAssertEqual(acc.connection?.id, conn.id)
        XCTAssertEqual(acc.group?.id, group.id)
        XCTAssertEqual(acc.space?.id, space.id)
    }

    func test_account_orphanRelationship_nullified() throws {
        let ctx = try makeContext()
        let accSnap = AccountSnapshot(
            id: UUID(),
            connectionId: UUID(),
            externalId: "EXT", type: .bank,
            institution: "B", name: "N", currency: "EUR",
            archived: false, excluded: false,
            createdAt: Build.epoch, clock: Build.epoch
        )
        let acc = ModelSnapshots.insertOrUpdate(accSnap, in: ctx)
        try ctx.save()
        XCTAssertNil(acc.connection)
    }

    func test_apply_overridesAllFields() throws {
        let ctx = try makeContext()
        let original = Build.accountGroup(updatedAt: Build.epoch)
        let inserted = ModelSnapshots.insertOrUpdate(original, in: ctx)
        try ctx.save()

        let updated = AccountGroupSnapshot(
            id: original.id,
            name: "Renamed",
            color: "#000000",
            kind: .investment,
            sortOrder: 99,
            createdAt: original.createdAt,
            updatedAt: Build.later
        )
        ModelSnapshots.apply(updated, to: inserted)
        try ctx.save()

        let after = ModelSnapshots.snapshot(inserted)
        XCTAssertEqual(after, updated)
    }

    func test_transaction_roundTripWithRelationships() throws {
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
        let cat = ModelSnapshots.insertOrUpdate(Build.category(), in: ctx)
        try ctx.save()

        let txSnap = Build.transaction(
            accountId: acc.id, categoryId: cat.id, categorySource: .manual
        )
        let tx = ModelSnapshots.insertOrUpdate(txSnap, in: ctx)
        try ctx.save()

        let roundTrip = ModelSnapshots.snapshot(tx)
        XCTAssertEqual(roundTrip.accountId, acc.id)
        XCTAssertEqual(roundTrip.categoryId, cat.id)
        XCTAssertEqual(roundTrip.categorySource, .manual)
    }

    func test_find_returnsNilForMissing() throws {
        let ctx = try makeContext()
        XCTAssertNil(ModelSnapshots.find(transaction: UUID(), in: ctx))
        XCTAssertNil(ModelSnapshots.find(account: UUID(), in: ctx))
    }
}
