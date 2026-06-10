import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel
@testable import CoreIntegrations

// Stubbed EBSyncAPI driving the full sync orchestration without network.
@MainActor
final class EBSyncTests: XCTestCase {
    typealias S = TransferTestSupport
    typealias Sync = CoreLogic.EBSync

    private static let uid = "11111111-2222-3333-4444-555555555555"

    private final class StubAPI: EBSyncAPI, @unchecked Sendable {
        var session: SessionResponse
        var details: [String: AccountDetails] = [:]
        var balances: [String: BalancesResponse] = [:]
        var txPages: [String: [TransactionsResponse]] = [:]
        var sessionError: Error?

        init(session: SessionResponse) { self.session = session }

        func getSession(_ sessionId: String) async throws -> SessionResponse {
            if let sessionError { throw sessionError }
            return session
        }
        func getAccountDetails(_ accountUid: String) async throws -> AccountDetails {
            details[accountUid]!
        }
        func getAccountBalances(_ accountUid: String) async throws -> BalancesResponse {
            balances[accountUid] ?? decode(#"{"balances": []}"#)
        }
        func getAccountTransactions(
            _ accountUid: String, query: EBTransactionQuery
        ) async throws -> TransactionsResponse {
            var pages = txPages[accountUid] ?? []
            guard !pages.isEmpty else { return decode(#"{"transactions": []}"#) }
            let page = pages.removeFirst()
            txPages[accountUid] = pages
            return page
        }
    }

    // MARK: - fixtures

    nonisolated private static func decode<T: Decodable>(_ json: String) -> T {
        try! EBJSON.decoder.decode(T.self, from: Data(json.utf8))
    }

    private func decode<T: Decodable>(_ json: String) -> T { Self.decode(json) }

    // Mirrors the real GET /sessions/{id} shape: no session_id, slim accounts_data.
    private func makeSession(status: String = "AUTHORIZED",
                             uids: [String] = [EBSyncTests.uid]) -> SessionResponse {
        decode("""
        {
          "status": "\(status)",
          "accounts": [\(uids.map { #""\#($0)""# }.joined(separator: ","))],
          "accounts_data": [\(uids.map { #"{"uid": "\#($0)", "identification_hash": "h"}"# }.joined(separator: ","))],
          "access": {"accounts": null, "balances": true, "transactions": true,
                     "valid_until": "2026-09-08T10:00:00Z"},
          "aspsp": {"name": "Revolut", "country": "ES"},
          "closed": null
        }
        """)
    }

    private func details(iban: String? = "ES1234", name: String = "Main",
                         currency: String = "EUR") -> AccountDetails {
        decode("""
        {
          "name": "\(name)", "currency": "\(currency)"
          \(iban.map { #", "account_id": {"iban": "\#($0)"}"# } ?? "")
        }
        """)
    }

    private func balances(_ amount: String) -> BalancesResponse {
        decode("""
        {"balances": [{"name": "x", "balance_amount": {"currency": "EUR", "amount": "\(amount)"},
                       "balance_type": "CLBD"}]}
        """)
    }

    private func txPage(_ entries: [(ref: String, amount: String, indicator: String)],
                        continuation: String? = nil) -> TransactionsResponse {
        let txs = entries.map {
            """
            {"entry_reference": "\($0.ref)",
             "transaction_amount": {"currency": "EUR", "amount": "\($0.amount)"},
             "credit_debit_indicator": "\($0.indicator)",
             "status": "BOOK", "booking_date": "2026-06-01",
             "remittance_information": ["REF \($0.ref)"]}
            """
        }.joined(separator: ",")
        let cont = continuation.map { #", "continuation_key": "\#($0)""# } ?? ""
        return decode(#"{"transactions": [\#(txs)]\#(cont)}"#)
    }

    private func makeConnection(_ ctx: ModelContext, sessionId: String? = "sess-1") -> Connection {
        let conn = Connection(connector: .enablebanking, institutionName: "Revolut",
                              sessionId: sessionId, status: .active)
        ctx.insert(conn)
        try? ctx.save()
        return conn
    }

    private func makeLinkedAccount(_ ctx: ModelContext, connection: Connection,
                                   uid: String = EBSyncTests.uid) -> Account {
        let account = Account(connection: connection, externalId: uid, type: .bank,
                              institution: "Revolut", name: "Old Name", currency: "EUR",
                              iban: "ES1234")
        ctx.insert(account)
        try? ctx.save()
        return account
    }

    // MARK: - pure helpers

    func testComputeDateFrom() {
        let now = ISO8601DateFormatter().date(from: "2026-06-10T12:00:00Z")!
        XCTAssertEqual(Sync.computeDateFrom(lastSyncAt: nil, now: now), "2024-06-10")
        let recent = now.addingTimeInterval(-86_400)
        XCTAssertEqual(Sync.computeDateFrom(lastSyncAt: recent, now: now), "2026-06-02")
        let ancient = now.addingTimeInterval(-Double(900) * 86_400)
        XCTAssertEqual(Sync.computeDateFrom(lastSyncAt: ancient, now: now), "2024-06-10")
    }

    func testIsValidUid() {
        XCTAssertTrue(Sync.isValidUid(Self.uid))
        XCTAssertFalse(Sync.isValidUid(nil))
        XCTAssertFalse(Sync.isValidUid(""))
        XCTAssertFalse(Sync.isValidUid("undefined"))
        XCTAssertFalse(Sync.isValidUid("not-a-uuid"))
    }

    func testReapStaleRuns() throws {
        let ctx = try S.makeContext()
        let now = Date.now
        let stale = SyncRun(connector: .enablebanking, startedAt: now.addingTimeInterval(-1200))
        let fresh = SyncRun(connector: .enablebanking, startedAt: now.addingTimeInterval(-60))
        ctx.insert(stale); ctx.insert(fresh)
        try ctx.save()
        XCTAssertEqual(try Sync.reapStaleRuns(in: ctx, now: now), 1)
        XCTAssertEqual(stale.status, .error)
        XCTAssertEqual(stale.error, "abandoned")
        XCTAssertEqual(fresh.status, .running)
    }

    // MARK: - sync paths

    func testHappyPathInsertsAndDedupesTransactions() async throws {
        let ctx = try S.makeContext()
        let conn = makeConnection(ctx)
        let account = makeLinkedAccount(ctx, connection: conn)

        let api = StubAPI(session: makeSession())
        api.details[Self.uid] = details()
        api.balances[Self.uid] = balances("123.45")
        api.txPages[Self.uid] = [
            txPage([("r1", "10.00", "CRDT"), ("zero", "0", "CRDT")], continuation: "k1"),
            txPage([("r2", "-25.50", "DBIT")]),
        ]

        let result = try await Sync.sync(connection: conn, api: api, in: ctx)
        XCTAssertEqual(result.transactionsInserted, 2)
        XCTAssertEqual(result.errors, [])
        XCTAssertEqual(result.accountsTouched, 1)
        XCTAssertEqual(account.name, "Main")
        XCTAssertEqual(account.balance, Decimal(string: "123.45"))
        XCTAssertEqual(conn.status, .active)
        XCTAssertNotNil(conn.lastSyncAt)
        XCTAssertEqual(conn.expiresAt, ISO8601DateFormatter().date(from: "2026-09-08T10:00:00Z"))

        let runs = try ctx.fetch(FetchDescriptor<SyncRun>())
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.status, .ok)
        XCTAssertEqual(runs.first?.insertedTransactions, 2)

        // EUR transactions get amountEur backfilled at rate 1.
        let txs = try ctx.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(txs.count, 2)
        XCTAssertTrue(txs.allSatisfy { $0.amountEur != nil })
        XCTAssertEqual(result.postProcess?.fxBackfilled, 2)

        // Re-run with the same pages: everything dedupes on (account, externalId).
        api.txPages[Self.uid] = [txPage([("r1", "10.00", "CRDT"), ("r2", "-25.50", "DBIT")])]
        let second = try await Sync.sync(connection: conn, api: api, in: ctx)
        XCTAssertEqual(second.transactionsInserted, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Transaction>()).count, 2)
    }

    func testRevokedSessionMarksConnectionExpired() async throws {
        let ctx = try S.makeContext()
        let conn = makeConnection(ctx)
        let api = StubAPI(session: makeSession(status: "REVOKED"))
        let result = try await Sync.sync(connection: conn, api: api, in: ctx)
        XCTAssertEqual(conn.status, .expired)
        XCTAssertEqual(result.errors, ["session REVOKED"])
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<SyncRun>()).first?.status, .error)
    }

