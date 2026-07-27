import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CryptoPriceError: Error, Equatable {
    public let status: Int
    public let body: String
}

public protocol CryptoPriceSource: Sendable {
    func prices(for coinIds: [String]) async throws -> [String: Decimal]
}

// CoinGecko's public simple/price endpoint: no key, no account, one GET for many coins.
// Only the coin id and EUR go out — nothing about the holding or the user.
public struct CryptoPriceClient: CryptoPriceSource, Sendable {
    public let baseURL: URL
    let session: URLSession

    public init(
        baseURL: URL = URL(string: "https://api.coingecko.com/api/v3")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func makeRequest(coinIds: [String], currency: String = "eur") -> URLRequest {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("simple/price"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "ids", value: coinIds.sorted().joined(separator: ",")),
            URLQueryItem(name: "vs_currencies", value: currency),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    // coin id -> price in EUR.
    public func prices(for coinIds: [String]) async throws -> [String: Decimal] {
        if coinIds.isEmpty { return [:] }
        let (data, response) = try await session.data(for: makeRequest(coinIds: coinIds))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw CryptoPriceError(status: status, body: String(decoding: data, as: UTF8.self))
        }
        return try Self.decodePrices(data)
    }

    public static func decodePrices(_ data: Data, currency: String = "eur") throws -> [String: Decimal] {
        let raw = try JSONDecoder().decode([String: [String: Decimal]].self, from: data)
        return raw.compactMapValues { $0[currency] }
    }
}
