import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct EnableBankingError: Error, Equatable {
    public let status: Int
    public let body: String
}

public struct EBTransactionQuery: Equatable, Sendable {
    public var dateFrom: String?
    public var dateTo: String?
    public var transactionStatus: String?
    public var continuationKey: String?
    public var strategy: String?
    public init(dateFrom: String? = nil, dateTo: String? = nil, transactionStatus: String? = "BOOK",
                continuationKey: String? = nil, strategy: String? = "longest") {
        self.dateFrom = dateFrom; self.dateTo = dateTo
        self.transactionStatus = transactionStatus
        self.continuationKey = continuationKey; self.strategy = strategy
    }
}

public struct EBClient: Sendable {
    public let baseURL: URL
    let tokenProvider: any EBTokenProvider
    let session: URLSession
    let psu: PsuHeaders?

    public init(
        tokenProvider: any EBTokenProvider,
        baseURL: URL = URL(string: "https://api.enablebanking.com")!,
        session: URLSession = .shared,
        psu: PsuHeaders? = nil
    ) {
        self.tokenProvider = tokenProvider
        self.baseURL = baseURL
        self.session = session
        self.psu = psu
    }

    // MARK: - request building (pure, testable)

    func makeRequest(
        path: String,
        method: String = "GET",
        query: [String: String?] = [:],
        body: Data? = nil
    ) throws -> URLRequest {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
        if !items.isEmpty { comps.queryItems = items.sorted { $0.name < $1.name } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(try tokenProvider.bearerToken(), forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let ip = psu?.ipAddress { req.setValue(ip, forHTTPHeaderField: "psu-ip-address") }
        if let ua = psu?.userAgent { req.setValue(ua, forHTTPHeaderField: "psu-user-agent") }
        return req
    }

    // MARK: - transport

    private func send<T: Decodable>(_ request: URLRequest, as: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw EnableBankingError(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try EBJSON.decoder.decode(T.self, from: data)
    }

    private func sendVoid(_ request: URLRequest) async throws {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw EnableBankingError(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - endpoints

    public func listAspsps(country: String? = nil, psuType: String? = nil) async throws -> [Aspsp] {
        let req = try makeRequest(path: "/aspsps", query: ["country": country, "psu_type": psuType])
        return try await send(req, as: AspspsResponse.self).aspsps
    }

    public func startAuth(_ input: AuthRequest) async throws -> AuthResponse {
        let req = try makeRequest(path: "/auth", method: "POST", body: try EBJSON.encoder.encode(input))
        return try await send(req, as: AuthResponse.self)
    }

    public func createSession(code: String) async throws -> CreateSessionResponse {
        let body = try JSONSerialization.data(withJSONObject: ["code": code])
        let req = try makeRequest(path: "/sessions", method: "POST", body: body)
        return try await send(req, as: CreateSessionResponse.self)
    }

    public func getSession(_ sessionId: String) async throws -> SessionResponse {
        try await send(try makeRequest(path: "/sessions/\(sessionId)"), as: SessionResponse.self)
    }

    public func closeSession(_ sessionId: String) async throws {
        try await sendVoid(try makeRequest(path: "/sessions/\(sessionId)", method: "DELETE"))
    }

    public func getAccountDetails(_ accountUid: String) async throws -> AccountDetails {
        try await send(try makeRequest(path: "/accounts/\(accountUid)/details"), as: AccountDetails.self)
    }

    public func getAccountBalances(_ accountUid: String) async throws -> BalancesResponse {
        try await send(try makeRequest(path: "/accounts/\(accountUid)/balances"), as: BalancesResponse.self)
    }

    public func getAccountTransactions(
        _ accountUid: String, query: EBTransactionQuery = .init()
    ) async throws -> TransactionsResponse {
        let req = try makeRequest(path: "/accounts/\(accountUid)/transactions", query: [
            "date_from": query.dateFrom,
            "date_to": query.dateTo,
            "transaction_status": query.transactionStatus,
            "continuation_key": query.continuationKey,
            "strategy": query.strategy,
        ])
        return try await send(req, as: TransactionsResponse.self)
    }
}
