import XCTest
@testable import CoreIntegrations

private struct StubToken: EBTokenProvider {
    func bearerToken() throws -> String { "Bearer stub-token" }
}

final class EBClientRequestTests: XCTestCase {
    private func client(psu: PsuHeaders? = nil) -> EBClient {
        EBClient(tokenProvider: StubToken(),
                 baseURL: URL(string: "https://api.enablebanking.com")!,
                 psu: psu)
    }

    func test_transactions_urlAndQuery() throws {
        let req = try client().makeRequest(
            path: "/accounts/uid-1/transactions",
            query: ["date_from": "2026-01-01", "transaction_status": "BOOK",
                    "strategy": "longest", "continuation_key": nil]
        )
        let url = try XCTUnwrap(req.url)
        XCTAssertEqual(url.host, "api.enablebanking.com")
        XCTAssertTrue(url.path.hasSuffix("/accounts/uid-1/transactions"))
        let q = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let dict = Dictionary(uniqueKeysWithValues: q.map { ($0.name, $0.value) })
        XCTAssertEqual(dict["date_from"], "2026-01-01")
        XCTAssertEqual(dict["transaction_status"], "BOOK")
        XCTAssertEqual(dict["strategy"], "longest")
        XCTAssertNil(dict["continuation_key"] ?? nil, "nil query values are dropped")
    }

    func test_authHeaderAndAccept() throws {
        let req = try client().makeRequest(path: "/aspsps")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer stub-token")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(req.value(forHTTPHeaderField: "Content-Type"), "no body ⇒ no content-type")
    }

    func test_postBodySetsContentType() throws {
        let req = try client().makeRequest(path: "/sessions", method: "POST", body: Data("{}".utf8))
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(req.httpBody, Data("{}".utf8))
    }

    func test_psuHeadersForwarded() throws {
        let req = try client(psu: PsuHeaders(ipAddress: "1.2.3.4", userAgent: "UA/1"))
            .makeRequest(path: "/aspsps")
        XCTAssertEqual(req.value(forHTTPHeaderField: "psu-ip-address"), "1.2.3.4")
        XCTAssertEqual(req.value(forHTTPHeaderField: "psu-user-agent"), "UA/1")
    }
}
