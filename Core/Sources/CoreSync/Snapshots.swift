import Foundation
import CoreModel

public protocol SyncSnapshot: Sendable, Equatable {
    var id: UUID { get }
    var clock: Date { get }
}

public struct ConnectionSnapshot: SyncSnapshot {
    public let id: UUID
    public let connector: Connector
    public let institutionId: String?
    public let institutionName: String?
    public let sessionId: String?
    public let accessTokenEnc: String?
    public let refreshTokenEnc: String?
    public let metadataJSON: Data?
    public let status: ConnectionStatus
    public let expiresAt: Date?
    public let lastSyncAt: Date?
    public let lastError: String?
    public let createdAt: Date
    public let updatedAt: Date
    public var clock: Date { updatedAt }

    public init(
        id: UUID, connector: Connector,
        institutionId: String? = nil, institutionName: String? = nil,
        sessionId: String? = nil,
        accessTokenEnc: String? = nil, refreshTokenEnc: String? = nil,
        metadataJSON: Data? = nil,
        status: ConnectionStatus,
        expiresAt: Date? = nil, lastSyncAt: Date? = nil, lastError: String? = nil,
        createdAt: Date, updatedAt: Date
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

public struct AccountGroupSnapshot: SyncSnapshot {
    public let id: UUID
    public let name: String
    public let color: String?
    public let kind: AccountGroupKind
    public let sortOrder: Int
    public let createdAt: Date
    public let updatedAt: Date
    public var clock: Date { updatedAt }

    public init(
        id: UUID, name: String, color: String?, kind: AccountGroupKind,
        sortOrder: Int, createdAt: Date, updatedAt: Date
    ) {
        self.id = id; self.name = name; self.color = color; self.kind = kind
        self.sortOrder = sortOrder; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct AccountSpaceSnapshot: SyncSnapshot {
    public let id: UUID
    public let name: String
    public let color: String?
    public let isDefault: Bool
    public let sortOrder: Int
    public let createdAt: Date
    public let updatedAt: Date
    public var clock: Date { updatedAt }

    public init(
        id: UUID, name: String, color: String?, isDefault: Bool,
        sortOrder: Int, createdAt: Date, updatedAt: Date
    ) {
        self.id = id; self.name = name; self.color = color; self.isDefault = isDefault
        self.sortOrder = sortOrder; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct AccountSnapshot: SyncSnapshot {
    public let id: UUID
    public let connectionId: UUID?
    public let groupId: UUID?
    public let spaceId: UUID?
    public let externalId: String
    public let type: AccountType
    public let institution: String
    public let name: String
    public let currency: String
    public let iban: String?
    public let balance: Decimal?
    public let balanceUpdatedAt: Date?
    public let metadataJSON: Data?
    public let archived: Bool
    public let excluded: Bool
    public let manualOpeningBalance: Decimal?
    public let balanceAnchor: Decimal?
    public let balanceAnchorAt: Date?
    public let createdAt: Date
    public let clock: Date

    public init(
        id: UUID,
        connectionId: UUID? = nil, groupId: UUID? = nil, spaceId: UUID? = nil,
        externalId: String, type: AccountType,
        institution: String, name: String, currency: String, iban: String? = nil,
        balance: Decimal? = nil, balanceUpdatedAt: Date? = nil,
        metadataJSON: Data? = nil,
        archived: Bool, excluded: Bool,
        manualOpeningBalance: Decimal? = nil,
        balanceAnchor: Decimal? = nil, balanceAnchorAt: Date? = nil,
        createdAt: Date,
        clock: Date
    ) {
        self.id = id
        self.connectionId = connectionId
        self.groupId = groupId
        self.spaceId = spaceId
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
        self.clock = clock
    }
}

public struct CategorySnapshot: SyncSnapshot {
    public let id: UUID
    public let name: String
    public let parentId: UUID?
    public let kind: String
    public let color: String?
    public let createdAt: Date
    public let clock: Date

    public init(
        id: UUID, name: String, parentId: UUID? = nil,
        kind: String, color: String? = nil, createdAt: Date, clock: Date
    ) {
        self.id = id; self.name = name; self.parentId = parentId
        self.kind = kind; self.color = color
        self.createdAt = createdAt; self.clock = clock
    }
}

public struct CategoryRuleSnapshot: SyncSnapshot {
    public let id: UUID
    public let pattern: String
    public let field: RuleField
    public let matchType: RuleMatch
    public let categoryId: UUID?
    public let priority: Int
    public let createdAt: Date
    public let clock: Date

    public init(
        id: UUID, pattern: String,
        field: RuleField, matchType: RuleMatch,
        categoryId: UUID?, priority: Int,
        createdAt: Date, clock: Date
    ) {
        self.id = id; self.pattern = pattern; self.field = field
        self.matchType = matchType; self.categoryId = categoryId
        self.priority = priority; self.createdAt = createdAt; self.clock = clock
    }
}

public struct TransferRouteSnapshot: SyncSnapshot {
    public let id: UUID
    public let pattern: String
    public let field: RuleField
    public let matchType: RuleMatch
    public let sourceAccountId: UUID?
    public let targetAccountId: UUID?
    public let direction: TxDirection?
    public let priority: Int
    public let enabled: Bool
    public let createdAt: Date
    public let updatedAt: Date
    public var clock: Date { updatedAt }

    public init(
        id: UUID, pattern: String,
        field: RuleField, matchType: RuleMatch,
        sourceAccountId: UUID? = nil, targetAccountId: UUID? = nil,
        direction: TxDirection? = nil,
        priority: Int, enabled: Bool,
        createdAt: Date, updatedAt: Date
    ) {
        self.id = id; self.pattern = pattern; self.field = field
        self.matchType = matchType
        self.sourceAccountId = sourceAccountId
        self.targetAccountId = targetAccountId
        self.direction = direction; self.priority = priority
        self.enabled = enabled
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct TransferGroupSnapshot: SyncSnapshot {
    public let id: UUID
    public let pairedAt: Date?
    public let routeId: UUID?
    public let createdAt: Date
    public let clock: Date

    public init(
        id: UUID, pairedAt: Date? = nil, routeId: UUID? = nil,
        createdAt: Date, clock: Date
    ) {
        self.id = id; self.pairedAt = pairedAt; self.routeId = routeId
        self.createdAt = createdAt; self.clock = clock
    }
}

public struct BudgetSnapshot: SyncSnapshot {
    public let id: UUID
    public let categoryId: UUID?
    public let amountEur: Decimal
    public let period: BudgetPeriod
    public let startsOn: Date
    public let active: Bool
    public let createdAt: Date
    public let updatedAt: Date
    public var clock: Date { updatedAt }

    public init(
        id: UUID, categoryId: UUID?, amountEur: Decimal,
        period: BudgetPeriod, startsOn: Date, active: Bool,
        createdAt: Date, updatedAt: Date
    ) {
        self.id = id; self.categoryId = categoryId; self.amountEur = amountEur
        self.period = period; self.startsOn = startsOn; self.active = active
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct FxRateSnapshot: SyncSnapshot {
    public let id: UUID
    public let date: Date
    public let currency: String
    public let rate: Decimal
    public let createdAt: Date
    public let clock: Date

    public init(
        id: UUID, date: Date, currency: String,
        rate: Decimal, createdAt: Date, clock: Date
    ) {
        self.id = id; self.date = date; self.currency = currency
        self.rate = rate; self.createdAt = createdAt; self.clock = clock
    }
}

public struct TransactionSnapshot: SyncSnapshot {
    public let id: UUID
    public let accountId: UUID?
    public let externalId: String
    public let bookedAt: Date
    public let valueAt: Date?
    public let amount: Decimal
    public let currency: String
    public let amountEur: Decimal?
    public let fxRateUsed: Decimal?
    public let direction: TxDirection
    public let transactionDescription: String?
    public let counterparty: String?
    public let categoryId: UUID?
    public let categorySource: CategorySource
    public let isTransfer: Bool
    public let transferGroupId: UUID?
    public let routedFromTxId: UUID?
    public let routeId: UUID?
    public let sharedExpenseGroupId: UUID?
    public let rawJSON: Data?
    public let createdAt: Date
    public let clock: Date

    public init(
        id: UUID, accountId: UUID?,
        externalId: String, bookedAt: Date, valueAt: Date? = nil,
        amount: Decimal, currency: String,
        amountEur: Decimal? = nil, fxRateUsed: Decimal? = nil,
        direction: TxDirection,
        transactionDescription: String? = nil, counterparty: String? = nil,
        categoryId: UUID? = nil, categorySource: CategorySource,
        isTransfer: Bool,
        transferGroupId: UUID? = nil, routedFromTxId: UUID? = nil,
        routeId: UUID? = nil, sharedExpenseGroupId: UUID? = nil,
        rawJSON: Data? = nil,
        createdAt: Date, clock: Date
    ) {
        self.id = id; self.accountId = accountId
        self.externalId = externalId; self.bookedAt = bookedAt; self.valueAt = valueAt
        self.amount = amount; self.currency = currency
        self.amountEur = amountEur; self.fxRateUsed = fxRateUsed
        self.direction = direction
        self.transactionDescription = transactionDescription
        self.counterparty = counterparty
        self.categoryId = categoryId; self.categorySource = categorySource
        self.isTransfer = isTransfer
        self.transferGroupId = transferGroupId
        self.routedFromTxId = routedFromTxId; self.routeId = routeId
        self.sharedExpenseGroupId = sharedExpenseGroupId
        self.rawJSON = rawJSON
        self.createdAt = createdAt; self.clock = clock
    }

    public func withCategory(
        id newCategoryId: UUID?,
        source newSource: CategorySource
    ) -> TransactionSnapshot {
        TransactionSnapshot(
            id: id, accountId: accountId,
            externalId: externalId, bookedAt: bookedAt, valueAt: valueAt,
            amount: amount, currency: currency,
            amountEur: amountEur, fxRateUsed: fxRateUsed,
            direction: direction,
            transactionDescription: transactionDescription,
            counterparty: counterparty,
            categoryId: newCategoryId, categorySource: newSource,
            isTransfer: isTransfer,
            transferGroupId: transferGroupId,
            routedFromTxId: routedFromTxId, routeId: routeId,
            sharedExpenseGroupId: sharedExpenseGroupId,
            rawJSON: rawJSON,
            createdAt: createdAt, clock: clock
        )
    }
}

public struct SharedExpenseGroupSnapshot: SyncSnapshot {
    public let id: UUID
    public let label: String
    public let primaryTxId: UUID?
    public let attributionMonth: Date
    public let createdAt: Date
    public let updatedAt: Date
    public var clock: Date { updatedAt }

    public init(
        id: UUID, label: String, primaryTxId: UUID?,
        attributionMonth: Date, createdAt: Date, updatedAt: Date
    ) {
        self.id = id; self.label = label; self.primaryTxId = primaryTxId
        self.attributionMonth = attributionMonth
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct PortfolioValuationSnapshot: SyncSnapshot {
    public let id: UUID
    public let accountId: UUID?
    public let asOf: Date
    public let marketValueEur: Decimal
    public let cashValueEur: Decimal?
    public let notes: String?
    public let createdAt: Date
    public let updatedAt: Date
    public var clock: Date { updatedAt }

    public init(
        id: UUID, accountId: UUID?, asOf: Date,
        marketValueEur: Decimal, cashValueEur: Decimal? = nil,
        notes: String? = nil,
        createdAt: Date, updatedAt: Date
    ) {
        self.id = id; self.accountId = accountId; self.asOf = asOf
        self.marketValueEur = marketValueEur; self.cashValueEur = cashValueEur
        self.notes = notes
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct SyncRunSnapshot: SyncSnapshot {
    public let id: UUID
    public let connector: Connector
    public let connectionId: UUID?
    public let startedAt: Date
    public let finishedAt: Date?
    public let status: SyncRunStatus
    public let insertedTransactions: Int
    public let error: String?
    public let rawJSON: Data?
    public var clock: Date { finishedAt ?? startedAt }

    public init(
        id: UUID, connector: Connector, connectionId: UUID?,
        startedAt: Date, finishedAt: Date? = nil,
        status: SyncRunStatus, insertedTransactions: Int,
        error: String? = nil, rawJSON: Data? = nil
    ) {
        self.id = id; self.connector = connector; self.connectionId = connectionId
        self.startedAt = startedAt; self.finishedAt = finishedAt
        self.status = status; self.insertedTransactions = insertedTransactions
        self.error = error; self.rawJSON = rawJSON
    }
}
