import XCTest
import Foundation
import SwiftData
import CloudKit
@testable import CoreModel
@testable import CoreSync

@MainActor
final class SaveObserverTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema(CoreModelSchema.allTypes)
        let config = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func recordName(_ c: CKSyncEngine.PendingRecordZoneChange) -> String? {
        switch c {
        case .saveRecord(let id), .deleteRecord(let id): return id.recordName
        @unknown default: return nil
        }
    }
    private func isSave(_ c: CKSyncEngine.PendingRecordZoneChange) -> Bool {
        if case .saveRecord = c { return true }; return false
    }
    private func isDelete(_ c: CKSyncEngine.PendingRecordZoneChange) -> Bool {
        if case .deleteRecord = c { return true }; return false
    }

    private func makeAccount(_ ctx: ModelContext) -> Account {
        let a = Account(externalId: UUID().uuidString, type: .bank,
                        institution: "B", name: "N", currency: "EUR")
        ctx.insert(a)
        return a
    }

    func test_insertSave_enqueuesSaveRecord() throws {
        let ctx = try makeContext()
        var committed: [CKSyncEngine.PendingRecordZoneChange] = []
        let observer = SaveObserver(observing: ctx) { committed.append(contentsOf: $0) }

        let a = makeAccount(ctx)
        try ctx.save()

        XCTAssertTrue(committed.contains { isSave($0) && recordName($0) == a.id.uuidString })
        _ = observer
    }

    func test_updateSave_enqueuesSaveRecord() throws {
        let ctx = try makeContext()
        let a = makeAccount(ctx)
        try ctx.save()

        var committed: [CKSyncEngine.PendingRecordZoneChange] = []
        let observer = SaveObserver(observing: ctx) { committed.append(contentsOf: $0) }

        a.name = "Renamed"
        try ctx.save()

        XCTAssertTrue(committed.contains { isSave($0) && recordName($0) == a.id.uuidString })
        _ = observer
    }

    // The case that motivates willSave-capture: after commit the row is gone, so the
    // UUID must be captured before the delete lands.
    func test_deleteSave_enqueuesDeleteRecord() throws {
        let ctx = try makeContext()
        let a = makeAccount(ctx)
        try ctx.save()
        let uuid = a.id.uuidString

        var committed: [CKSyncEngine.PendingRecordZoneChange] = []
        let observer = SaveObserver(observing: ctx) { committed.append(contentsOf: $0) }

        ctx.delete(a)
        try ctx.save()

        XCTAssertTrue(committed.contains { isDelete($0) && recordName($0) == uuid },
                      "Delete must be enqueued with the model's UUID captured at willSave")
        _ = observer
    }

    // A save on the engine's own context must not be observed (no echo loop): an
    // observer scoped to context A ignores saves on context B in the same container.
    func test_observerIsScopedToItsContext() throws {
        let schema = Schema(CoreModelSchema.allTypes)
        let config = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        let uiCtx = ModelContext(container)
        let syncCtx = ModelContext(container)

        var committed: [CKSyncEngine.PendingRecordZoneChange] = []
        let observer = SaveObserver(observing: uiCtx) { committed.append(contentsOf: $0) }

        let a = Account(externalId: UUID().uuidString, type: .bank,
                        institution: "B", name: "N", currency: "EUR")
        syncCtx.insert(a)
        try syncCtx.save()

        XCTAssertTrue(committed.isEmpty, "Saves on a different context must not enqueue")
        _ = observer
    }
}
