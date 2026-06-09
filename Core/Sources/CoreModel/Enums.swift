import Foundation

public enum AccountType: String, Codable, CaseIterable, Sendable {
    case bank
    case broker
    case crypto
    case realEstate = "real_estate"
    case pension
    case other
}

public enum ConnectionStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case active
    case expired
    case error
    case revoked
}

public enum Connector: String, Codable, CaseIterable, Sendable {
    case enablebanking
    case trading212
    case revolutx
    case manual
}

public enum TxDirection: String, Codable, CaseIterable, Sendable {
    case debit
    case credit

    public var flipped: TxDirection { self == .debit ? .credit : .debit }
}

public enum AccountGroupKind: String, Codable, CaseIterable, Sendable {
    case cash
    case savings
    case investment
    case credit
    case other
}

public enum BudgetPeriod: String, Codable, CaseIterable, Sendable {
    case week
    case month
    case year
}

public enum CategorySource: String, Codable, CaseIterable, Sendable {
    case bank
    case rule
    case manual
}

// Category.kind is stored as a String on the model; this is the typed view of the four
// valid kinds (lib/income.ts CATEGORY_KINDS). "income" is load-bearing in Dashboard cash-flow.
public enum CategoryKind: String, Codable, CaseIterable, Sendable {
    case expense
    case income
    case reimbursement
    case refund
}

public enum RuleField: String, Codable, CaseIterable, Sendable {
    case description
    case counterparty
}

public enum RuleMatch: String, Codable, CaseIterable, Sendable {
    case contains
    case equals
    case startsWith
    case endsWith
    case regex
}

public enum SyncRunStatus: String, Codable, CaseIterable, Sendable {
    case running
    case ok
    case partial
    case error
}