    func testBadUidRecordsErrorAndMetadata() async throws {
        let ctx = try S.makeContext()
        let conn = makeConnection(ctx)
        let api = StubAPI(session: makeSession(uids: ["undefined"]))
        let result = try await Sync.sync(connection: conn, api: api, in: ctx)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(result.errors[0].hasPrefix("bad-uid:"))
        let meta = try JSONSerialization.jsonObject(
            with: XCTUnwrap(conn.metadataJSON)) as? [String: Any]
        XCTAssertNotNil(meta?["lastBadAccountAt"])
        XCTAssertEqual(conn.status, .error)
    }

    func testDiscoveredAccountParkedArchivedWithoutTransactions() async throws {
        let ctx = try S.makeContext()
        let conn = makeConnection(ctx)
        let api = StubAPI(session: makeSession())
        api.details[Self.uid] = details()
        api.balances[Self.uid] = balances("50")
        api.txPages[Self.uid] = [txPage([("r1", "10.00", "CRDT")])]

        let result = try await Sync.sync(connection: conn, api: api, in: ctx)
        XCTAssertEqual(result.transactionsInserted, 0)
        let account = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Account>()).first)
        XCTAssertTrue(account.archived)
        XCTAssertNil(account.balance)
        let meta = try JSONSerialization.jsonObject(
            with: XCTUnwrap(account.metadataJSON)) as? [String: Any]
        XCTAssertEqual(meta?["pendingApproval"] as? Bool, true)
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<Transaction>()).isEmpty)
    }

    func testArchivedAccountSkippedButStamped() async throws {
        let ctx = try S.makeContext()
        let conn = makeConnection(ctx)
        let account = makeLinkedAccount(ctx, connection: conn)
        account.archived = true
        try ctx.save()

        let api = StubAPI(session: makeSession())
        api.details[Self.uid] = details()
        api.txPages[Self.uid] = [txPage([("r1", "10.00", "CRDT")])]
        let result = try await Sync.sync(connection: conn, api: api, in: ctx)
        XCTAssertEqual(result.transactionsInserted, 0)
        let meta = try JSONSerialization.jsonObject(
            with: XCTUnwrap(account.metadataJSON)) as? [String: Any]
        XCTAssertNotNil(meta?["lastDiscoveredAt"])
    }

    func testIbanRepointFromOldConnectionRevokesIt() async throws {
        let ctx = try S.makeContext()
        let old = makeConnection(ctx, sessionId: "old-sess")
        let account = makeLinkedAccount(ctx, connection: old, uid: UUID().uuidString)
        let current = makeConnection(ctx)

        let api = StubAPI(session: makeSession())
        api.details[Self.uid] = details()  // same ES1234 iban as the existing account
        api.balances[Self.uid] = balances("9.99")

        let result = try await Sync.sync(connection: current, api: api, in: ctx)
        XCTAssertEqual(result.errors, [])
        XCTAssertEqual(account.connection?.id, current.id)
        XCTAssertEqual(account.externalId, Self.uid)
        XCTAssertEqual(old.status, .revoked)
        let meta = try JSONSerialization.jsonObject(
            with: XCTUnwrap(old.metadataJSON)) as? [String: Any]
        XCTAssertEqual(meta?["replacedBy"] as? String, current.id.uuidString)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Account>()).count, 1)
    }

    func testAmbiguousIbanRefusesRepoint() async throws {
        let ctx = try S.makeContext()
        let other = makeConnection(ctx, sessionId: "other")
        _ = makeLinkedAccount(ctx, connection: other, uid: UUID().uuidString)
        _ = makeLinkedAccount(ctx, connection: other, uid: UUID().uuidString)
        let current = makeConnection(ctx)

        let api = StubAPI(session: makeSession())
        api.details[Self.uid] = details()
        let result = try await Sync.sync(connection: current, api: api, in: ctx)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(result.errors[0].hasPrefix("iban-ambiguous:"))
    }

    func testCurrencyOverridePreserved() async throws {
        let ctx = try S.makeContext()
        let conn = makeConnection(ctx)
        let account = makeLinkedAccount(ctx, connection: conn)
        account.currency = "USD"
        account.metadataJSON = try JSONSerialization.data(
            withJSONObject: ["currencyOverride": true])
        try ctx.save()

        let api = StubAPI(session: makeSession())
        api.details[Self.uid] = details(currency: "EUR")
        _ = try await Sync.sync(connection: conn, api: api, in: ctx)
        XCTAssertEqual(account.currency, "USD")
        let meta = try JSONSerialization.jsonObject(
            with: XCTUnwrap(account.metadataJSON)) as? [String: Any]
        XCTAssertEqual(meta?["currencyOverride"] as? Bool, true)
    }

    func testUnauthorizedAPIErrorMarksExpiredAndThrows() async throws {
        let ctx = try S.makeContext()
        let conn = makeConnection(ctx)
        let api = StubAPI(session: makeSession())
        api.sessionError = EnableBankingError(status: 401, body: "expired")

        do {
            _ = try await Sync.sync(connection: conn, api: api, in: ctx)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual((error as? EnableBankingError)?.status, 401)
        }
        XCTAssertEqual(conn.status, .expired)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<SyncRun>()).first?.status, .error)
    }

    func testSyncAllSkipsRevokedAndExpired() async throws {
        let ctx = try S.makeContext()
        let active = makeConnection(ctx)
        let revoked = makeConnection(ctx)
        revoked.status = .revoked
        let expired = makeConnection(ctx)
        expired.status = .expired
        try ctx.save()

        let api = StubAPI(session: makeSession(uids: []))
        let results = await Sync.syncAll(api: api, in: ctx)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].connectionId, active.id)
    }
}
