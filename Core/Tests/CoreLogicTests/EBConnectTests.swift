import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel
@testable import CoreIntegrations

@MainActor
final class EBConnectTests: XCTestCase {
    typealias S = TransferTestSupport
    typealias C = CoreLogic.EBConnect

    private func makeSession(
        status: String = "AUTHORIZED",
        validUntil: String? = "2026-09-08T10:00:00Z",
        uids: [String] = ["uid-1", "uid-2"]
    ) -> SessionResponse {
        let json = """
        {
          "session_id": "sess-1",
          "status": "\(status)",
          "accounts": ["acc-raw-1"],
          "accounts_data": [\(uids.map { #"{"uid": "\#($0)"}"# }.joined(separator: ","))],
          "access": {\(validUntil.map { #""valid_until": "\#($0)""# } ?? "")},
          "aspsp": {"name": "Revolut", "country": "ES"}
        }
        """
        return try! EBJSON.decoder.decode(SessionResponse.self, from: Data(json.utf8))
    }

    func testMakeAuthRequestValidityAndFields() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let (request, validUntil) = C.makeAuthRequest(
            aspspName: "Revolut", country: "ES",
            redirectUrl: "https://example.com/cb", state: "st-1", now: now)
        XCTAssertEqual(validUntil, now.addingTimeInterval(90 * 86_400))
        XCTAssertEqual(request.aspsp.name, "Revolut")
        XCTAssertEqual(request.aspsp.country, "ES")
        XCTAssertEqual(request.state, "st-1")
        XCTAssertEqual(request.redirectUrl, "https://example.com/cb")
        XCTAssertEqual(request.psuType, "personal")
        XCTAssertTrue(request.access.validUntil.hasSuffix("Z"))
    }

    func testPrepareConnectionInsertsPendingRow() throws {
        let ctx = try S.makeContext()
        let until = Date(timeIntervalSince1970: 1_760_000_000)
        let conn = try C.prepareConnection(
            aspspName: "ING", country: "ES", state: "st-2", authorizationId: "auth-9",
            validUntil: until, in: ctx)
        XCTAssertEqual(conn.connector, .enablebanking)
        XCTAssertEqual(conn.institutionName, "ING")
        XCTAssertEqual(conn.status, .pending)
        XCTAssertEqual(conn.expiresAt, until)
        XCTAssertEqual(C.storedState(of: conn), "st-2")
        XCTAssertEqual(C.storedCountry(of: conn), "ES")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Connection>()).count, 1)
    }

    func testPrepareConnectionReauthReusesRowAndPreservesUnrelatedMetadata() throws {
        let ctx = try S.makeContext()
        let existing = Connection(connector: .enablebanking, status: .expired)
        existing.metadataJSON = try JSONSerialization.data(withJSONObject: ["custom": "keep"])
        ctx.insert(existing)
        try ctx.save()

        let conn = try C.prepareConnection(
            existing: existing, aspspName: "Abanca", country: "ES",
            state: "st-3", authorizationId: "auth-3",
            validUntil: .now, in: ctx)
        XCTAssertEqual(conn.id, existing.id)
        XCTAssertEqual(conn.status, .pending)
        XCTAssertEqual(C.storedState(of: conn), "st-3")
        let meta = try JSONSerialization.jsonObject(
            with: XCTUnwrap(conn.metadataJSON)) as? [String: Any]
        XCTAssertEqual(meta?["custom"] as? String, "keep")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Connection>()).count, 1)
    }

    func testParseCallback() throws {
        let ok = try C.parseCallback(
            URL(string: "https://x.vercel.app/cb?code=abc&state=st")!)
        XCTAssertEqual(ok.code, "abc")
        XCTAssertEqual(ok.state, "st")

        XCTAssertThrowsError(try C.parseCallback(
            URL(string: "https://x.vercel.app/cb?error=access_denied&state=st")!)) {
            XCTAssertEqual($0 as? C.CallbackError, .bankReported("access_denied"))
        }
        XCTAssertThrowsError(try C.parseCallback(
            URL(string: "https://x.vercel.app/cb?state=st")!)) {
            XCTAssertEqual($0 as? C.CallbackError, .missingCode)
        }
        XCTAssertThrowsError(try C.parseCallback(
            URL(string: "https://x.vercel.app/cb?code=abc")!)) {
            XCTAssertEqual($0 as? C.CallbackError, .missingState)
        }
    }

    func testApplySessionAuthorizedActivatesConnection() throws {
        let ctx = try S.makeContext()
        let conn = try C.prepareConnection(
            aspspName: "Revolut", country: "ES", state: "st-4", authorizationId: "a",
            validUntil: .now, in: ctx)
        try C.applySession(makeSession(), to: conn, expectedState: "st-4", in: ctx)
        XCTAssertEqual(conn.sessionId, "sess-1")
        XCTAssertEqual(conn.status, .active)
        XCTAssertEqual(conn.expiresAt, ISO8601DateFormatter().date(from: "2026-09-08T10:00:00Z"))
        let meta = try JSONSerialization.jsonObject(
            with: XCTUnwrap(conn.metadataJSON)) as? [String: Any]
        XCTAssertEqual(meta?["sessionStatus"] as? String, "AUTHORIZED")
        XCTAssertEqual(meta?["accountUids"] as? [String], ["uid-1", "uid-2"])
        XCTAssertEqual(C.storedState(of: conn), "st-4")
    }

    func testApplySessionNonAuthorizedStaysPending() throws {
        let ctx = try S.makeContext()
        let conn = try C.prepareConnection(
            aspspName: "Revolut", country: "ES", state: "st-5", authorizationId: "a",
            validUntil: .now, in: ctx)
        try C.applySession(makeSession(status: "PENDING_AUTHORIZATION"),
                           to: conn, expectedState: "st-5", in: ctx)
        XCTAssertEqual(conn.status, .pending)
    }

    func testApplySessionRejectsStateMismatch() throws {
        let ctx = try S.makeContext()
        let conn = try C.prepareConnection(
            aspspName: "Revolut", country: "ES", state: "st-6", authorizationId: "a",
            validUntil: .now, in: ctx)
        XCTAssertThrowsError(try C.applySession(
            makeSession(), to: conn, expectedState: "WRONG", in: ctx)) {
            XCTAssertEqual($0 as? C.CallbackError, .stateMismatch)
        }
        XCTAssertNil(conn.sessionId)
    }
}
