import Foundation
import SwiftData
import CoreModel

public enum ModelSnapshots {

    // MARK: - Connection

    @MainActor
    public static func find(connection id: UUID, in ctx: ModelContext) -> Connection? {
        (try? ctx.fetch(FetchDescriptor<Connection>(
            predicate: #Predicate { $0.id == id }
        )))?.first
    }

    @MainActor
    public static func snapshot(_ m: Connection) -> ConnectionSnapshot {
        ConnectionSnapshot(
            id: m.id, connector: m.connector,
            institutionId: m.institutionId, institutionName: m.institutionName,
            sessionId: m.sessionId,
            accessTokenEnc: m.accessTokenEnc, refreshTokenEnc: m.refreshTokenEnc,
            metadataJSON: m.metadataJSON,
            status: m.status,
            expiresAt: m.expiresAt, lastSyncAt: m.lastSyncAt, lastError: m.lastError,
            createdAt: m.createdAt, updatedAt: m.updatedAt
        )
    }

    @MainActor
    public static func apply(_ s: ConnectionSnapshot, to m: Connection) {
        m.connector = s.connector
        m.institutionId = s.institutionId
        m.institutionName = s.institutionName
        m.sessionId = s.sessionId
        m.accessTokenEnc = s.accessTokenEnc
        m.refreshTokenEnc = s.refreshTokenEnc
        m.metadataJSON = s.metadataJSON
        m.status = s.status
        m.expiresAt = s.expiresAt
        m.lastSyncAt = s.lastSyncAt
        m.lastError = s.lastError
        m.createdAt = s.createdAt
        m.updatedAt = s.updatedAt
    }

    @MainActor
    public static func insertOrUpdate(_ s: ConnectionSnapshot, in ctx: ModelContext) -> Connection {
        if let existing = find(connection: s.id, in: ctx) {
            apply(s, to: existing)
            return existing
        }
        let m = Connection(
            id: s.id, connector: s.connector,
            institutionId: s.institutionId, institutionName: s.institutionName,
            sessionId: s.sessionId,
            accessTokenEnc: s.accessTokenEnc, refreshTokenEnc: s.refreshTokenEnc,
            metadataJSON: s.metadataJSON,
            status: s.status,
            expiresAt: s.expiresAt, lastSyncAt: s.lastSyncAt, lastError: s.lastError,
            createdAt: s.createdAt, updatedAt: s.updatedAt
        )
        ctx.insert(m)
        return m
    }

    // MARK: - AccountGroup

    @MainActor
    public static func find(accountGroup id: UUID, in ctx: ModelContext) -> AccountGroup? {
        (try? ctx.fetch(FetchDescriptor<AccountGroup>(
            predicate: #Predicate { $0.id == id }
        )))?.first
    }

    @MainActor
    public static func snapshot(_ m: AccountGroup) -> AccountGroupSnapshot {
        AccountGroupSnapshot(
            id: m.id, name: m.name, color: m.color, kind: m.kind,
            sortOrder: m.sortOrder, createdAt: m.createdAt, updatedAt: m.updatedAt
        )
    }

    @MainActor
    public static func apply(_ s: AccountGroupSnapshot, to m: AccountGroup) {
        m.name = s.name; m.color = s.color; m.kind = s.kind
        m.sortOrder = s.sortOrder
        m.createdAt = s.createdAt; m.updatedAt = s.updatedAt
    }

    @MainActor
    public static func insertOrUpdate(_ s: AccountGroupSnapshot, in ctx: ModelContext) -> AccountGroup {
        if let existing = find(accountGroup: s.id, in: ctx) {
            apply(s, to: existing)
            return existing
        }
        let m = AccountGroup(
            id: s.id, name: s.name, color: s.color, kind: s.kind,
            sortOrder: s.sortOrder, createdAt: s.createdAt, updatedAt: s.updatedAt
        )
        ctx.insert(m)
        return m
    }

    // MARK: - AccountSpace

    @MainActor
    public static func find(accountSpace id: UUID, in ctx: ModelContext) -> AccountSpace? {
        (try? ctx.fetch(FetchDescriptor<AccountSpace>(
            predicate: #Predicate { $0.id == id }
        )))?.first
    }

    @MainActor
    public static func snapshot(_ m: AccountSpace) -> AccountSpaceSnapshot {
        AccountSpaceSnapshot(
            id: m.id, name: m.name, color: m.color, isDefault: m.isDefault,
            sortOrder: m.sortOrder, createdAt: m.createdAt, updatedAt: m.updatedAt
        )
    }

