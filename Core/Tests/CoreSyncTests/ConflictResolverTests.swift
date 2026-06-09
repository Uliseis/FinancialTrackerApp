import XCTest
import Foundation
@testable import CoreModel
@testable import CoreSync

final class ConflictResolverTests: XCTestCase {

    // MARK: - generic LWW

    func test_resolve_remoteNewer_appliesRemote() {
        let local = Build.accountGroup(updatedAt: Build.epoch)
        let remote = Build.accountGroup(id: local.id, updatedAt: Build.later)
        XCTAssertEqual(ConflictResolver.resolve(local: local, remote: remote), .applyRemote)
    }

    func test_resolve_localNewer_keepsLocal() {
        let local = Build.accountGroup(updatedAt: Build.later)
        let remote = Build.accountGroup(id: local.id, updatedAt: Build.epoch)
        XCTAssertEqual(ConflictResolver.resolve(local: local, remote: remote), .keepLocal)
    }

    func test_resolve_tie_appliesRemote() {
        let local = Build.accountGroup(updatedAt: Build.epoch)
        let remote = Build.accountGroup(id: local.id, updatedAt: Build.epoch)
        XCTAssertEqual(ConflictResolver.resolve(local: local, remote: remote), .applyRemote)
    }

    // MARK: - transaction manual-override

    func test_transaction_bothNonManual_plainLWW_remoteNewer() {
        let localCatId = UUID()
        let remoteCatId = UUID()
        let local = Build.transaction(
            categoryId: localCatId, categorySource: .rule, clock: Build.epoch
        )
        let remote = Build.transaction(
            id: local.id, accountId: local.accountId ?? UUID(),
            categoryId: remoteCatId, categorySource: .rule, clock: Build.later
        )
        XCTAssertEqual(
            ConflictResolver.resolveTransaction(local: local, remote: remote),
            .applyRemote
        )
    }

    func test_transaction_localManual_remoteNewerNonManual_mergesKeepingLocalCategory() {
        let localCatId = UUID()
        let remoteCatId = UUID()
        let local = Build.transaction(
            categoryId: localCatId, categorySource: .manual, clock: Build.epoch
        )
        let remote = Build.transaction(
            id: local.id, accountId: local.accountId ?? UUID(),
            categoryId: remoteCatId, categorySource: .rule, clock: Build.later
        )
        let result = ConflictResolver.resolveTransaction(local: local, remote: remote)
        guard case .merge(let merged) = result else {
            return XCTFail("expected .merge, got \(result)")
        }
        XCTAssertEqual(merged.categoryId, localCatId)
        XCTAssertEqual(merged.categorySource, .manual)
        XCTAssertEqual(merged.clock, remote.clock)
    }

    func test_transaction_localManualLocalNewer_keepsLocal() {
        let local = Build.transaction(
            categoryId: UUID(), categorySource: .manual, clock: Build.later
        )
        let remote = Build.transaction(
            id: local.id, accountId: local.accountId ?? UUID(),
            categoryId: UUID(), categorySource: .rule, clock: Build.epoch
        )
        XCTAssertEqual(
            ConflictResolver.resolveTransaction(local: local, remote: remote),
            .keepLocal
        )
    }

    func test_transaction_remoteManualRemoteNewer_appliesRemote() {
        let local = Build.transaction(
            categoryId: UUID(), categorySource: .bank, clock: Build.epoch
        )
        let remote = Build.transaction(
            id: local.id, accountId: local.accountId ?? UUID(),
            categoryId: UUID(), categorySource: .manual, clock: Build.later
        )
        XCTAssertEqual(
            ConflictResolver.resolveTransaction(local: local, remote: remote),
            .applyRemote
        )
    }

    func test_transaction_remoteManualLocalNewer_mergesAdoptingRemoteCategory() {
        let localCatId = UUID()
        let remoteCatId = UUID()
        let local = Build.transaction(
            categoryId: localCatId, categorySource: .bank, clock: Build.later
        )
        let remote = Build.transaction(
            id: local.id, accountId: local.accountId ?? UUID(),
            categoryId: remoteCatId, categorySource: .manual, clock: Build.epoch
        )
        let result = ConflictResolver.resolveTransaction(local: local, remote: remote)
        guard case .merge(let merged) = result else {
            return XCTFail("expected .merge, got \(result)")
        }
        XCTAssertEqual(merged.categoryId, remoteCatId)
        XCTAssertEqual(merged.categorySource, .manual)
        XCTAssertEqual(merged.clock, local.clock)
    }

    func test_transaction_bothManual_plainLWW() {
        let local = Build.transaction(
            categoryId: UUID(), categorySource: .manual, clock: Build.epoch
        )
        let remote = Build.transaction(
            id: local.id, accountId: local.accountId ?? UUID(),
            categoryId: UUID(), categorySource: .manual, clock: Build.later
        )
        XCTAssertEqual(
            ConflictResolver.resolveTransaction(local: local, remote: remote),
            .applyRemote
        )
    }

    func test_transaction_tieClock_localManualRemoteNonManual_merges() {
        let localCatId = UUID()
        let local = Build.transaction(
            categoryId: localCatId, categorySource: .manual, clock: Build.epoch
        )
        let remote = Build.transaction(
            id: local.id, accountId: local.accountId ?? UUID(),
            categoryId: UUID(), categorySource: .rule, clock: Build.epoch
        )
        let result = ConflictResolver.resolveTransaction(local: local, remote: remote)
        guard case .merge(let merged) = result else {
            return XCTFail("expected .merge on tie when local has manual, got \(result)")
        }
        XCTAssertEqual(merged.categoryId, localCatId)
        XCTAssertEqual(merged.categorySource, .manual)
    }
}
