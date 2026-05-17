import Foundation
import SwiftData

@Model
public final class Connection {
    @Attribute(.unique) public var id: UUID
    public var connector: Connector
    public var institutionId: String?
    public var institutionName: String?
    public var sessionId: String?
    public var accessTokenEnc: String?
    public var refreshTokenEnc: String?
    public var metadataJSON: Data?
    public var status: ConnectionStatus
    public var expiresAt: Date?
    public var lastSyncAt: Date?
    public var lastError: String?
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Account.connection)
    public var accounts: [Account] = []

    @Relationship(deleteRule: .nullify, inverse: \SyncRun.connection)
    public var syncRuns: [SyncRun] = []

    public init(
        id: UUID = UUID(),
        connector: Connector,
        institutionId: String? = nil,
        institutionName: String? = nil,
        sessionId: String? = nil,
        accessTokenEnc: String? = nil,
        refreshTokenEnc: String? = nil,
        metadataJSON: Data? = nil,
        status: ConnectionStatus = .pending,
        expiresAt: Date? = nil,
        lastSyncAt: Date? = nil,
        lastError: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.connector = connector
        self.institutionId = institutionId
        self.institutionName = institutionName
        self.sessionId = sessionId
        self.accessTokenEnc = accessTokenEnc
        self.refreshTokenEnc = refreshTokenEnc
        self.metadataJSON = metadataJSON
        self.status = status
        self.expiresAt = expiresAt
        self.lastSyncAt = lastSyncAt
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class AccountGroup {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var color: String?
    public var kind: AccountGroupKind
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Account.group)
    public var accounts: [Account] = []

    public init(
        id: UUID = UUID(),
        name: String,
        color: String? = nil,
        kind: AccountGroupKind = .other,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.kind = kind
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class AccountSpace {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var color: String?
    public var isDefault: Bool
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Account.space)
    public var accounts: [Account] = []

    public init(
        id: UUID = UUID(),
        name: String,
        color: String? = nil,
        isDefault: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class Account {
    @Attribute(.unique) public var id: UUID
    public var connection: Connection?
    public var group: AccountGroup?
    public var space: AccountSpace?
    public var externalId: String
    public var type: AccountType
    public var institution: String
    public var name: String
    public var currency: String
    public var iban: String?
    public var balance: Decimal?
    public var balanceUpdatedAt: Date?
    public var metadataJSON: Data?
    public var archived: Bool
    public var excluded: Bool
    public var manualOpeningBalance: Decimal?
    public var balanceAnchor: Decimal?
    public var balanceAnchorAt: Date?
    public var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
    public var transactions: [Transaction] = []

    @Relationship(deleteRule: .cascade, inverse: \PortfolioValuation.account)
    public var valuations: [PortfolioValuation] = []

    @Relationship(deleteRule: .cascade, inverse: \TransferRoute.targetAccount)
    public var incomingRoutes: [TransferRoute] = []

    @Relationship(deleteRule: .cascade, inverse: \TransferRoute.sourceAccount)
    public var outgoingRoutes: [TransferRoute] = []

    public init(
        id: UUID = UUID(),
        connection: Connection? = nil,
        group: AccountGroup? = nil,
        space: AccountSpace? = nil,
        externalId: String,
        type: AccountType,
        institution: String,
        name: String,
        currency: String,
        iban: String? = nil,
        balance: Decimal? = nil,
        balanceUpdatedAt: Date? = nil,
        metadataJSON: Data? = nil,
        archived: Bool = false,
        excluded: Bool = false,
        manualOpeningBalance: Decimal? = nil,
        balanceAnchor: Decimal? = nil,
        balanceAnchorAt: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.connection = connection
        self.group = group
        self.space = space
        self.externalId = externalId
        self.type = type
        self.institution = institution
        self.name = name
        self.currency = currency
        self.iban = iban
        self.balance = balance
        self.balanceUpdatedAt = balanceUpdatedAt
        self.metadataJSON = metadataJSON
        self.archived = archived
        self.excluded = excluded
        self.manualOpeningBalance = manualOpeningBalance
        self.balanceAnchor = balanceAnchor
        self.balanceAnchorAt = balanceAnchorAt
        self.createdAt = createdAt
    }
}

@Model
public final class Category {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var parent: Category?
    public var kind: String
    public var color: String?
    public var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Category.parent)
    public var children: [Category] = []

    @Relationship(deleteRule: .cascade, inverse: \CategoryRule.category)
    public var rules: [CategoryRule] = []

    @Relationship(deleteRule: .cascade, inverse: \Budget.category)
    public var budgets: [Budget] = []

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    public var transactions: [Transaction] = []

    public init(
        id: UUID = UUID(),
        name: String,
        parent: Category? = nil,
        kind: String = "expense",
        color: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.parent = parent
        self.kind = kind
        self.color = color
        self.createdAt = createdAt
    }
}

@Model
public final class CategoryRule {
    @Attribute(.unique) public var id: UUID
    public var pattern: String
    public var field: RuleField
    public var matchType: RuleMatch
    public var category: Category?
    public var priority: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        pattern: String,
        field: RuleField = .description,
        matchType: RuleMatch = .contains,
        category: Category? = nil,
        priority: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.pattern = pattern
        self.field = field
        self.matchType = matchType
        self.category = category
        self.priority = priority
        self.createdAt = createdAt
    }
}

@Model
public final class TransferRoute {
    @Attribute(.unique) public var id: UUID
    public var pattern: String
    public var field: RuleField
    public var matchType: RuleMatch
    public var sourceAccount: Account?
    public var targetAccount: Account?
    public var direction: TxDirection?
    public var priority: Int
    public var enabled: Bool
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Transaction.route)
    public var routedTransactions: [Transaction] = []

    @Relationship(deleteRule: .nullify, inverse: \TransferGroup.route)
    public var spawnedGroups: [TransferGroup] = []

    public init(
        id: UUID = UUID(),
        pattern: String,
        field: RuleField = .description,
        matchType: RuleMatch = .contains,
        sourceAccount: Account? = nil,
        targetAccount: Account? = nil,
        direction: TxDirection? = nil,
        priority: Int = 0,
        enabled: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.pattern = pattern
        self.field = field
        self.matchType = matchType
        self.sourceAccount = sourceAccount
        self.targetAccount = targetAccount
        self.direction = direction
        self.priority = priority
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class TransferGroup {
    @Attribute(.unique) public var id: UUID
    public var auto: Bool
    public var route: TransferRoute?
    public var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Transaction.transferGroup)
    public var transactions: [Transaction] = []

    public init(
        id: UUID = UUID(),
        auto: Bool = true,
        route: TransferRoute? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.auto = auto
        self.route = route
        self.createdAt = createdAt
    }
}

@Model
public final class Budget {
    @Attribute(.unique) public var id: UUID
    public var category: Category?
    public var amountEur: Decimal
    public var period: BudgetPeriod
    public var startsOn: Date
    public var active: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        category: Category? = nil,
        amountEur: Decimal,
        period: BudgetPeriod = .month,
        startsOn: Date,
        active: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.category = category
        self.amountEur = amountEur
        self.period = period
        self.startsOn = startsOn
        self.active = active
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class FxRate {
    @Attribute(.unique) public var id: UUID
    public var date: Date
    public var currency: String
    public var rate: Decimal
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        date: Date,
        currency: String,
        rate: Decimal,
        createdAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.currency = currency
        self.rate = rate
        self.createdAt = createdAt
    }
}

@Model
public final class Transaction {
    @Attribute(.unique) public var id: UUID
    public var account: Account?
    public var externalId: String
    public var bookedAt: Date
    public var valueAt: Date?
    public var amount: Decimal
    public var currency: String
    public var amountEur: Decimal?
    public var fxRateUsed: Decimal?
    public var direction: TxDirection
    public var transactionDescription: String?
    public var counterparty: String?
    public var category: Category?
    public var categorySource: CategorySource
    public var isTransfer: Bool
    public var transferGroup: TransferGroup?
    public var routedFromTx: Transaction?
    public var route: TransferRoute?
    public var sharedExpenseGroup: SharedExpenseGroup?
    public var rawJSON: Data?
    public var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Transaction.routedFromTx)
    public var mirrors: [Transaction] = []

    @Relationship(deleteRule: .cascade, inverse: \SharedExpenseGroup.primaryTx)
    public var primaryForGroup: SharedExpenseGroup?

    public var desc: String? { transactionDescription }

    public init(
        id: UUID = UUID(),
        account: Account? = nil,
        externalId: String,
        bookedAt: Date,
        valueAt: Date? = nil,
        amount: Decimal,
        currency: String,
        amountEur: Decimal? = nil,
        fxRateUsed: Decimal? = nil,
        direction: TxDirection,
        description: String? = nil,
        counterparty: String? = nil,
        category: Category? = nil,
        categorySource: CategorySource = .bank,
        isTransfer: Bool = false,
        transferGroup: TransferGroup? = nil,
        routedFromTx: Transaction? = nil,
        route: TransferRoute? = nil,
        sharedExpenseGroup: SharedExpenseGroup? = nil,
        rawJSON: Data? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.account = account
        self.externalId = externalId
        self.bookedAt = bookedAt
        self.valueAt = valueAt
        self.amount = amount
        self.currency = currency
        self.amountEur = amountEur
        self.fxRateUsed = fxRateUsed
        self.direction = direction
        self.transactionDescription = description
        self.counterparty = counterparty
        self.category = category
        self.categorySource = categorySource
        self.isTransfer = isTransfer
        self.transferGroup = transferGroup
        self.routedFromTx = routedFromTx
        self.route = route
        self.sharedExpenseGroup = sharedExpenseGroup
        self.rawJSON = rawJSON
        self.createdAt = createdAt
    }
}