    @MainActor
    public static func apply(_ s: AccountSpaceSnapshot, to m: AccountSpace) {
        m.name = s.name; m.color = s.color; m.isDefault = s.isDefault
        m.sortOrder = s.sortOrder
        m.createdAt = s.createdAt; m.updatedAt = s.updatedAt
    }

    @MainActor
    public static func insertOrUpdate(_ s: AccountSpaceSnapshot, in ctx: ModelContext) -> AccountSpace {
        if let existing = find(accountSpace: s.id, in: ctx) {
            apply(s, to: existing)
            return existing
        }
        let m = AccountSpace(
            id: s.id, name: s.name, color: s.color, isDefault: s.isDefault,
            sortOrder: s.sortOrder, createdAt: s.createdAt, updatedAt: s.updatedAt
        )
        ctx.insert(m)
        return m
    }

    // MARK: - Account

    @MainActor
    public static func find(account id: UUID, in ctx: ModelContext) -> Account? {
        (try? ctx.fetch(FetchDescriptor<Account>(
            predicate: #Predicate { $0.id == id }
        )))?.first
    }

    @MainActor
    public static func snapshot(_ m: Account) -> AccountSnapshot {
        AccountSnapshot(
            id: m.id,
            connectionId: m.connection?.id,
            groupId: m.group?.id,
            spaceId: m.space?.id,
            externalId: m.externalId,
            type: m.type,
            institution: m.institution, name: m.name, currency: m.currency,
            iban: m.iban,
            balance: m.balance, balanceUpdatedAt: m.balanceUpdatedAt,
            metadataJSON: m.metadataJSON,
            archived: m.archived, excluded: m.excluded,
            manualOpeningBalance: m.manualOpeningBalance,
            balanceAnchor: m.balanceAnchor, balanceAnchorAt: m.balanceAnchorAt,
            createdAt: m.createdAt, clock: m.updatedAt
        )
    }

    @MainActor
    public static func apply(_ s: AccountSnapshot, to m: Account, in ctx: ModelContext) {
        m.connection = s.connectionId.flatMap { find(connection: $0, in: ctx) }
        m.group = s.groupId.flatMap { find(accountGroup: $0, in: ctx) }
        m.space = s.spaceId.flatMap { find(accountSpace: $0, in: ctx) }
        m.externalId = s.externalId
        m.type = s.type
        m.institution = s.institution
        m.name = s.name
        m.currency = s.currency
        m.iban = s.iban
        m.balance = s.balance
        m.balanceUpdatedAt = s.balanceUpdatedAt
        m.metadataJSON = s.metadataJSON
        m.archived = s.archived
        m.excluded = s.excluded
        m.manualOpeningBalance = s.manualOpeningBalance
        m.balanceAnchor = s.balanceAnchor
        m.balanceAnchorAt = s.balanceAnchorAt
        m.createdAt = s.createdAt
        m.updatedAt = s.clock
    }

    @MainActor
    public static func insertOrUpdate(_ s: AccountSnapshot, in ctx: ModelContext) -> Account {
        if let existing = find(account: s.id, in: ctx) {
            apply(s, to: existing, in: ctx)
            return existing
        }
        let m = Account(
            id: s.id,
            externalId: s.externalId, type: s.type,
            institution: s.institution, name: s.name, currency: s.currency,
            createdAt: s.createdAt
        )
        ctx.insert(m)
        apply(s, to: m, in: ctx)
        return m
    }

    // MARK: - Category

    @MainActor
    public static func find(category id: UUID, in ctx: ModelContext) -> CoreModel.Category? {
        (try? ctx.fetch(FetchDescriptor<CoreModel.Category>(
            predicate: #Predicate { $0.id == id }
        )))?.first
    }

    @MainActor
    public static func snapshot(_ m: CoreModel.Category) -> CategorySnapshot {
        CategorySnapshot(
            id: m.id, name: m.name, parentId: m.parent?.id,
            kind: m.kind, color: m.color,
            createdAt: m.createdAt, clock: m.updatedAt
        )
    }

    @MainActor
    public static func apply(_ s: CategorySnapshot, to m: CoreModel.Category, in ctx: ModelContext) {
        m.name = s.name
        m.parent = s.parentId.flatMap { find(category: $0, in: ctx) }
        m.kind = s.kind
        m.color = s.color
        m.createdAt = s.createdAt
        m.updatedAt = s.clock
    }

