import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct Trading212Error: Error, Equatable {
    public let status: Int
    public let body: String
}

public struct Trading212Credentials: Equatable, Sendable {
    public let key: String
    public let secret: String
    public init(key: String, secret: String) {
        self.key = key
        self.secret = secret
    }

    // HTTP Basic: base64(key:secret).
    public var basicAuthHeader: String {
        "Basic " + Data("\(key):\(secret)".utf8).base64EncodedString()
    }
}

// What /equity/account/summary gives us. Trading 212 reports its own cost basis, so the
// account's P&L can be cross-checked against the ledger-derived one rather than trusted blind.
public struct Trading212Summary: Equatable, Sendable {
    public let totalValueEur: Decimal
    public let currency: String
    public let investedEur: Decimal?
    public let costBasisEur: Decimal?
    public let unrealizedPnlEur: Decimal?
    public let realizedPnlEur: Decimal?
    public let cashEur: Decimal?
}

public struct Trading212Client: Sendable {
    public let baseURL: URL
    let credentials: Trading212Credentials
    let session: URLSession

    public init(
        credentials: Trading212Credentials,
        baseURL: URL = URL(string: "https://live.trading212.com/api/v0")!,
        session: URLSession = .shared
    ) {
        self.credentials = credentials
        self.baseURL = baseURL
        self.session = session
    }

    func makeRequest(path: String) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "GET"
        req.setValue(credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    public func accountSummary() async throws -> Trading212Summary {
        let (data, response) = try await session.data(for: makeRequest(path: "equity/account/summary"))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Trading212Error(status: status, body: String(decoding: data, as: UTF8.self))
        }
        return try Self.decodeSummary(data)
    }

    // Split out so the shape is testable without a live key.
    public static func decodeSummary(_ data: Data) throws -> Trading212Summary {
        let raw = try JSONDecoder().decode(RawSummary.self, from: data)
        let cash = raw.cash
        let cashTotal: Decimal? = cash.map {
            ($0.availableToTrade ?? 0) + ($0.inPies ?? 0) + ($0.reservedForOrders ?? 0)
        }
        return Trading212Summary(
            totalValueEur: raw.totalValue ?? 0,
            currency: raw.currency ?? "EUR",
            investedEur: raw.investments?.currentValue,
            costBasisEur: raw.investments?.totalCost,
            unrealizedPnlEur: raw.investments?.unrealizedProfitLoss,
            realizedPnlEur: raw.investments?.realizedProfitLoss,
            cashEur: cashTotal
        )
    }

    struct RawSummary: Decodable {
        let totalValue: Decimal?
        let currency: String?
        let cash: RawCash?
        let investments: RawInvestments?
    }
    struct RawCash: Decodable {
        let availableToTrade: Decimal?
        let inPies: Decimal?
        let reservedForOrders: Decimal?
    }
    struct RawInvestments: Decodable {
        let currentValue: Decimal?
        let totalCost: Decimal?
        let unrealizedProfitLoss: Decimal?
        let realizedProfitLoss: Decimal?
    }
}
