import XCTest
import Foundation
import SwiftData
@testable import CoreModel
@testable import CoreLogic
@testable import ImportFromPostgresCore

@MainActor
final class ImporterTests: XCTestCase {
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

    private func loadFixture(_ name: String) throws -> DumpDocument {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        guard let url else {
            XCTFail("missing fixture \(name).json")
            throw CocoaError(.fileReadNoSuchFile)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DumpDocument.self, from: data)
    }

    // MARK: - end-to-end fixture

    func test_minimalFixture_insertsEverything() throws {
        let ctx = try makeContext()
        let doc = try loadFixture("dump_minimal")
        let s = try PostgresImporter.importDump(doc, into: ctx)

        XCTAssertEqual(s.connections, 1)
        XCTAssertEqual(s.accountGroups, 2)
        XCTAssertEqual(s.accountSpaces, 1)
        XCTAssertEqual(s.accounts, 2)
        XCTAssertEqual(s.categories, 2)
        XCTAssertEqual(s.categoryRules, 1)
        XCTAssertEqual(s.transferRoutes, 1)
        XCTAssertEqual(s.budgets, 1)
        XCTAssertEqual(s.fxRates, 1)
        XCTAssertEqual(s.transferGroups, 1)
        XCTAssertEqual(s.transactions, 4)
        XCTAssertEqual(s.sharedExpenseGroups, 1)
        XCTAssertEqual(s.portfolioValuations, 1)
        XCTAssertEqual(s.syncRuns, 1)
        XCTAssertEqual(s.categorySourceBackfilled, 1)
        XCTAssertEqual(s.attributionMonthBackfilled, 0)
    }

    func test_fixtureImport_categoryParentLinked() throws {
        let ctx = try makeContext()
        let doc = try loadFixture("dump_minimal")
        _ = try PostgresImporter.importDump(doc, into: ctx)

        let groceriesID = UUID(uuidString: "55555555-0000-0000-0000-000000000002")!
        let groceries = try ctx.fetch(FetchDescriptor<CoreModel.Category>(
            predicate: #Predicate { $0.id == groceriesID }
        )).first
        XCTAssertNotNil(groceries)
        XCTAssertEqual(groceries?.parent?.name, "Food")
    }

    func test_fixtureImport_decimalParsedExactly() throws {
        let ctx = try makeContext()
        let doc = try loadFixture("dump_minimal")
        _ = try PostgresImporter.importDump(doc, into: ctx)

        let accID = UUID(uuidString: "44444444-0000-0000-0000-000000000001")!
        let acc = try ctx.fetch(FetchDescriptor<Account>(
            predicate: #Predicate { $0.id == accID }
        )).first
        XCTAssertEqual(acc?.balance, Decimal(string: "1234.5678"))
    }

