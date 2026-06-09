import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class AccountsMutationsTests: XCTestCase {
    typealias S = TransferTestSupport
    typealias A = CoreLogic.Accounts

    func testCreateManualSetsExternalIdPrefixAndOpeningBalance() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let a = try A.createManual(
            name: "  Cash  ", institution: "  Wallet  ", currency: "eur",
            space: space, openingBalance: 250, in: ctx)
        XCTAssertTrue(a.externalId.hasPrefix("manual:"))
        XCTAssertEqual(a.name, "Cash")
        XCTAssertEqual(a.institution, "Wallet")
        XCTAssertEqual(a.currency, "EUR")
        XCTAssertNil(a.connection)
        XCTAssertEqual(a.balance, 250)
        XCTAssertEqual(a.manualOpeningBalance, 250)
        XCTAssertNotNil(a.balanceUpdatedAt)
    }

    func testCreateManualDefaultsToDefaultSpace() throws {
        let ctx = try S.makeContext()
        let a = try A.createManual(name: "Cash", institution: "Wallet", in: ctx)
        XCTAssertEqual(a.space?.name, "Individual")
        XCTAssertEqual(a.space?.isDefault, true)
        XCTAssertNil(a.balanceUpdatedAt) // no opening balance
    }

    func testCreateManualRejectsBlankNameInstitutionCurrency() throws {
        let ctx = try S.makeContext()
        XCTAssertThrowsError(try A.createManual(name: " ", institution: "X", in: ctx)) {
            XCTAssertEqual($0 as? A.MutationError, .nameRequired)
        }
        XCTAssertThrowsError(try A.createManual(name: "X", institution: " ", in: ctx)) {
            XCTAssertEqual($0 as? A.MutationError, .institutionRequired)
        }
        XCTAssertThrowsError(try A.createManual(name: "X", institution: "Y", currency: "EU", in: ctx)) {
            XCTAssertEqual($0 as? A.MutationError, .invalidCurrency)
        }
    }

    func testUpdateChangesFieldsAndMarksCurrencyOverride() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let group = try CoreLogic.AccountGroups.create(name: "Cash", in: ctx)
        let a = try A.createManual(name: "Old", institution: "Bank", space: space, in: ctx)
        let repair = try A.update(
            a, name: "New", type: .broker, institution: "Broker", currency: "usd",
            group: group, space: space, excluded: true, openingBalance: 99, in: ctx)
        XCTAssertNil(repair) // space unchanged ⇒ no repair
        XCTAssertEqual(a.name, "New")
        XCTAssertEqual(a.type, .broker)
        XCTAssertEqual(a.currency, "USD")
        XCTAssertEqual(a.group?.id, group.id)
        XCTAssertTrue(a.excluded)
        XCTAssertEqual(a.manualOpeningBalance, 99)
        let meta = try XCTUnwrap(a.metadataJSON
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual(meta["currencyOverride"] as? Bool, true)
        XCTAssertNotNil(meta["currencyOverrideAt"])
    }

    func testUpdateSpaceChangeRepairsCrossSpaceGroup() throws {
        let ctx = try S.makeContext()
        let space1 = S.makeSpace(ctx, name: "One")
        let space2 = AccountSpace(name: "Two")
        ctx.insert(space2)
        let accA = S.makeAccount(ctx, name: "A", space: space1)
        let accB = S.makeAccount(ctx, name: "B", space: space1)
        let group = TransferGroup()
        ctx.insert(group)
        let txA = S.makeTx(ctx, account: accA, amount: -100, direction: .debit,
                           isTransfer: true, transferGroup: group)
        _ = S.makeTx(ctx, account: accB, amount: 100, direction: .credit,
                     isTransfer: true, transferGroup: group)
        try ctx.save()

        let repair = try A.update(
            accA, name: accA.name, type: accA.type, institution: accA.institution,
            currency: accA.currency, group: nil, space: space2,
            excluded: false, openingBalance: nil, in: ctx)
        XCTAssertEqual(repair?.groupsBroken, 1)
        XCTAssertNil(txA.transferGroup)
        XCTAssertFalse(txA.isTransfer)
    }

    func testUpdateDoesNotClobberConnectedAccountBalance() throws {
        let ctx = try S.makeContext()
        let conn = Connection(connector: .enablebanking)
        ctx.insert(conn)
        let a = S.makeAccount(ctx, name: "Bank", connection: conn)
        a.balance = 1234
        try ctx.save()
        _ = try A.update(
            a, name: "Bank2", type: a.type, institution: a.institution,
            currency: a.currency, group: nil, space: a.space,
            excluded: false, openingBalance: 0, in: ctx)
        XCTAssertEqual(a.balance, 1234) // untouched
        XCTAssertNil(a.manualOpeningBalance)
    }

    func testSetArchivedTriggersRepairAndNoOpsWhenUnchanged() throws {
        let ctx = try S.makeContext()
        let a = try A.createManual(name: "Cash", institution: "Wallet", in: ctx)
        XCTAssertNil(try A.setArchived(a, false, in: ctx)) // already false
        let repair = try A.setArchived(a, true, in: ctx)
        XCTAssertNotNil(repair)
        XCTAssertTrue(a.archived)
    }

    func testSetAndClearAnchorTogether() throws {
        let ctx = try S.makeContext()
        let a = try A.createManual(name: "Cash", institution: "Wallet", in: ctx)
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        try A.setAnchor(a, balance: 500, at: when, in: ctx)
        XCTAssertEqual(a.balanceAnchor, 500)
        XCTAssertEqual(a.balanceAnchorAt, when)
        XCTAssertTrue(A.hasAnchor(a))
        try A.clearAnchor(a, in: ctx)
        XCTAssertNil(a.balanceAnchor)
        XCTAssertNil(a.balanceAnchorAt)
        XCTAssertFalse(A.hasAnchor(a))
    }

    func testAnchorDrivesComputedBalance() throws {
        let ctx = try S.makeContext()
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let anchorAt = cal.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
        let a = try A.createManual(name: "Cash", institution: "Wallet", openingBalance: 0, in: ctx)
        _ = S.makeTx(ctx, account: a, amount: -10, amountEur: -10, direction: .debit,
                     bookedAt: cal.date(from: DateComponents(year: 2025, month: 12, day: 31))!)
        _ = S.makeTx(ctx, account: a, amount: 25, amountEur: 25, direction: .credit,
                     bookedAt: cal.date(from: DateComponents(year: 2026, month: 1, day: 2))!)
        try A.setAnchor(a, balance: 200, at: anchorAt, in: ctx)
        let native = A.computeNativeBalances([a], in: ctx)
        XCTAssertEqual(native[a.id], 225) // 200 anchor + 25 (tx after anchor); -10 before excluded
    }

    func testDeleteCascadesTransactions() throws {
        let ctx = try S.makeContext()
        let a = try A.createManual(name: "Cash", institution: "Wallet", in: ctx)
        _ = S.makeTx(ctx, account: a, amount: -10, direction: .debit)
        try ctx.save()
        try A.delete(a, in: ctx)
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<Account>()).isEmpty)
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<CoreModel.Transaction>()).isEmpty)
    }
}