    @MainActor
    public static func insertOrUpdate(_ s: CategorySnapshot, in ctx: ModelContext) -> CoreModel.Category {
        if let existing = find(category: s.id, in: ctx) {
            apply(s, to: existing, in: ctx)
            return existing
        }
        let m = CoreModel.Category(
            id: s.id, name: s.name, parent: nil,
            kind: s.kind, color: s.color, createdAt: s.createdAt
        )
        ctx.insert(m)
        apply(s, to: m, in: ctx)
        return m
    }

    // MARK: - CategoryRule

    @MainActor
    public static func find(categoryRule id: UUID, in ctx: ModelContext) -> CategoryRule? {
        (try? ctx.fetch(FetchDescriptor<CategoryRule>(
            predicate: #Predicate { $0.id == id }
        )))?.first
    }

    @MainActor
    public static func snapshot(_ m: CategoryRule) -> CategoryRuleSnapshot {
        CategoryRuleSnapshot(
            id: m.id, pattern: m.pattern, field: m.field, matchType: m.matchType,
            categoryId: m.category?.id, priority: m.priority,
            createdAt: m.createdAt, clock: m.updatedAt
        )
    }

    @MainActor
    public static func apply(_ s: CategoryRuleSnapshot, to m: CategoryRule, in ctx: ModelContext) {
        m.pattern = s.pattern
        m.field = s.field
        m.matchType = s.matchType
        m.category = s.categoryId.flatMap { find(category: $0, in: ctx) }
        m.priority = s.priority
        m.createdAt = s.createdAt
        m.updatedAt = s.clock
    }

    @MainActor
    public static func insertOrUpdate(_ s: CategoryRuleSnapshot, in ctx: ModelContext) -> CategoryRule {
        if let existing = find(categoryRule: s.id, in: ctx) {
            apply(s, to: existing, in: ctx)
            return existing
        }
        let m = CategoryRule(
            id: s.id, pattern: s.pattern, field: s.field, matchType: s.matchType,
            category: nil, priority: s.priority, createdAt: s.createdAt
        )
        ctx.insert(m)
        apply(s, to: m, in: ctx)
        return m
    }

    // MARK: - TransferRoute

    @MainActor
    public static func find(transferRoute id: UUID, in ctx: ModelContext) -> TransferRoute? {
        (try? ctx.fetch(FetchDescriptor<TransferRoute>(
            predicate: #Predicate { $0.id == id }
        )))?.first
    }

    @MainActor
    public static func snapshot(_ m: TransferRoute) -> TransferRouteSnapshot {
        TransferRouteSnapshot(
            id: m.id, pattern: m.pattern, field: m.field, matchType: m.matchType,
            sourceAccountId: m.sourceAccount?.id,
            targetAccountId: m.targetAccount?.id,
            direction: m.direction, priority: m.priority, enabled: m.enabled,
            createdAt: m.createdAt, updatedAt: m.updatedAt
        )
    }

    @MainActor
    public static func apply(_ s: TransferRouteSnapshot, to m: TransferRoute, in ctx: ModelContext) {
        m.pattern = s.pattern; m.field = s.field; m.matchType = s.matchType
        m.sourceAccount = s.sourceAccountId.flatMap { find(account: $0, in: ctx) }
        m.targetAccount = s.targetAccountId.flatMap { find(account: $0, in: ctx) }
        m.direction = s.direction; m.priority = s.priority; m.enabled = s.enabled
        m.createdAt = s.createdAt; m.updatedAt = s.updatedAt
    }

    @MainActor
    public static func insertOrUpdate(_ s: TransferRouteSnapshot, in ctx: ModelContext) -> TransferRoute {
        if let existing = find(transferRoute: s.id, in: ctx) {
            apply(s, to: existing, in: ctx)
            return existing
        }
        let m = TransferRoute(
            id: s.id, pattern: s.pattern,
            field: s.field, matchType: s.matchType,
            priority: s.priority, enabled: s.enabled,
            createdAt: s.createdAt, updatedAt: s.updatedAt
        )
        ctx.insert(m)
        apply(s, to: m, in: ctx)
        return m
    }

    // MARK: - TransferGroup