    func test_fixtureImport_mirrorChainLinked() throws {
        let ctx = try makeContext()
        let doc = try loadFixture("dump_minimal")
        _ = try PostgresImporter.importDump(doc, into: ctx)

        let mirrorID = UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000002")!
        let sourceID = UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000001")!
        let mirror = try ctx.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.id == mirrorID }
        )).first
        XCTAssertEqual(mirror?.routedFromTx?.id, sourceID)
    }

    func test_fixtureImport_transferGroupRouteLinked() throws {
        let ctx = try makeContext()
        let doc = try loadFixture("dump_minimal")
        _ = try PostgresImporter.importDump(doc, into: ctx)

        let groupID = UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!
        let routeID = UUID(uuidString: "77777777-0000-0000-0000-000000000001")!
        let group = try ctx.fetch(FetchDescriptor<TransferGroup>(
            predicate: #Predicate { $0.id == groupID }
        )).first
        XCTAssertEqual(group?.route?.id, routeID)
        XCTAssertNotNil(group?.pairedAt)
    }

    func test_fixtureImport_sharedExpenseGroupCircularRefResolved() throws {
        let ctx = try makeContext()
        let doc = try loadFixture("dump_minimal")
        _ = try PostgresImporter.importDump(doc, into: ctx)

        let segID = UUID(uuidString: "cccccccc-0000-0000-0000-000000000001")!
        let primaryID = UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000003")!
        let reimbID = UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000004")!

        let seg = try ctx.fetch(FetchDescriptor<SharedExpenseGroup>(
            predicate: #Predicate { $0.id == segID }
        )).first
        XCTAssertEqual(seg?.primaryTx?.id, primaryID)

        let primary = try ctx.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.id == primaryID }
        )).first
        XCTAssertEqual(primary?.sharedExpenseGroup?.id, segID)

        let reimb = try ctx.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.id == reimbID }
        )).first
        XCTAssertEqual(reimb?.sharedExpenseGroup?.id, segID)
    }

    func test_fixtureImport_categorySourceNullBackfilledToBank() throws {
        let ctx = try makeContext()
        let doc = try loadFixture("dump_minimal")
        _ = try PostgresImporter.importDump(doc, into: ctx)

        let primaryID = UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000003")!
        let primary = try ctx.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.id == primaryID }
        )).first
        XCTAssertEqual(primary?.categorySource, .bank)
        guard let raw = primary?.rawJSON else {
            return XCTFail("expected rawJSON marker after backfill")
        }
        let obj = try JSONSerialization.jsonObject(with: raw) as? [String: Any]
        XCTAssertEqual(obj?["_legacyCategorySourceNull"] as? Bool, true)
    }

    func test_fixtureImport_transferInvariantsPass() throws {
        let ctx = try makeContext()
        let doc = try loadFixture("dump_minimal")
        _ = try PostgresImporter.importDump(doc, into: ctx)

        let violations = try CoreLogic.TransferInvariants.assertAll(in: ctx)
        XCTAssertEqual(
            violations,
            [],
            "imported data violated invariants: \(CoreLogic.TransferInvariants.format(violations))"
        )
    }

    func test_fixtureImport_idempotent() throws {
        let ctx = try makeContext()
        let doc = try loadFixture("dump_minimal")
        let first = try PostgresImporter.importDump(doc, into: ctx)
        XCTAssertEqual(first.transactions, 4)

        let second = try PostgresImporter.importDump(doc, into: ctx)
        XCTAssertEqual(second.transactions, 0)
        XCTAssertEqual(second.accounts, 0)
        XCTAssertEqual(second.connections, 0)

        let txCount = try ctx.fetchCount(FetchDescriptor<Transaction>())
        XCTAssertEqual(txCount, 4)
    }

    // MARK: - programmatic edge cases

    func test_orphanAccountRefThrows() throws {
        let ctx = try makeContext()
        let doc = baseDoc(
            accounts: [],
            transactions: [
                txStub(
                    id: "bbbbbbbb-0000-0000-0000-000000000001",
                    accountId: "44444444-0000-0000-0000-000000000099"
                )
            ]
        )
        XCTAssertThrowsError(try PostgresImporter.importDump(doc, into: ctx)) { err in
            guard case ImportError.orphanReference(let table, _, let field, _) = err else {
                return XCTFail("expected orphanReference, got \(err)")
            }
            XCTAssertEqual(table, "transactions")
            XCTAssertEqual(field, "accountId")
        }
    }

    func test_attributionMonthBackfillsFromPrimaryTx() throws {
        let ctx = try makeContext()
        let accId = "44444444-0000-0000-0000-000000000001"
        let txId = "bbbbbbbb-0000-0000-0000-000000000001"
        let segId = "cccccccc-0000-0000-0000-000000000001"

        let doc = baseDoc(
            accounts: [accountStub(id: accId)],
            transactions: [
                txStub(
                    id: txId,
                    accountId: accId,
                    bookedAt: "2024-03-17T12:00:00Z",
                    sharedExpenseGroupId: segId
                )
            ],
            sharedExpenseGroups: [
                DumpSharedExpenseGroup(
                    id: segId,
                    label: "Test",
                    primaryTxId: txId,
                    attributionMonth: nil,
                    createdAt: "2024-03-17T12:00:00Z",
                    updatedAt: "2024-03-17T12:00:00Z"
                )
            ]
        )

        let s = try PostgresImporter.importDump(doc, into: ctx)
        XCTAssertEqual(s.attributionMonthBackfilled, 1)

        let segUUID = UUID(uuidString: segId)!
        let seg = try ctx.fetch(FetchDescriptor<SharedExpenseGroup>(
            predicate: #Predicate { $0.id == segUUID }
        )).first
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month, .day], from: seg!.attributionMonth)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 1)
    }

    func test_schemaVersionMismatchThrows() throws {
        let ctx = try makeContext()
        let doc = DumpDocument(exportedAt: "2024-01-01T00:00:00Z", schemaVersion: 99)
        XCTAssertThrowsError(try PostgresImporter.importDump(doc, into: ctx)) { err in
            guard case ImportError.schemaVersionUnsupported = err else {
                return XCTFail("expected schemaVersionUnsupported, got \(err)")
            }
        }
    }

    func test_duplicateDumpIdThrows() throws {
        let ctx = try makeContext()
        let id = "44444444-0000-0000-0000-000000000001"
        let doc = baseDoc(accounts: [accountStub(id: id), accountStub(id: id)])
        XCTAssertThrowsError(try PostgresImporter.importDump(doc, into: ctx)) { err in
            guard case ImportError.duplicateDumpId(let table, _) = err else {
                return XCTFail("expected duplicateDumpId, got \(err)")
            }
            XCTAssertEqual(table, "accounts")
        }
    }

    func test_invalidUUIDThrows() throws {
        let ctx = try makeContext()
        let doc = baseDoc(accounts: [accountStub(id: "not-a-uuid")])
        XCTAssertThrowsError(try PostgresImporter.importDump(doc, into: ctx)) { err in
            guard case ImportError.invalidUUID = err else {
                return XCTFail("expected invalidUUID, got \(err)")
            }
        }
    }

    func test_invalidDecimalThrows() throws {
        let ctx = try makeContext()
        var acc = accountStub(id: "44444444-0000-0000-0000-000000000001")
        acc = DumpAccount(
            id: acc.id, connectionId: nil, groupId: nil, spaceId: nil,
            externalId: acc.externalId, type: acc.type, institution: acc.institution,
            name: acc.name, currency: acc.currency, iban: nil,
            balance: "abc", balanceUpdatedAt: nil, metadata: nil,
            archived: false, excluded: false,
            manualOpeningBalance: nil, balanceAnchor: nil, balanceAnchorAt: nil,
            createdAt: acc.createdAt
        )
        let doc = baseDoc(accounts: [acc])
        XCTAssertThrowsError(try PostgresImporter.importDump(doc, into: ctx)) { err in
            guard case ImportError.invalidDecimal = err else {
                return XCTFail("expected invalidDecimal, got \(err)")
            }
        }
    }

    // MARK: - dump builders

    private func baseDoc(
        accounts: [DumpAccount] = [],
        transferGroups: [DumpTransferGroup] = [],
        transactions: [DumpTransaction] = [],
        sharedExpenseGroups: [DumpSharedExpenseGroup] = []
    ) -> DumpDocument {
        DumpDocument(
            exportedAt: "2024-01-01T00:00:00Z",
            schemaVersion: 1,
            accounts: accounts,
            transferGroups: transferGroups,
            transactions: transactions,
            sharedExpenseGroups: sharedExpenseGroups
        )
    }

    private func accountStub(id: String) -> DumpAccount {
        DumpAccount(
            id: id, connectionId: nil, groupId: nil, spaceId: nil,
            externalId: "EXT_\(id.prefix(8))",
            type: "bank", institution: "Bank", name: "Test", currency: "EUR",
            iban: nil, balance: nil, balanceUpdatedAt: nil, metadata: nil,
            archived: false, excluded: false,
            manualOpeningBalance: nil, balanceAnchor: nil, balanceAnchorAt: nil,
            createdAt: "2024-01-01T00:00:00Z"
        )
    }

    private func txStub(
        id: String,
        accountId: String,
        bookedAt: String = "2024-01-15T10:00:00Z",
        sharedExpenseGroupId: String? = nil
    ) -> DumpTransaction {
        DumpTransaction(
            id: id, accountId: accountId,
            externalId: "EXT_TX_\(id.prefix(8))",
            bookedAt: bookedAt, valueAt: nil,
            amount: "-10.00", currency: "EUR", amountEur: "-10.00", fxRateUsed: nil,
            direction: "debit", description: nil, counterparty: nil,
            categoryId: nil, categorySource: "bank", isTransfer: false,
            transferGroupId: nil, routedFromTxId: nil, routeId: nil,
            sharedExpenseGroupId: sharedExpenseGroupId,
            raw: nil, createdAt: bookedAt
        )
    }
}
