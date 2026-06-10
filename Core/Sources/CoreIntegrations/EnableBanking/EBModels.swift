import Foundation

// Wire models for the Enable Banking REST API. Monetary amounts arrive as JSON strings
// ("123.45") and stay String here — conversion to Decimal happens in EBHelpers so the
// numeric boundary is explicit and never goes through Double.

public enum EBJSON {
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
}

public struct EBAmount: Codable, Equatable, Sendable {
    public let currency: String
    public let amount: String
}

public struct EBAccountIdentification: Codable, Equatable, Sendable {
    public let iban: String?
    public let other: Other?
    public struct Other: Codable, Equatable, Sendable {
        public let identification: String
        public let schemeName: String?
        public let issuer: String?
    }
}

public struct EBPartyIdentification: Codable, Equatable, Sendable {
    public let name: String?
}

public struct EBAuthMethod: Codable, Equatable, Sendable {
    public let name: String?
    public let psuType: String?
    public let approach: String?
}

public struct Aspsp: Codable, Equatable, Sendable {
    public let name: String
    public let country: String
    public let logo: String?
    public let psuTypes: [String]?
    public let authMethods: [EBAuthMethod]?
    public let maximumConsentValidity: Int?
    public let beta: Bool?
    public let bic: String?
}

public struct AspspsResponse: Codable, Equatable, Sendable {
    public let aspsps: [Aspsp]
}

public struct AuthRequest: Codable, Equatable, Sendable {
    public struct Access: Codable, Equatable, Sendable {
        public let validUntil: String
        public let balances: Bool?
        public let transactions: Bool?
        public init(validUntil: String, balances: Bool? = true, transactions: Bool? = true) {
            self.validUntil = validUntil
            self.balances = balances
            self.transactions = transactions
        }
    }
    public struct Aspsp: Codable, Equatable, Sendable {
        public let name: String
        public let country: String
        public init(name: String, country: String) { self.name = name; self.country = country }
    }
    public let access: Access
    public let aspsp: Aspsp
    public let state: String
    public let redirectUrl: String
    public let psuType: String
    public let language: String?
    public let authMethod: String?

    public init(access: Access, aspsp: Aspsp, state: String, redirectUrl: String,
                psuType: String, language: String? = nil, authMethod: String? = nil) {
        self.access = access; self.aspsp = aspsp; self.state = state
        self.redirectUrl = redirectUrl; self.psuType = psuType
        self.language = language; self.authMethod = authMethod
    }
}

public struct AuthResponse: Codable, Equatable, Sendable {
    public let url: String
    public let authorizationId: String
}

public struct SessionAccount: Codable, Equatable, Sendable {
    public let uid: String?
    public let identificationHash: String?
    public let accountId: EBAccountIdentification?
    public let details: String?
    public let usage: String?
    public let cashAccountType: String?
    public let product: String?
    public let currency: String?
    public let name: String?
    public let productName: String?
}

public struct SessionAccess: Codable, Equatable, Sendable {
    public let validUntil: String?
    public let balances: Bool?
    public let transactions: Bool?
}

public struct SessionAspsp: Codable, Equatable, Sendable {
    public let name: String
    public let country: String
}

// The `accounts` array has historically carried either bare uid strings or {uid: …}
// objects — the web's sessionAccountsOf handles both, so the wire type does too.
public struct SessionAccountRef: Codable, Equatable, Sendable {
    public let uid: String?

    private struct Boxed: Codable { let uid: String? }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            uid = string
        } else {
            uid = (try? container.decode(Boxed.self))?.uid
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(uid)
    }
}

// Shared shape of the two session payloads so helpers and the sync work on either.
public protocol EBSessionPayload {
    var status: String { get }
    var accounts: [SessionAccountRef]? { get }
    var accountsData: [SessionAccount]? { get }
    var access: SessionAccess? { get }
    var aspsp: SessionAspsp? { get }
}

// POST /sessions. The one response that carries session_id — and the one place it is
// genuinely required: a created session without an id is unusable, so a missing key
// must fail the decode loudly rather than limp on.
public struct CreateSessionResponse: Codable, Equatable, Sendable, EBSessionPayload {
    public let sessionId: String
    public let status: String
    public let accounts: [SessionAccountRef]?
    public let accountsData: [SessionAccount]?
    public let access: SessionAccess?
    public let aspsp: SessionAspsp?
    public let psuType: String?
    public let created: String?
    public let authorized: String?
    public let closed: String?
}

// GET /sessions/{id}. Verified against the live API 2026-06-10: there is NO session_id
// in this payload (it's in the URL), and accounts_data entries are slim (uid +
// identification hashes only). Modeled separately so the absence is a compile-time
// fact, not an optional somebody forgets is always nil.
public struct SessionResponse: Codable, Equatable, Sendable, EBSessionPayload {
    public let status: String
    public let accounts: [SessionAccountRef]?
    public let accountsData: [SessionAccount]?
    public let access: SessionAccess?
    public let aspsp: SessionAspsp?
    public let psuType: String?
    public let created: String?
    public let authorized: String?
    public let closed: String?
}

public struct AccountDetails: Codable, Equatable, Sendable {
    public let accountId: EBAccountIdentification?
    public let name: String?
    public let details: String?
    public let usage: String?
    public let cashAccountType: String?
    public let product: String?
    public let currency: String
    public let uid: String?
}

public struct Balance: Codable, Equatable, Sendable {
    public let name: String?
    public let balanceAmount: EBAmount
    public let balanceType: String
    public let lastChangeDateTime: String?
    public let referenceDate: String?
}

public struct BalancesResponse: Codable, Equatable, Sendable {
    public let balances: [Balance]
}

public struct EbTransaction: Codable, Equatable, Sendable {
    public let entryReference: String?
    public let transactionAmount: EBAmount
    public let creditor: EBPartyIdentification?
    public let creditorAccount: EBAccountIdentification?
    public let debtor: EBPartyIdentification?
    public let debtorAccount: EBAccountIdentification?
    public let bankTransactionCode: BankTransactionCode?
    public let creditDebitIndicator: String
    public let status: String?
    public let bookingDate: String?
    public let valueDate: String?
    public let transactionDate: String?
    public let referenceNumber: String?
    public let remittanceInformation: [String]?
    public let note: String?
    public let transactionId: String?

    public struct BankTransactionCode: Codable, Equatable, Sendable {
        public let description: String?
        public let code: String?
        public let subCode: String?
    }
}

public struct TransactionsResponse: Codable, Equatable, Sendable {
    public let transactions: [EbTransaction]
    public let continuationKey: String?
}

public struct PsuHeaders: Equatable, Sendable {
    public let ipAddress: String?
    public let userAgent: String?
    public init(ipAddress: String? = nil, userAgent: String? = nil) {
        self.ipAddress = ipAddress; self.userAgent = userAgent
    }
}
