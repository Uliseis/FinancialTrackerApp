import Foundation
import CoreModel

public enum EBHelpers {
    private static let posix = Locale(identifier: "en_US_POSIX")

    // EB dates are either "yyyy-MM-dd" or ISO 8601 datetimes. Parse both, UTC.
    public static func parseDate(_ s: String) -> Date? {
        if s.count == 10, let d = dayFormatter.date(from: s) { return d }
        if let d = isoFull.date(from: s) { return d }
        if let d = isoPlain.date(from: s) { return d }
        return nil
    }

    // ISO8601DateFormatter isn't Sendable; it's thread-safe for the read-only use here.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = posix
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    nonisolated(unsafe) private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func direction(_ indicator: String) -> TxDirection {
        indicator == "CRDT" ? .credit : .debit
    }

    // Signed Decimal amount: debits negative, credits positive. Never goes through Double.
    public static func signedAmount(_ t: EbTransaction) -> Decimal? {
        let raw = t.transactionAmount.amount
        let cleaned = raw.hasPrefix("+") || raw.hasPrefix("-") ? String(raw.dropFirst()) : raw
        guard let magnitude = Decimal(string: cleaned, locale: posix) else { return nil }
        return t.creditDebitIndicator == "DBIT" ? -magnitude : magnitude
    }

    public static func decimal(_ s: String) -> Decimal? {
        Decimal(string: s, locale: posix)
    }

    public static func bookingDate(_ t: EbTransaction) -> Date? {
        let candidate = t.bookingDate ?? t.valueDate ?? t.transactionDate
        return candidate.flatMap(parseDate)
    }

    public static func valueDate(_ t: EbTransaction) -> Date? {
        let candidate = t.valueDate ?? t.transactionDate
        return candidate.flatMap(parseDate)
    }

    public static func externalId(_ t: EbTransaction, fallback: String) -> String {
        t.transactionId ?? t.entryReference ?? fallback
    }

    public static func description(_ t: EbTransaction) -> String {
        if let r = t.remittanceInformation, !r.isEmpty { return r.joined(separator: " ") }
        if let n = t.note { return n }
        if let d = t.bankTransactionCode?.description { return d }
        return ""
    }

    public static func counterparty(_ t: EbTransaction) -> String? {
        t.creditDebitIndicator == "CRDT" ? t.debtor?.name : t.creditor?.name
    }

    private static let balanceOrder = ["CLBD", "ITBD", "ITAV", "CLAV", "OPAV", "OPBD", "FWAV", "PRCD", "XPCD", "INFO"]
    public static func preferredBalance(_ balances: [Balance]) -> Balance? {
        for t in balanceOrder {
            if let found = balances.first(where: { $0.balanceType == t }) { return found }
        }
        return balances.first
    }

    public static func iban(ofSession a: SessionAccount) -> String? { a.accountId?.iban }
    public static func iban(ofDetails a: AccountDetails) -> String? { a.accountId?.iban }

    public static func sessionAccounts(_ s: any EBSessionPayload) -> [SessionAccount] {
        if let data = s.accountsData, !data.isEmpty { return data }
        return (s.accounts ?? []).compactMap(\.uid).map { uid in
            SessionAccount(uid: uid, identificationHash: nil, accountId: nil, details: nil,
                           usage: nil, cashAccountType: nil, product: nil, currency: nil,
                           name: nil, productName: nil)
        }
    }

    public static func normalizeCurrency(_ c: String?) -> String? {
        guard let c, c.count == 3, c != "XXX",
              c.allSatisfy({ $0.isUppercase && $0.isLetter }) else { return nil }
        return c
    }
}