@Model
public final class SharedExpenseGroup {
    @Attribute(.unique) public var id: UUID
    public var label: String
    public var primaryTx: Transaction?
    public var attributionMonth: Date
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Transaction.sharedExpenseGroup)
    public var members: [Transaction] = []

    public init(
        id: UUID = UUID(),
        label: String,
        primaryTx: Transaction? = nil,
        attributionMonth: Date,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.label = label
        self.primaryTx = primaryTx
        self.attributionMonth = attributionMonth
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class PortfolioValuation {
    @Attribute(.unique) public var id: UUID
    public var account: Account?
    public var asOf: Date
    public var marketValueEur: Decimal
    public var cashValueEur: Decimal?
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        account: Account? = nil,
        asOf: Date,
        marketValueEur: Decimal,
        cashValueEur: Decimal? = nil,
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.account = account
        self.asOf = asOf
        self.marketValueEur = marketValueEur
        self.cashValueEur = cashValueEur
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class SyncRun {
    @Attribute(.unique) public var id: UUID
    public var connector: Connector
    public var connection: Connection?
    public var startedAt: Date
    public var finishedAt: Date?
    public var status: SyncRunStatus
    public var insertedTransactions: Int
    public var error: String?
    public var rawJSON: Data?

    public init(
        id: UUID = UUID(),
        connector: Connector,
        connection: Connection? = nil,
        startedAt: Date = .now,
        finishedAt: Date? = nil,
        status: SyncRunStatus = .running,
        insertedTransactions: Int = 0,
        error: String? = nil,
        rawJSON: Data? = nil
    ) {
        self.id = id
        self.connector = connector
        self.connection = connection
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.insertedTransactions = insertedTransactions
        self.error = error
        self.rawJSON = rawJSON
    }
}

public enum CoreModelSchema {
    public static let allTypes: [any PersistentModel.Type] = [
        Connection.self,
        AccountGroup.self,
        AccountSpace.self,
        Account.self,
        Category.self,
        CategoryRule.self,
        TransferRoute.self,
        TransferGroup.self,
        Budget.self,
        FxRate.self,
        Transaction.self,
        SharedExpenseGroup.self,
        PortfolioValuation.self,
        SyncRun.self,
    ]
}
