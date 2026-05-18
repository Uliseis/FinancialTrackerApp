import Foundation

public struct DumpDocument: Codable, Sendable {
    public let exportedAt: String
    public let schemaVersion: Int
    public let connections: [DumpConnection]
    public let accountGroups: [DumpAccountGroup]
    public let accountSpaces: [DumpAccountSpace]
    public let accounts: [DumpAccount]
    public let categories: [DumpCategory]
    public let categoryRules: [DumpCategoryRule]
    public let transferRoutes: [DumpTransferRoute]
    public let budgets: [DumpBudget]
    public let fxRates: [DumpFxRate]
    public let transferGroups: [DumpTransferGroup]
    public let transactions: [DumpTransaction]
    public let sharedExpenseGroups: [DumpSharedExpenseGroup]
    public let portfolioValuations: [DumpPortfolioValuation]
    public let syncRuns: [DumpSyncRun]

    public init(
        exportedAt: String,
        schemaVersion: Int,
        connections: [DumpConnection] = [],
        accountGroups: [DumpAccountGroup] = [],
        accountSpaces: [DumpAccountSpace] = [],
        accounts: [DumpAccount] = [],
        categories: [DumpCategory] = [],
        categoryRules: [DumpCategoryRule] = [],
        transferRoutes: [DumpTransferRoute] = [],
        budgets: [DumpBudget] = [],
        fxRates: [DumpFxRate] = [],
        transferGroups: [DumpTransferGroup] = [],
        transactions: [DumpTransaction] = [],
        sharedExpenseGroups: [DumpSharedExpenseGroup] = [],
        portfolioValuations: [DumpPortfolioValuation] = [],
        syncRuns: [DumpSyncRun] = []
    ) {
        self.exportedAt = exportedAt
        self.schemaVersion = schemaVersion
        self.connections = connections
        self.accountGroups = accountGroups
        self.accountSpaces = accountSpaces
        self.accounts = accounts
        self.categories = categories
        self.categoryRules = categoryRules
        self.transferRoutes = transferRoutes
        self.budgets = budgets
        self.fxRates = fxRates
        self.transferGroups = transferGroups
        self.transactions = transactions
        self.sharedExpenseGroups = sharedExpenseGroups
        self.portfolioValuations = portfolioValuations
        self.syncRuns = syncRuns
    }
}

public struct DumpConnection: Codable, Sendable {
    public let id: String
    public let connector: String
    public let institutionId: String?
    public let institutionName: String?
    public let sessionId: String?
    public let accessTokenEnc: String?
    public let refreshTokenEnc: String?
    public let metadata: JSONValue?
    public let status: String
    public let expiresAt: String?
    public let lastSyncAt: String?
    public let lastError: String?
    public let createdAt: String
    public let updatedAt: String
}

public struct DumpAccountGroup: Codable, Sendable {
    public let id: String
    public let name: String
    public let color: String?
    public let kind: String
    public let sortOrder: Int
    public let createdAt: String
    public let updatedAt: String
}

public struct DumpAccountSpace: Codable, Sendable {
    public let id: String
    public let name: String
    public let color: String?
    public let isDefault: Bool
    public let sortOrder: Int
    public let createdAt: String
    public let updatedAt: String
}

public struct DumpAccount: Codable, Sendable {
    public let id: String
    public let connectionId: String?
    public let groupId: String?
    public let spaceId: String?
    public let externalId: String
    public let type: String
    public let institution: String
    public let name: String
    public let currency: String
    public let iban: String?
    public let balance: String?
    public let balanceUpdatedAt: String?
    public let metadata: JSONValue?
    public let archived: Bool
    public let excluded: Bool
    public let manualOpeningBalance: String?
    public let balanceAnchor: String?
    public let balanceAnchorAt: String?
    public let createdAt: String
}

public struct DumpCategory: Codable, Sendable {
    public let id: String
    public let name: String
    public let parentId: String?
    public let kind: String
    public let color: String?
    public let createdAt: String
}

public struct DumpCategoryRule: Codable, Sendable {
    public let id: String
    public let pattern: String
    public let field: String
    public let matchType: String
    public let categoryId: String
    public let priority: Int
    public let createdAt: String
}

public struct DumpTransferRoute: Codable, Sendable {
    public let id: String
    public let pattern: String
    public let field: String
    public let matchType: String
    public let sourceAccountId: String?
    public let targetAccountId: String
    public let direction: String?
    public let priority: Int
    public let enabled: Bool
    public let createdAt: String
    public let updatedAt: String
}

public struct DumpBudget: Codable, Sendable {
    public let id: String
    public let categoryId: String
    public let amountEur: String
    public let period: String
    public let startsOn: String
    public let active: Bool
    public let createdAt: String
    public let updatedAt: String
}

public struct DumpFxRate: Codable, Sendable {
    public let id: String
    public let date: String
    public let currency: String
    public let rate: String
    public let createdAt: String
}

public struct DumpTransferGroup: Codable, Sendable {
    public let id: String
    public let pairedAt: String?
    public let routeId: String?
    public let createdAt: String
}

public struct DumpTransaction: Codable, Sendable {
    public let id: String
    public let accountId: String
    public let externalId: String
    public let bookedAt: String
    public let valueAt: String?
    public let amount: String
    public let currency: String
    public let amountEur: String?
    public let fxRateUsed: String?
    public let direction: String
    public let description: String?
    public let counterparty: String?
    public let categoryId: String?
    public let categorySource: String?
    public let isTransfer: Bool
    public let transferGroupId: String?
    public let routedFromTxId: String?
    public let routeId: String?
    public let sharedExpenseGroupId: String?
    public let raw: JSONValue?
    public let createdAt: String
}

public struct DumpSharedExpenseGroup: Codable, Sendable {
    public let id: String
    public let label: String
    public let primaryTxId: String
    public let attributionMonth: String?
    public let createdAt: String
    public let updatedAt: String
}

public struct DumpPortfolioValuation: Codable, Sendable {
    public let id: String
    public let accountId: String
    public let asOf: String
    public let marketValueEur: String
    public let cashValueEur: String?
    public let notes: String?
    public let createdAt: String
    public let updatedAt: String
}

public struct DumpSyncRun: Codable, Sendable {
    public let id: String
    public let connector: String
    public let connectionId: String?
    public let startedAt: String
    public let finishedAt: String?
    public let status: String
    public let insertedTransactions: Int
    public let error: String?
    public let raw: JSONValue?
}
