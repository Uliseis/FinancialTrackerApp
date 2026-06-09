import XCTest
@testable import CoreIntegrations

final class EBModelsDecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try EBJSON.decoder.decode(T.self, from: Data(json.utf8))
    }

    func test_aspsps_snakeCase() throws {
        let r = try decode(AspspsResponse.self, """
        {"aspsps":[{"name":"BBVA","country":"ES","psu_types":["personal"],
          "maximum_consent_validity":7776000,"beta":false,
          "auth_methods":[{"name":"redirect","psu_type":"personal","approach":"REDIRECT"}]}]}
        """)
        XCTAssertEqual(r.aspsps.count, 1)
        XCTAssertEqual(r.aspsps[0].name, "BBVA")
        XCTAssertEqual(r.aspsps[0].psuTypes, ["personal"])
        XCTAssertEqual(r.aspsps[0].maximumConsentValidity, 7_776_000)
        XCTAssertEqual(r.aspsps[0].authMethods?.first?.approach, "REDIRECT")
    }

    func test_session_withAccountsData() throws {
        let s = try decode(SessionResponse.self, """
        {"session_id":"sess-1","status":"AUTHORIZED","accounts":["uid-1"],
         "accounts_data":[{"uid":"uid-1","account_id":{"iban":"ES1234"},"currency":"EUR","name":"Main"}],
         "access":{"valid_until":"2026-09-01T00:00:00.000+00:00","transactions":true},
         "aspsp":{"name":"BBVA","country":"ES"},"psu_type":"personal"}
        """)
        XCTAssertEqual(s.sessionId, "sess-1")
        XCTAssertEqual(s.status, "AUTHORIZED")
        XCTAssertEqual(s.accountsData?.first?.accountId?.iban, "ES1234")
        XCTAssertEqual(s.access.validUntil, "2026-09-01T00:00:00.000+00:00")
    }

    func test_accountDetails_andBalances() throws {
        let d = try decode(AccountDetails.self, """
        {"account_id":{"iban":"ES99"},"name":"Checking","currency":"EUR","cash_account_type":"CACC"}
        """)
        XCTAssertEqual(d.accountId?.iban, "ES99")
        XCTAssertEqual(d.cashAccountType, "CACC")

        let b = try decode(BalancesResponse.self, """
        {"balances":[{"name":"Closing","balance_amount":{"currency":"EUR","amount":"1234.56"},
          "balance_type":"CLBD","reference_date":"2026-06-01"}]}
        """)
        XCTAssertEqual(b.balances.first?.balanceType, "CLBD")
        XCTAssertEqual(b.balances.first?.balanceAmount.amount, "1234.56")
    }

    func test_transactions_creditDebitAndContinuation() throws {
        let t = try decode(TransactionsResponse.self, """
        {"transactions":[
          {"transaction_amount":{"currency":"EUR","amount":"42.00"},
           "credit_debit_indicator":"DBIT","status":"BOOK","booking_date":"2026-05-20",
           "creditor":{"name":"Acme"},"remittance_information":["Invoice","123"],
           "transaction_id":"tx-1","bank_transaction_code":{"description":"Card payment"}}],
         "continuation_key":"next-page"}
        """)
        XCTAssertEqual(t.transactions.count, 1)
        XCTAssertEqual(t.transactions[0].creditDebitIndicator, "DBIT")
        XCTAssertEqual(t.transactions[0].transactionAmount.amount, "42.00")
        XCTAssertEqual(t.transactions[0].remittanceInformation, ["Invoice", "123"])
        XCTAssertEqual(t.transactions[0].bankTransactionCode?.description, "Card payment")
        XCTAssertEqual(t.continuationKey, "next-page")
    }
}
