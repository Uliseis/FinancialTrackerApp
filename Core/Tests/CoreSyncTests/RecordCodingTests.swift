import XCTest
import Foundation
import CloudKit
@testable import CoreModel
@testable import CoreSync

final class RecordCodingTests: XCTestCase {

    func test_connection_roundTrip() throws {
        let snap = Build.connection()
        let record = RecordCoding.encode(snap)
        XCTAssertEqual(record.recordType, RecordType.connection)
        XCTAssertEqual(record.recordID.recordName, snap.id.uuidString)
        let decoded = try RecordCoding.decodeConnection(record)
        XCTAssertEqual(decoded, snap)
    }

    func test_accountGroup_roundTrip() throws {
        let snap = Build.accountGroup()
        let record = RecordCoding.encode(snap)
        let decoded = try RecordCoding.decodeAccountGroup(record)
        XCTAssertEqual(decoded, snap)
    }

    func test_accountSpace_roundTrip() throws {
        let snap = Build.accountSpace()
        let record = RecordCoding.encode(snap)
        let decoded = try RecordCoding.decodeAccountSpace(record)
        XCTAssertEqual(decoded, snap)
    }

    func test_account_roundTrip() throws {
        let snap = Build.account()
        let record = RecordCoding.encode(snap)
        let decoded = try RecordCoding.decodeAccount(record)
        XCTAssertEqual(decoded, snap)
    }

    func test_account_decimalPreservesPrecision() throws {
        let snap = AccountSnapshot(
            id: UUID(),
            externalId: "EXT", type: .bank,
            institution: "B", name: "N", currency: "EUR",
            balance: Decimal(string: "9999999999.9999")!,
            archived: false, excluded: false,
            createdAt: Build.epoch, clock: Build.epoch
        )
        let record = RecordCoding.encode(snap)
        let decoded = try RecordCoding.decodeAccount(record)
        XCTAssertEqual(decoded.balance, snap.balance)
    }

    func test_category_roundTrip() throws {
        let snap = Build.category()
        let record = RecordCoding.encode(snap)
        let decoded = try RecordCoding.decodeCategory(record)
        XCTAssertEqual(decoded, snap)
    }

    func test_categoryRule_roundTrip() throws {
        let snap = Build.categoryRule()
        let record = RecordCoding.encode(snap)
        let decoded = try RecordCoding.decodeCategoryRule(record)
        XCTAssertEqual(decoded, snap)
    }

    func test_transferRoute_roundTrip() throws {
        let snap = Build.transferRoute()
        let record = RecordCoding.encode(snap)
        let decoded = try RecordCoding.decodeTransferRoute(record)
        XCTAssertEqual(decoded, snap)
    }

    func test_transferGroup_roundTrip() throws {
        let snap = Build.transferGroup()
        let record = RecordCoding.encode(snap)
        let decoded = try RecordCoding.decodeTransferGroup(record)
        XCTAssertEqual(decoded, snap)
    }

    func test_budget_roundTrip() throws {
        let snap = Build.budget()
        let record = RecordCoding.encode(snap)
        let decoded = try RecordCoding.decodeBudget(record)
        XCTAssertEqual(decoded, snap)
    }

    func test_fxRate_roundTrip() throws {
        let snap = Build.fxRate()
        let record = RecordCoding.encode(snap)
        let decoded = try RecordCoding.decodeFxRate(record)
        XCTAssertEqual(decoded, snap)
    }

    func test_transaction_roundTrip() throws {
        let snap = Build.transaction(
            categoryId: UUID(), categorySource: .manual
        )
        let record = RecordCoding.encode(snap)
        let decoded = try RecordCoding.decodeTransaction(record)
        XCTAssertEqual(decoded, snap)
    }

    func test_sharedExpenseGroup_roundTrip() throws {
        let snap = Build.sharedExpenseGroup()
        let record = RecordCoding.encode(snap)
        let decoded = try RecordCoding.decodeSharedExpenseGroup(record)
        XCTAssertEqual(decoded, snap)
    }

    func test_portfolioValuation_roundTrip() throws {
        let snap = Build.portfolioValuation()
        let record = RecordCoding.encode(snap)
        let decoded = try RecordCoding.decodePortfolioValuation(record)
        XCTAssertEqual(decoded, snap)
    }

    func test_syncRun_roundTrip() throws {
        let snap = Build.syncRun()
        let record = RecordCoding.encode(snap)
        let decoded = try RecordCoding.decodeSyncRun(record)
        XCTAssertEqual(decoded, snap)
    }

    func test_decode_wrongRecordType_throws() {
        let record = CKRecord(
            recordType: "WrongType",
            recordID: CKRecord.ID(recordName: UUID().uuidString)
        )
        XCTAssertThrowsError(try RecordCoding.decodeConnection(record)) { err in
            guard case RecordCodingError.wrongRecordType(let f, let e) = err else {
                return XCTFail("expected wrongRecordType, got \(err)")
            }
            XCTAssertEqual(f, "WrongType")
            XCTAssertEqual(e, RecordType.connection)
        }
    }

    func test_decode_nonUUIDRecordName_throws() {
        let record = CKRecord(
            recordType: RecordType.connection,
            recordID: CKRecord.ID(recordName: "not-a-uuid")
        )
        record["connector"] = "manual"
        record["status"] = "pending"
        record["createdAt"] = Build.epoch
        record["updatedAt"] = Build.epoch
        XCTAssertThrowsError(try RecordCoding.decodeConnection(record)) { err in
            guard case RecordCodingError.recordNameNotUUID = err else {
                return XCTFail("expected recordNameNotUUID, got \(err)")
            }
        }
    }

    func test_decode_missingRequiredField_throws() {
        let record = CKRecord(
            recordType: RecordType.connection,
            recordID: CKRecord.ID(recordName: UUID().uuidString)
        )
        // Missing connector + status + dates.
        XCTAssertThrowsError(try RecordCoding.decodeConnection(record)) { err in
            guard case RecordCodingError.missingField = err else {
                return XCTFail("expected missingField, got \(err)")
            }
        }
    }
}
