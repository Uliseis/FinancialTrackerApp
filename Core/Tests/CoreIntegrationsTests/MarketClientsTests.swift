import XCTest
@testable import CoreIntegrations

final class MarketClientsTests: XCTestCase {
    func testBasicAuthHeaderIsBase64OfKeyColonSecret() {
        let creds = Trading212Credentials(key: "abc", secret: "def")
        XCTAssertEqual(creds.basicAuthHeader, "Basic " + Data("abc:def".utf8).base64EncodedString())
    }

    func testTrading212RequestTargetsSummaryWithAuth() {
        let client = Trading212Client(credentials: .init(key: "k", secret: "s"))
        let req = client.makeRequest(path: "equity/account/summary")
        XCTAssertEqual(
            req.url?.absoluteString,
            "https://live.trading212.com/api/v0/equity/account/summary")
        XCTAssertEqual(req.httpMethod, "GET")
        XCTAssertTrue(req.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
    }

    func testDecodeSummarySumsCashBuckets() throws {
        let json = Data("""
        {
          "currency": "EUR",
          "totalValue": 19390.42,
          "cash": { "availableToTrade": 900.00, "inPies": 43.64, "reservedForOrders": 0 },
          "investments": {
            "currentValue": 18446.78, "totalCost": 15542.51,
            "unrealizedProfitLoss": 2912.40, "realizedProfitLoss": 4738.31
          }
        }
        """.utf8)
        let s = try Trading212Client.decodeSummary(json)
        XCTAssertEqual(s.totalValueEur, Decimal(string: "19390.42"))
        XCTAssertEqual(s.cashEur, Decimal(string: "943.64"))
        XCTAssertEqual(s.costBasisEur, Decimal(string: "15542.51"))
        XCTAssertEqual(s.realizedPnlEur, Decimal(string: "4738.31"))
    }

    func testDecodeSummaryToleratesMissingSections() throws {
        let s = try Trading212Client.decodeSummary(Data(#"{"totalValue": 10}"#.utf8))
        XCTAssertEqual(s.totalValueEur, 10)
        XCTAssertNil(s.cashEur)
        XCTAssertNil(s.costBasisEur)
        XCTAssertEqual(s.currency, "EUR")
    }

    func testCryptoRequestSortsIdsAndAsksForEur() {
        let req = CryptoPriceClient().makeRequest(coinIds: ["ethereum", "bitcoin"])
        XCTAssertEqual(
            req.url?.absoluteString,
            "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=eur")
    }

    func testDecodePricesPicksTheRequestedCurrency() throws {
        let json = Data(#"{"bitcoin":{"eur":57176.0,"usd":62000.0},"ethereum":{"eur":1721.09}}"#.utf8)
        let prices = try CryptoPriceClient.decodePrices(json)
        XCTAssertEqual(prices["bitcoin"], Decimal(string: "57176.0"))
        XCTAssertEqual(prices["ethereum"], Decimal(string: "1721.09"))
        XCTAssertEqual(prices.count, 2)
    }

    func testDecodePricesSkipsCoinsMissingThatCurrency() throws {
        let prices = try CryptoPriceClient.decodePrices(Data(#"{"bitcoin":{"usd":62000.0}}"#.utf8))
        XCTAssertTrue(prices.isEmpty)
    }
}