    @MainActor
    public static func find(transferGroup id: UUID, in ctx: ModelContext) -> TransferGroup? {
        (try? ctx.fetch(FetchDescriptor<TransferGroup>(
            predicate: #Predicate { $0.id == id }
        )))?.first
    }

    @MainActor
    public static func snapshot(_ m: TransferGroup) -> TransferGroupSnapshot {
        TransferGroupSnapshot(
            id: m.id, pairedAt: m.pairedAt, routeId: m.route?.id,
            createdAt: m.createdAt, clock: m.updatedAt
        )
    }

    @MainActor
    public static func apply(_ s: TransferGroupSnapshot, to m: TransferGroup, in ctx: ModelContext) {
        m.pairedAt = s.pairedAt
        m.route = s.routeId.flatMap { find(transferRoute: $0, in: ctx) }
        m.createdAt = s.createdAt
        m.updatedAt = s.clock
    }

    @MainActor
    public static func insertOrUpdate(_ s: TransferGroupSnapshot, in ctx: ModelContext) -> TransferGroup {
        if let existing = find(transferGroup: s.id, in: ctx) {
            apply(s, to: existing, in: ctx)
            return existing
        }
        let m = TransferGroup(
            id: s.id, pairedAt: s.pairedAt, route: nil, createdAt: s.createdAt
        )
        ctx.insert(m)
        apply(s, to: m, in: ctx)
        return m
    }

    // MARK: - Budget

    @MainActor
    public static func find(budget id: UUID, in ctx: ModelContext) -> Budget? {
        (try? ctx.fetch(FetchDescriptor<Budget>(
            predicate: #Predicate { $0.id == id }
        )))?.first
    }

    @MainActor
    public static func snapshot(_ m: Budget) -> BudgetSnapshot {
        BudgetSnapshot(
            id: m.id, categoryId: m.category?.id,
            amountEur: m.amountEur, period: m.period, startsOn: m.startsOn,
            active: m.active,
            createdAt: m.createdAt, updatedAt: m.updatedAt
        )
    }

    @MainActor
    public static func apply(_ s: BudgetSnapshot, to m: Budget, in ctx: ModelContext) {
        m.category = s.categoryId.flatMap { find(category: $0, in: ctx) }
        m.amountEur = s.amountEur
        m.period = s.period
        m.startsOn = s.startsOn
        m.active = s.active
        m.createdAt = s.createdAt
        m.updatedAt = s.updatedAt
    }

    @MainActor
    public static func insertOrUpdate(_ s: BudgetSnapshot, in ctx: ModelContext) -> Budget {
        if let existing = find(budget: s.id, in: ctx) {
            apply(s, to: existing, in: ctx)
            return existing
        }
        let m = Budget(
            id: s.id, category: nil, amountEur: s.amountEur,
            period: s.period, startsOn: s.startsOn, active: s.active,
            createdAt: s.createdAt, updatedAt: s.updatedAt
        )
        ctx.insert(m)
        apply(s, to: m, in: ctx)
        return m
    }

    // MARK: - FxRate

    @MainActor
    public static func find(fxRate id: UUID, in ctx: ModelContext) -> FxRate? {
        (try? ctx.fetch(FetchDescriptor<FxRate>(
            predicate: #Predicate { $0.id == id }
        )))?.first
    }

    @MainActor
    public static func findFxRate(date: Date, currency: String, in ctx: ModelContext) -> FxRate? {
        (try? ctx.fetch(FetchDescriptor<FxRate>(
            predicate: #Predicate { $0.date == date && $0.currency == currency }
        )))?.first
    }

    @MainActor
    public static func snapshot(_ m: FxRate) -> FxRateSnapshot {
        FxRateSnapshot(
            id: m.id, date: m.date, currency: m.currency, rate: m.rate,
            createdAt: m.createdAt, clock: m.createdAt
        )
    }

    @MainActor
    public static func apply(_ s: FxRateSnapshot, to m: FxRate) {
        m.date = s.date
        m.currency = s.currency
        m.rate = s.rate
        m.createdAt = s.createdAt
    }

    @MainActor
    public static func insertOrUpdate(_ s: FxRateSnapshot, in ctx: ModelContext) -> FxRate {
        if let existing = find(fxRate: s.id, in: ctx) {
            apply(s, to: existing)
            return existing
        }
        let m = FxRate(
            id: s.id, date: s.date, currency: s.currency,
            rate: s.rate, createdAt: s.createdAt
        )
        ctx.insert(m)
        return m
    }

