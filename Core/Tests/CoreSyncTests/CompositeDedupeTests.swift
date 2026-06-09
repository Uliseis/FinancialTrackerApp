import XCTest
import Foundation
@testable import CoreModel
@testable import CoreSync

final class CompositeDedupeTests: XCTestCase {

    // MARK: - Transaction (S5)

    func test_transaction_noExisting_insert() {
        let incoming = Build.transaction()
        XCTAssertEqual(
            CompositeDedupe.dedupe(incoming: incoming, existing: nil),
            .insert
        )
    }

    func test_transaction_sameIdSameCompositeKey_sameRow() {
        let accountId = UUID()
        let id = UUID()
        let incoming = Build.transaction(id: id, accountId: accountId, externalId: "EXT_42")
        let existing = Build.transaction(id: id, accountId: accountId, externalId: "EXT_42")
        XCTAssertEqual(
            CompositeDedupe.dedupe(incoming: incoming, existing: existing),
            .sameRow(existingId: id)
        )
    }

    func test_transaction_existingOlder_existingWins() {
        let accountId = UUID()
        let existingId = UUID()
        let incomingId = UUID()
        let existing = Build.transaction(
            id: existingId, accountId: accountId, externalId: "EXT_42",
            createdAt: Build.epoch
        )
        let incoming = Build.transaction(
            id: incomingId, accountId: accountId, externalId: "EXT_42",
            createdAt: Build.later
        )
        XCTAssertEqual(
            CompositeDedupe.dedupe(incoming: incoming, existing: existing),
            .duplicate(winnerId: existingId, loserId: incomingId)
        )
    }

    func test_transaction_incomingOlder_incomingWins() {
        let accountId = UUID()
        let existingId = UUID()
        let incomingId = UUID()
        let existing = Build.transaction(
            id: existingId, accountId: accountId, externalId: "EXT_42",
            createdAt: Build.later
        )
        let incoming = Build.transaction(
            id: incomingId, accountId: accountId, externalId: "EXT_42",
            createdAt: Build.epoch
        )
        XCTAssertEqual(
            CompositeDedupe.dedupe(incoming: incoming, existing: existing),
            .duplicate(winnerId: incomingId, loserId: existingId)
        )
    }

    func test_transaction_tieCreatedAt_lowerUUIDWins() {
        let accountId = UUID()
        let idA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let idB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let existing = Build.transaction(
            id: idB, accountId: accountId, externalId: "EXT_42",
            createdAt: Build.epoch
        )
        let incoming = Build.transaction(
            id: idA, accountId: accountId, externalId: "EXT_42",
            createdAt: Build.epoch
        )
        XCTAssertEqual(
            CompositeDedupe.dedupe(incoming: incoming, existing: existing),
            .duplicate(winnerId: idA, loserId: idB)
        )
    }

    func test_transaction_compositeKey_requiresAccountId() {
        let withAccount = Build.transaction(accountId: UUID(), externalId: "EXT_X")
        XCTAssertNotNil(withAccount.compositeKey)

        let withoutAccount = TransactionSnapshot(
            id: UUID(), accountId: nil,
            externalId: "EXT_X", bookedAt: Build.epoch,
            amount: Decimal(1), currency: "EUR",
            direction: .debit,
            categorySource: .bank, isTransfer: false,
            createdAt: Build.epoch, clock: Build.epoch
        )
        XCTAssertNil(withoutAccount.compositeKey)
    }

    // MARK: - FxRate (N6)

    func test_fxRate_noExisting_insert() {
        let incoming = Build.fxRate()
        XCTAssertEqual(
            CompositeDedupe.dedupe(incoming: incoming, existing: nil),
            .insert
        )
    }

    func test_fxRate_sameIdSameKey_sameRow() {
        let id = UUID()
        let date = Build.epoch
        let incoming = Build.fxRate(id: id, currency: "USD", date: date)
        let existing = Build.fxRate(id: id, currency: "USD", date: date)
        XCTAssertEqual(
            CompositeDedupe.dedupe(incoming: incoming, existing: existing),
            .sameRow(existingId: id)
        )
    }

    func test_fxRate_existingOlder_existingWins() {
        let existingId = UUID()
        let incomingId = UUID()
        let date = Build.epoch
        let existing = Build.fxRate(
            id: existingId, currency: "USD", date: date, createdAt: Build.epoch
        )
        let incoming = Build.fxRate(
            id: incomingId, currency: "USD", date: date, createdAt: Build.later
        )
        XCTAssertEqual(
            CompositeDedupe.dedupe(incoming: incoming, existing: existing),
            .duplicate(winnerId: existingId, loserId: incomingId)
        )
    }

    func test_fxRate_tieCreatedAt_lowerUUIDWins() {
        let idA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let idB = UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!
        let date = Build.epoch
        let existing = Build.fxRate(id: idB, currency: "USD", date: date)
        let incoming = Build.fxRate(id: idA, currency: "USD", date: date)
        XCTAssertEqual(
            CompositeDedupe.dedupe(incoming: incoming, existing: existing),
            .duplicate(winnerId: idA, loserId: idB)
        )
    }

    func test_fxRate_compositeKey() {
        let date = Build.epoch
        let s = Build.fxRate(currency: "GBP", date: date)
        XCTAssertEqual(s.compositeKey, FxRateCompositeKey(date: date, currency: "GBP"))
    }
}
