import XCTest
@testable import CoreIntegrations
@testable import CoreModel

final class EBHelpersTests: XCTestCase {
    private func tx(_ json: String) throws -> EbTransaction {
        try EBJSON.decoder.decode(EbTransaction.self, from: Data(json.utf8))
    }

    func test_signedAmount_debitNegative_creditPositive() throws {
        let debit = try tx(#"{"transaction_amount":{"currency":"EUR","amount":"42.50"},"credit_debit_indicator":"DBIT"}"#)
        let credit = try tx(#"{"transaction_amount":{"currency":"EUR","amount":"42.50"},"credit_debit_indicator":"CRDT"}"#)
        XCTAssertEqual(EBHelpers.signedAmount(debit), Decimal(string: "-42.50"))
        XCTAssertEqual(EBHelpers.signedAmount(credit), Decimal(string: "42.50"))
    }

    func test_signedAmount_stripsLeadingSign() throws {
        let t = try tx(#"{"transaction_amount":{"currency":"EUR","amount":"+7.00"},"credit_debit_indicator":"DBIT"}"#)
        XCTAssertEqual(EBHelpers.signedAmount(t), Decimal(string: "-7"))
    }

    func test_direction_mapsToCoreModel() {
        XCTAssertEqual(EBHelpers.direction("CRDT"), TxDirection.credit)
        XCTAssertEqual(EBHelpers.direction("DBIT"), TxDirection.debit)
    }

    func test_bookingDate_fallbackOrder() throws {
        let onlyValue = try tx(#"{"transaction_amount":{"currency":"EUR","amount":"1"},"credit_debit_indicator":"DBIT","value_date":"2026-05-10"}"#)
        let d = try XCTUnwrap(EBHelpers.bookingDate(onlyValue))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(cal.component(.year, from: d), 2026)
        XCTAssertEqual(cal.component(.month, from: d), 5)
        XCTAssertEqual(cal.component(.day, from: d), 10)
    }

    func test_parseDate_isoDateTime() {
        XCTAssertNotNil(EBHelpers.parseDate("2026-09-01T00:00:00.000+00:00"))
        XCTAssertNotNil(EBHelpers.parseDate("2026-09-01T12:34:56+00:00"))
        XCTAssertNil(EBHelpers.parseDate("garbage"))
    }

    func test_externalId_prefersTransactionId() throws {
        let withId = try tx(#"{"transaction_amount":{"currency":"EUR","amount":"1"},"credit_debit_indicator":"DBIT","transaction_id":"tx-9","entry_reference":"ref-9"}"#)
        let withRef = try tx(#"{"transaction_amount":{"currency":"EUR","amount":"1"},"credit_debit_indicator":"DBIT","entry_reference":"ref-9"}"#)
        let bare = try tx(#"{"transaction_amount":{"currency":"EUR","amount":"1"},"credit_debit_indicator":"DBIT"}"#)
        XCTAssertEqual(EBHelpers.externalId(withId, fallback: "fb"), "tx-9")
        XCTAssertEqual(EBHelpers.externalId(withRef, fallback: "fb"), "ref-9")
        XCTAssertEqual(EBHelpers.externalId(bare, fallback: "fb"), "fb")
    }

    func test_description_remittanceThenNoteThenCode() throws {
        let remit = try tx(#"{"transaction_amount":{"currency":"EUR","amount":"1"},"credit_debit_indicator":"DBIT","remittance_information":["A","B"]}"#)
        let note = try tx(#"{"transaction_amount":{"currency":"EUR","amount":"1"},"credit_debit_indicator":"DBIT","note":"hello"}"#)
        let code = try tx(#"{"transaction_amount":{"currency":"EUR","amount":"1"},"credit_debit_indicator":"DBIT","bank_transaction_code":{"description":"Fee"}}"#)
        XCTAssertEqual(EBHelpers.description(remit), "A B")
        XCTAssertEqual(EBHelpers.description(note), "hello")
        XCTAssertEqual(EBHelpers.description(code), "Fee")
    }

    func test_counterparty_sideDependsOnDirection() throws {
        let debit = try tx(#"{"transaction_amount":{"currency":"EUR","amount":"1"},"credit_debit_indicator":"DBIT","creditor":{"name":"Shop"},"debtor":{"name":"Me"}}"#)
        let credit = try tx(#"{"transaction_amount":{"currency":"EUR","amount":"1"},"credit_debit_indicator":"CRDT","creditor":{"name":"Shop"},"debtor":{"name":"Payer"}}"#)
        XCTAssertEqual(EBHelpers.counterparty(debit), "Shop")
        XCTAssertEqual(EBHelpers.counterparty(credit), "Payer")
    }

    func test_preferredBalance_priorityOrder() throws {
        let resp = try EBJSON.decoder.decode(BalancesResponse.self, from: Data(#"""
        {"balances":[
          {"balance_amount":{"currency":"EUR","amount":"5"},"balance_type":"INFO"},
          {"balance_amount":{"currency":"EUR","amount":"10"},"balance_type":"CLBD"},
          {"balance_amount":{"currency":"EUR","amount":"8"},"balance_type":"ITAV"}]}
        """#.utf8))
        XCTAssertEqual(EBHelpers.preferredBalance(resp.balances)?.balanceType, "CLBD")
    }

    func test_normalizeCurrency() {
        XCTAssertEqual(EBHelpers.normalizeCurrency("EUR"), "EUR")
        XCTAssertNil(EBHelpers.normalizeCurrency("XXX"))
        XCTAssertNil(EBHelpers.normalizeCurrency("eur"))
        XCTAssertNil(EBHelpers.normalizeCurrency("EU"))
        XCTAssertNil(EBHelpers.normalizeCurrency(nil))
    }

    func test_sessionAccounts_fallbackToUidList() throws {
        let s = try EBJSON.decoder.decode(SessionResponse.self, from: Data(#"""
        {"session_id":"s","status":"AUTHORIZED","accounts":["uid-a","uid-b"],
         "access":{},"aspsp":{"name":"B","country":"ES"}}
        """#.utf8))
        let accs = EBHelpers.sessionAccounts(s)
        XCTAssertEqual(accs.map(\.uid), ["uid-a", "uid-b"])
    }
}