    // MARK: - Transaction

    @MainActor
    public static func find(transaction id: UUID, in ctx: ModelContext) -> Transaction? {
        (try? ctx.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.id == id }
        )))?.first
    }

    @MainActor
    public static func findTransaction(
        accountId: UUID, externalId: String, in ctx: ModelContext
    ) -> Transaction? {
        (try? ctx.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate {
                $0.account?.id == accountId && $0.externalId == externalId
            }
        )))?.first
    }

    @MainActor
    public static func snapshot(_ m: Transaction) -> TransactionSnapshot {
        TransactionSnapshot(
            id: m.id, accountId: m.account?.id,
            externalId: m.externalId, bookedAt: m.bookedAt, valueAt: m.valueAt,
            amount: m.amount, currency: m.currency,
            amountEur: m.amountEur, fxRateUsed: m.fxRateUsed,
            direction: m.direction,
            transactionDescription: m.transactionDescription,
            counterparty: m.counterparty,
            categoryId: m.category?.id, categorySource: m.categorySource,
            isTransfer: m.isTransfer,
            transferGroupId: m.transferGroup?.id,
            routedFromTxId: m.routedFromTx?.id,
            routeId: m.route?.id,
            sharedExpenseGroupId: m.sharedExpenseGroup?.id,
            rawJSON: m.rawJSON,
            createdAt: m.createdAt, clock: m.updatedAt
        )
    }

    @MainActor
    public static func apply(_ s: TransactionSnapshot, to m: Transaction, in ctx: ModelContext) {
        m.account = s.accountId.flatMap { find(account: $0, in: ctx) }
        m.externalId = s.externalId
        m.bookedAt = s.bookedAt
        m.valueAt = s.valueAt
        m.amount = s.amount
        m.currency = s.currency
        m.amountEur = s.amountEur
        m.fxRateUsed = s.fxRateUsed
        m.direction = s.direction
        m.transactionDescription = s.transactionDescription
        m.counterparty = s.counterparty
        m.category = s.categoryId.flatMap { find(category: $0, in: ctx) }
        m.categorySource = s.categorySource
        m.isTransfer = s.isTransfer
        m.transferGroup = s.transferGroupId.flatMap { find(transferGroup: $0, in: ctx) }
        m.routedFromTx = s.routedFromTxId.flatMap { find(transaction: $0, in: ctx) }
        m.route = s.routeId.flatMap { find(transferRoute: $0, in: ctx) }
        m.sharedExpenseGroup = s.sharedExpenseGroupId.flatMap { find(sharedExpenseGroup: $0, in: ctx) }
        m.rawJSON = s.rawJSON
        m.createdAt = s.createdAt
        m.updatedAt = s.clock
    }

    @MainActor
    public static func insertOrUpdate(_ s: TransactionSnapshot, in ctx: ModelContext) -> Transaction {
        if let existing = find(transaction: s.id, in: ctx) {
            apply(s, to: existing, in: ctx)
            return existing
        }
        let m = Transaction(
            id: s.id,
            externalId: s.externalId, bookedAt: s.bookedAt,
            amount: s.amount, currency: s.currency,
            direction: s.direction,
            categorySource: s.categorySource,
            isTransfer: s.isTransfer,
            createdAt: s.createdAt
        )
        ctx.insert(m)
        apply(s, to: m, in: ctx)
        return m
    }

    // MARK: - SharedExpenseGroup

    @MainActor
    public static func find(sharedExpenseGroup id: UUID, in ctx: ModelContext) -> SharedExpenseGroup? {
        (try? ctx.fetch(FetchDescriptor<SharedExpenseGroup>(
            predicate: #Predicate { $0.id == id }
        )))?.first
    }

    @MainActor
    public static func snapshot(_ m: SharedExpenseGroup) -> SharedExpenseGroupSnapshot {
        SharedExpenseGroupSnapshot(
            id: m.id, label: m.label, primaryTxId: m.primaryTx?.id,
            attributionMonth: m.attributionMonth,
            createdAt: m.createdAt, updatedAt: m.updatedAt
        )
    }

    @MainActor
    public static func apply(_ s: SharedExpenseGroupSnapshot, to m: SharedExpenseGroup, in ctx: ModelContext) {
        m.label = s.label
        m.primaryTx = s.primaryTxId.flatMap { find(transaction: $0, in: ctx) }
        m.attributionMonth = s.attributionMonth
        m.createdAt = s.createdAt
        m.updatedAt = s.updatedAt
    }

    @MainActor
    public static func insertOrUpdate(_ s: SharedExpenseGroupSnapshot, in ctx: ModelContext) -> SharedExpenseGroup {
        if let existing = find(sharedExpenseGroup: s.id, in: ctx) {
            apply(s, to: existing, in: ctx)
            return existing
        }
        let m = SharedExpenseGroup(
            id: s.id, label: s.label, primaryTx: nil,
            attributionMonth: s.attributionMonth,
            createdAt: s.createdAt, updatedAt: s.updatedAt
        )
        ctx.insert(m)
        apply(s, to: m, in: ctx)
        return m
    }

    // MARK: - PortfolioValuation

    @MainActor
    public static func find(portfolioValuation id: UUID, in ctx: ModelContext) -> PortfolioValuation? {
        (try? ctx.fetch(FetchDescriptor<PortfolioValuation>(
            predicate: #Predicate { $0.id == id }
        )))?.first
    }

    @MainActor
    public static func snapshot(_ m: PortfolioValuation) -> PortfolioValuationSnapshot {
        PortfolioValuationSnapshot(
            id: m.id, accountId: m.account?.id, asOf: m.asOf,
            marketValueEur: m.marketValueEur, cashValueEur: m.cashValueEur,
            notes: m.notes,
            createdAt: m.createdAt, updatedAt: m.updatedAt
        )
    }

    @MainActor
    public static func apply(_ s: PortfolioValuationSnapshot, to m: PortfolioValuation, in ctx: ModelContext) {
        m.account = s.accountId.flatMap { find(account: $0, in: ctx) }
        m.asOf = s.asOf
        m.marketValueEur = s.marketValueEur
        m.cashValueEur = s.cashValueEur
        m.notes = s.notes
        m.createdAt = s.createdAt
        m.updatedAt = s.updatedAt
    }

    @MainActor
    public static func insertOrUpdate(_ s: PortfolioValuationSnapshot, in ctx: ModelContext) -> PortfolioValuation {
        if let existing = find(portfolioValuation: s.id, in: ctx) {
            apply(s, to: existing, in: ctx)
            return existing
        }
        let m = PortfolioValuation(
            id: s.id, account: nil, asOf: s.asOf,
            marketValueEur: s.marketValueEur, cashValueEur: s.cashValueEur,
            notes: s.notes,
            createdAt: s.createdAt, updatedAt: s.updatedAt
        )
        ctx.insert(m)
        apply(s, to: m, in: ctx)
        return m
    }

    // MARK: - SyncRun

    @MainActor
    public static func find(syncRun id: UUID, in ctx: ModelContext) -> SyncRun? {
        (try? ctx.fetch(FetchDescriptor<SyncRun>(
            predicate: #Predicate { $0.id == id }
        )))?.first
    }

    @MainActor
    public static func snapshot(_ m: SyncRun) -> SyncRunSnapshot {
        SyncRunSnapshot(
            id: m.id, connector: m.connector,
            connectionId: m.connection?.id,
            startedAt: m.startedAt, finishedAt: m.finishedAt,
            status: m.status, insertedTransactions: m.insertedTransactions,
            error: m.error, rawJSON: m.rawJSON
        )
    }

    @MainActor
    public static func apply(_ s: SyncRunSnapshot, to m: SyncRun, in ctx: ModelContext) {
        m.connector = s.connector
        m.connection = s.connectionId.flatMap { find(connection: $0, in: ctx) }
        m.startedAt = s.startedAt
        m.finishedAt = s.finishedAt
        m.status = s.status
        m.insertedTransactions = s.insertedTransactions
        m.error = s.error
        m.rawJSON = s.rawJSON
    }

    @MainActor
    public static func insertOrUpdate(_ s: SyncRunSnapshot, in ctx: ModelContext) -> SyncRun {
        if let existing = find(syncRun: s.id, in: ctx) {
            apply(s, to: existing, in: ctx)
            return existing
        }
        let m = SyncRun(
            id: s.id, connector: s.connector, connection: nil,
            startedAt: s.startedAt, finishedAt: s.finishedAt,
            status: s.status, insertedTransactions: s.insertedTransactions,
            error: s.error, rawJSON: s.rawJSON
        )
        ctx.insert(m)
        apply(s, to: m, in: ctx)
        return m
    }
}
