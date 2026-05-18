import Foundation
import SwiftData
import CoreModel

public struct ImportSummary: Sendable, Equatable {
    public var connections: Int = 0
    public var accountGroups: Int = 0
    public var accountSpaces: Int = 0
    public var accounts: Int = 0
    public var categories: Int = 0
    public var categoryRules: Int = 0
    public var transferRoutes: Int = 0
    public var budgets: Int = 0
    public var fxRates: Int = 0
    public var transferGroups: Int = 0
    public var transactions: Int = 0
    public var sharedExpenseGroups: Int = 0
    public var portfolioValuations: Int = 0
    public var syncRuns: Int = 0

    public var categorySourceBackfilled: Int = 0
    public var attributionMonthBackfilled: Int = 0

    public init() {}
}

public enum PostgresImporter {
    @MainActor
    public static func importDump(
        _ doc: DumpDocument,
        into ctx: ModelContext
    ) throws -> ImportSummary {
        guard doc.schemaVersion == DumpParse.supportedSchemaVersion else {
            throw ImportError.schemaVersionUnsupported(
                found: doc.schemaVersion,
                supported: DumpParse.supportedSchemaVersion
            )
        }

        var maps = IDMaps()
        var summary = ImportSummary()

        try importConnections(doc.connections, maps: &maps, summary: &summary, ctx: ctx)
        try importAccountGroups(doc.accountGroups, maps: &maps, summary: &summary, ctx: ctx)
        try importAccountSpaces(doc.accountSpaces, maps: &maps, summary: &summary, ctx: ctx)
        try importAccounts(doc.accounts, maps: &maps, summary: &summary, ctx: ctx)
        try importCategories(doc.categories, maps: &maps, summary: &summary, ctx: ctx)
        try importCategoryRules(doc.categoryRules, maps: &maps, summary: &summary, ctx: ctx)
        try importTransferRoutes(doc.transferRoutes, maps: &maps, summary: &summary, ctx: ctx)
        try importBudgets(doc.budgets, maps: &maps, summary: &summary, ctx: ctx)
        try importFxRates(doc.fxRates, maps: &maps, summary: &summary, ctx: ctx)
        try importTransferGroups(doc.transferGroups, maps: &maps, summary: &summary, ctx: ctx)
        try importTransactionsFirstPass(doc.transactions, maps: &maps, summary: &summary, ctx: ctx)
        try importSharedExpenseGroups(doc.sharedExpenseGroups, maps: &maps, summary: &summary, ctx: ctx)
        try linkTransactionsSecondPass(doc.transactions, maps: maps)
        try importPortfolioValuations(doc.portfolioValuations, maps: &maps, summary: &summary, ctx: ctx)
        try importSyncRuns(doc.syncRuns, maps: &maps, summary: &summary, ctx: ctx)

        try ctx.save()
        return summary
    }

    private struct IDMaps {
        var connections: [UUID: Connection] = [:]
        var accountGroups: [UUID: AccountGroup] = [:]
        var accountSpaces: [UUID: AccountSpace] = [:]
        var accounts: [UUID: Account] = [:]
        var categories: [UUID: CoreModel.Category] = [:]
        var transferRoutes: [UUID: TransferRoute] = [:]
        var transferGroups: [UUID: TransferGroup] = [:]
        var transactions: [UUID: Transaction] = [:]
        var sharedExpenseGroups: [UUID: SharedExpenseGroup] = [:]
    }

    // MARK: - Phase 1

    @MainActor
    private static func importConnections(
        _ rows: [DumpConnection],
        maps: inout IDMaps,
        summary: inout ImportSummary,
        ctx: ModelContext
    ) throws {
        for r in rows {
            let id = try DumpParse.uuid(r.id, table: "connections", id: r.id, field: "id")
            if maps.connections[id] != nil {
                throw ImportError.duplicateDumpId(table: "connections", id: r.id)
            }
            if let existing = try fetchByID(Connection.self, id: id, ctx: ctx) {
                maps.connections[id] = existing
                continue
            }
            let connector = try DumpParse.enumValue(
                r.connector, as: Connector.self,
                table: "connections", id: r.id, field: "connector",
                valid: Connector.allCases.map(\.rawValue)
            )
            let status = try DumpParse.enumValue(
                r.status, as: ConnectionStatus.self,
                table: "connections", id: r.id, field: "status",
                valid: ConnectionStatus.allCases.map(\.rawValue)
            )
            let m = Connection(
                id: id,
                connector: connector,
                institutionId: r.institutionId,
                institutionName: r.institutionName,
                sessionId: r.sessionId,
                accessTokenEnc: r.accessTokenEnc,
                refreshTokenEnc: r.refreshTokenEnc,
                metadataJSON: try r.metadata?.encoded(),
                status: status,
                expiresAt: try DumpParse.timestamp(r.expiresAt, table: "connections", id: r.id, field: "expiresAt"),
                lastSyncAt: try DumpParse.timestamp(r.lastSyncAt, table: "connections", id: r.id, field: "lastSyncAt"),
                lastError: r.lastError,
                createdAt: try DumpParse.timestamp(r.createdAt, table: "connections", id: r.id, field: "createdAt"),
                updatedAt: try DumpParse.timestamp(r.updatedAt, table: "connections", id: r.id, field: "updatedAt")
            )
            ctx.insert(m)
            maps.connections[id] = m
            summary.connections += 1
        }
    }

    @MainActor
    private static func importAccountGroups(
        _ rows: [DumpAccountGroup],
        maps: inout IDMaps,
        summary: inout ImportSummary,
        ctx: ModelContext
    ) throws {
        for r in rows {
            let id = try DumpParse.uuid(r.id, table: "account_groups", id: r.id, field: "id")
            if maps.accountGroups[id] != nil {
                throw ImportError.duplicateDumpId(table: "account_groups", id: r.id)
            }
            if let existing = try fetchByID(AccountGroup.self, id: id, ctx: ctx) {
                maps.accountGroups[id] = existing
                continue
            }
            let kind = try DumpParse.enumValue(
                r.kind, as: AccountGroupKind.self,
                table: "account_groups", id: r.id, field: "kind",
                valid: AccountGroupKind.allCases.map(\.rawValue)
            )
            let m = AccountGroup(
                id: id,
                name: r.name,
                color: r.color,
                kind: kind,
                sortOrder: r.sortOrder,
                createdAt: try DumpParse.timestamp(r.createdAt, table: "account_groups", id: r.id, field: "createdAt"),
                updatedAt: try DumpParse.timestamp(r.updatedAt, table: "account_groups", id: r.id, field: "updatedAt")
            )
            ctx.insert(m)
            maps.accountGroups[id] = m
            summary.accountGroups += 1
        }
    }

    @MainActor
    private static func importAccountSpaces(
        _ rows: [DumpAccountSpace],
        maps: inout IDMaps,
        summary: inout ImportSummary,
        ctx: ModelContext
    ) throws {
        for r in rows {
            let id = try DumpParse.uuid(r.id, table: "account_spaces", id: r.id, field: "id")
            if maps.accountSpaces[id] != nil {
                throw ImportError.duplicateDumpId(table: "account_spaces", id: r.id)
            }
            if let existing = try fetchByID(AccountSpace.self, id: id, ctx: ctx) {
                maps.accountSpaces[id] = existing
                continue
            }
            let m = AccountSpace(
                id: id,
                name: r.name,
                color: r.color,
                isDefault: r.isDefault,
                sortOrder: r.sortOrder,
                createdAt: try DumpParse.timestamp(r.createdAt, table: "account_spaces", id: r.id, field: "createdAt"),
                updatedAt: try DumpParse.timestamp(r.updatedAt, table: "account_spaces", id: r.id, field: "updatedAt")
            )
            ctx.insert(m)
            maps.accountSpaces[id] = m
            summary.accountSpaces += 1
        }
    }

    @MainActor
    private static func importAccounts(
        _ rows: [DumpAccount],
        maps: inout IDMaps,
        summary: inout ImportSummary,
        ctx: ModelContext
    ) throws {
        for r in rows {
            let id = try DumpParse.uuid(r.id, table: "accounts", id: r.id, field: "id")
            if maps.accounts[id] != nil {
                throw ImportError.duplicateDumpId(table: "accounts", id: r.id)
            }
            if let existing = try fetchByID(Account.self, id: id, ctx: ctx) {
                maps.accounts[id] = existing
                continue
            }
            let type = try DumpParse.enumValue(
                r.type, as: AccountType.self,
                table: "accounts", id: r.id, field: "type",
                valid: AccountType.allCases.map(\.rawValue)
            )
            let connection: Connection? = try resolveOptional(
                r.connectionId, in: maps.connections,
                table: "accounts", id: r.id, field: "connectionId"
            )
            let group: AccountGroup? = try resolveOptional(
                r.groupId, in: maps.accountGroups,
                table: "accounts", id: r.id, field: "groupId"
            )
            let space: AccountSpace? = try resolveOptional(
                r.spaceId, in: maps.accountSpaces,
                table: "accounts", id: r.id, field: "spaceId"
            )
            let m = Account(
                id: id,
                connection: connection,
                group: group,
                space: space,
                externalId: r.externalId,
                type: type,
                institution: r.institution,
                name: r.name,
                currency: r.currency,
                iban: r.iban,
                balance: try DumpParse.decimal(r.balance, table: "accounts", id: r.id, field: "balance"),
                balanceUpdatedAt: try DumpParse.timestamp(r.balanceUpdatedAt, table: "accounts", id: r.id, field: "balanceUpdatedAt"),
                metadataJSON: try r.metadata?.encoded(),
                archived: r.archived,
                excluded: r.excluded,
                manualOpeningBalance: try DumpParse.decimal(r.manualOpeningBalance, table: "accounts", id: r.id, field: "manualOpeningBalance"),
                balanceAnchor: try DumpParse.decimal(r.balanceAnchor, table: "accounts", id: r.id, field: "balanceAnchor"),
                balanceAnchorAt: try DumpParse.timestamp(r.balanceAnchorAt, table: "accounts", id: r.id, field: "balanceAnchorAt"),
                createdAt: try DumpParse.timestamp(r.createdAt, table: "accounts", id: r.id, field: "createdAt")
            )
            ctx.insert(m)
            maps.accounts[id] = m
            summary.accounts += 1
        }
    }

    @MainActor
    private static func importCategories(
        _ rows: [DumpCategory],
        maps: inout IDMaps,
        summary: inout ImportSummary,
        ctx: ModelContext
    ) throws {
        for r in rows {
            let id = try DumpParse.uuid(r.id, table: "categories", id: r.id, field: "id")
            if maps.categories[id] != nil {
                throw ImportError.duplicateDumpId(table: "categories", id: r.id)
            }
            if let existing = try fetchByID(CoreModel.Category.self, id: id, ctx: ctx) {
                maps.categories[id] = existing
                continue
            }
            let m = CoreModel.Category(
                id: id,
                name: r.name,
                parent: nil,
                kind: r.kind,
                color: r.color,
                createdAt: try DumpParse.timestamp(r.createdAt, table: "categories", id: r.id, field: "createdAt")
            )
            ctx.insert(m)
            maps.categories[id] = m
            summary.categories += 1
        }
        for r in rows {
            guard let parentId = r.parentId else { continue }
            let cid = try DumpParse.uuid(r.id, table: "categories", id: r.id, field: "id")
            let pid = try DumpParse.uuid(parentId, table: "categories", id: r.id, field: "parentId")
            guard let cat = maps.categories[cid] else {
                throw ImportError.orphanReference(
                    table: "categories", id: r.id, field: "self", referencedId: r.id
                )
            }
            guard let parent = maps.categories[pid] else {
                throw ImportError.orphanReference(
                    table: "categories", id: r.id, field: "parentId", referencedId: parentId
                )
            }
            cat.parent = parent
        }
    }

    @MainActor
    private static func importCategoryRules(
        _ rows: [DumpCategoryRule],
        maps: inout IDMaps,
        summary: inout ImportSummary,
        ctx: ModelContext
    ) throws {
        for r in rows {
            let id = try DumpParse.uuid(r.id, table: "category_rules", id: r.id, field: "id")
            if let existing = try fetchByID(CategoryRule.self, id: id, ctx: ctx) {
                _ = existing
                continue
            }
            let field = try DumpParse.enumValue(
                r.field, as: RuleField.self,
                table: "category_rules", id: r.id, field: "field",
                valid: RuleField.allCases.map(\.rawValue)
            )
            let matchType = try DumpParse.enumValue(
                r.matchType, as: RuleMatch.self,
                table: "category_rules", id: r.id, field: "matchType",
                valid: RuleMatch.allCases.map(\.rawValue)
            )
            let category: CoreModel.Category = try resolveRequired(
                r.categoryId, in: maps.categories,
                table: "category_rules", id: r.id, field: "categoryId"
            )
            let m = CategoryRule(
                id: id,
                pattern: r.pattern,
                field: field,
                matchType: matchType,
                category: category,
                priority: r.priority,
                createdAt: try DumpParse.timestamp(r.createdAt, table: "category_rules", id: r.id, field: "createdAt")
            )
            ctx.insert(m)
            summary.categoryRules += 1
        }
    }

    @MainActor
    private static func importTransferRoutes(
        _ rows: [DumpTransferRoute],
        maps: inout IDMaps,
        summary: inout ImportSummary,
        ctx: ModelContext
    ) throws {
        for r in rows {
            let id = try DumpParse.uuid(r.id, table: "transfer_routes", id: r.id, field: "id")
            if maps.transferRoutes[id] != nil {
                throw ImportError.duplicateDumpId(table: "transfer_routes", id: r.id)
            }
            if let existing = try fetchByID(TransferRoute.self, id: id, ctx: ctx) {
                maps.transferRoutes[id] = existing
                continue
            }
            let field = try DumpParse.enumValue(
                r.field, as: RuleField.self,
                table: "transfer_routes", id: r.id, field: "field",
                valid: RuleField.allCases.map(\.rawValue)
            )
            let matchType = try DumpParse.enumValue(
                r.matchType, as: RuleMatch.self,
                table: "transfer_routes", id: r.id, field: "matchType",
                valid: RuleMatch.allCases.map(\.rawValue)
            )
            let direction: TxDirection? = try r.direction.map { v in
                try DumpParse.enumValue(
                    v, as: TxDirection.self,
                    table: "transfer_routes", id: r.id, field: "direction",
                    valid: TxDirection.allCases.map(\.rawValue)
                )
            }
            let source: Account? = try resolveOptional(
                r.sourceAccountId, in: maps.accounts,
                table: "transfer_routes", id: r.id, field: "sourceAccountId"
            )
            let target: Account = try resolveRequired(
                r.targetAccountId, in: maps.accounts,
                table: "transfer_routes", id: r.id, field: "targetAccountId"
            )
            let m = TransferRoute(
                id: id,
                pattern: r.pattern,
                field: field,
                matchType: matchType,
                sourceAccount: source,
                targetAccount: target,
                direction: direction,
                priority: r.priority,
                enabled: r.enabled,
                createdAt: try DumpParse.timestamp(r.createdAt, table: "transfer_routes", id: r.id, field: "createdAt"),
                updatedAt: try DumpParse.timestamp(r.updatedAt, table: "transfer_routes", id: r.id, field: "updatedAt")
            )
            ctx.insert(m)
            maps.transferRoutes[id] = m
            summary.transferRoutes += 1
        }
    }

    @MainActor
    private static func importBudgets(
        _ rows: [DumpBudget],
        maps: inout IDMaps,
        summary: inout ImportSummary,
        ctx: ModelContext
    ) throws {
        for r in rows {
            let id = try DumpParse.uuid(r.id, table: "budgets", id: r.id, field: "id")
            if let existing = try fetchByID(Budget.self, id: id, ctx: ctx) {
                _ = existing
                continue
            }
            let period = try DumpParse.enumValue(
                r.period, as: BudgetPeriod.self,
                table: "budgets", id: r.id, field: "period",
                valid: BudgetPeriod.allCases.map(\.rawValue)
            )
            let category: CoreModel.Category = try resolveRequired(
                r.categoryId, in: maps.categories,
                table: "budgets", id: r.id, field: "categoryId"
            )
            let m = Budget(
                id: id,
                category: category,
                amountEur: try DumpParse.decimal(r.amountEur, table: "budgets", id: r.id, field: "amountEur"),
                period: period,
                startsOn: try DumpParse.date(r.startsOn, table: "budgets", id: r.id, field: "startsOn"),
                active: r.active,
                createdAt: try DumpParse.timestamp(r.createdAt, table: "budgets", id: r.id, field: "createdAt"),
                updatedAt: try DumpParse.timestamp(r.updatedAt, table: "budgets", id: r.id, field: "updatedAt")
            )
            ctx.insert(m)
            summary.budgets += 1
        }
    }

    @MainActor
    private static func importFxRates(
        _ rows: [DumpFxRate],
        maps: inout IDMaps,
        summary: inout ImportSummary,
        ctx: ModelContext
    ) throws {
        for r in rows {
            let id = try DumpParse.uuid(r.id, table: "fx_rates", id: r.id, field: "id")
            if let existing = try fetchByID(FxRate.self, id: id, ctx: ctx) {
                _ = existing
                continue
            }
            let m = FxRate(
                id: id,
                date: try DumpParse.date(r.date, table: "fx_rates", id: r.id, field: "date"),
                currency: r.currency,
                rate: try DumpParse.decimal(r.rate, table: "fx_rates", id: r.id, field: "rate"),
                createdAt: try DumpParse.timestamp(r.createdAt, table: "fx_rates", id: r.id, field: "createdAt")
            )
            ctx.insert(m)
            summary.fxRates += 1
        }
    }

    @MainActor
    private static func importTransferGroups(
        _ rows: [DumpTransferGroup],
        maps: inout IDMaps,
        summary: inout ImportSummary,
        ctx: ModelContext
    ) throws {
        for r in rows {
            let id = try DumpParse.uuid(r.id, table: "transfer_groups", id: r.id, field: "id")
            if maps.transferGroups[id] != nil {
                throw ImportError.duplicateDumpId(table: "transfer_groups", id: r.id)
            }
            if let existing = try fetchByID(TransferGroup.self, id: id, ctx: ctx) {
                maps.transferGroups[id] = existing
                continue
            }
            let route: TransferRoute? = try resolveOptional(
                r.routeId, in: maps.transferRoutes,
                table: "transfer_groups", id: r.id, field: "routeId"
            )
            let m = TransferGroup(
                id: id,
                pairedAt: try DumpParse.timestamp(r.pairedAt, table: "transfer_groups", id: r.id, field: "pairedAt"),
                route: route,
                createdAt: try DumpParse.timestamp(r.createdAt, table: "transfer_groups", id: r.id, field: "createdAt")
            )
            ctx.insert(m)
            maps.transferGroups[id] = m
            summary.transferGroups += 1
        }
    }

    // MARK: - Phase 2 (transactions, two passes around SEGs)

    @MainActor
    private static func importTransactionsFirstPass(
        _ rows: [DumpTransaction],
        maps: inout IDMaps,
        summary: inout ImportSummary,
        ctx: ModelContext
    ) throws {
        for r in rows {
            let id = try DumpParse.uuid(r.id, table: "transactions", id: r.id, field: "id")
            if maps.transactions[id] != nil {
                throw ImportError.duplicateDumpId(table: "transactions", id: r.id)
            }
            if let existing = try fetchByID(Transaction.self, id: id, ctx: ctx) {
                maps.transactions[id] = existing
                continue
            }
            let direction = try DumpParse.enumValue(
                r.direction, as: TxDirection.self,
                table: "transactions", id: r.id, field: "direction",
                valid: TxDirection.allCases.map(\.rawValue)
            )
            let (categorySource, backfilledNullToBank) = try resolveCategorySource(r)
            if backfilledNullToBank { summary.categorySourceBackfilled += 1 }
            let account: Account = try resolveRequired(
                r.accountId, in: maps.accounts,
                table: "transactions", id: r.id, field: "accountId"
            )
            let category: CoreModel.Category? = try resolveOptional(
                r.categoryId, in: maps.categories,
                table: "transactions", id: r.id, field: "categoryId"
            )
            let transferGroup: TransferGroup? = try resolveOptional(
                r.transferGroupId, in: maps.transferGroups,
                table: "transactions", id: r.id, field: "transferGroupId"
            )
            let route: TransferRoute? = try resolveOptional(
                r.routeId, in: maps.transferRoutes,
                table: "transactions", id: r.id, field: "routeId"
            )
            let rawData = try buildRawData(
                raw: r.raw,
                backfilledCategorySource: backfilledNullToBank
            )
            let m = Transaction(
                id: id,
                account: account,
                externalId: r.externalId,
                bookedAt: try DumpParse.timestamp(r.bookedAt, table: "transactions", id: r.id, field: "bookedAt"),
                valueAt: try DumpParse.timestamp(r.valueAt, table: "transactions", id: r.id, field: "valueAt"),
                amount: try DumpParse.decimal(r.amount, table: "transactions", id: r.id, field: "amount"),
                currency: r.currency,
                amountEur: try DumpParse.decimal(r.amountEur, table: "transactions", id: r.id, field: "amountEur"),
                fxRateUsed: try DumpParse.decimal(r.fxRateUsed, table: "transactions", id: r.id, field: "fxRateUsed"),
                direction: direction,
                description: r.description,
                counterparty: r.counterparty,
                category: category,
                categorySource: categorySource,
                isTransfer: r.isTransfer,
                transferGroup: transferGroup,
                routedFromTx: nil,
                route: route,
                sharedExpenseGroup: nil,
                rawJSON: rawData,
                createdAt: try DumpParse.timestamp(r.createdAt, table: "transactions", id: r.id, field: "createdAt")
            )
            ctx.insert(m)
            maps.transactions[id] = m
            summary.transactions += 1
        }
    }

    @MainActor
    private static func importSharedExpenseGroups(
        _ rows: [DumpSharedExpenseGroup],
        maps: inout IDMaps,
        summary: inout ImportSummary,
        ctx: ModelContext
    ) throws {
        for r in rows {
            let id = try DumpParse.uuid(r.id, table: "shared_expense_groups", id: r.id, field: "id")
            if maps.sharedExpenseGroups[id] != nil {
                throw ImportError.duplicateDumpId(table: "shared_expense_groups", id: r.id)
            }
            if let existing = try fetchByID(SharedExpenseGroup.self, id: id, ctx: ctx) {
                maps.sharedExpenseGroups[id] = existing
                continue
            }
            let primary: Transaction = try resolveRequired(
                r.primaryTxId, in: maps.transactions,
                table: "shared_expense_groups", id: r.id, field: "primaryTxId"
            )
            let month: Date
            if let s = r.attributionMonth {
                month = try DumpParse.date(s, table: "shared_expense_groups", id: r.id, field: "attributionMonth")
            } else {
                month = monthStartUTC(of: primary.bookedAt)
                summary.attributionMonthBackfilled += 1
            }
            let m = SharedExpenseGroup(
                id: id,
                label: r.label,
                primaryTx: primary,
                attributionMonth: month,
                createdAt: try DumpParse.timestamp(r.createdAt, table: "shared_expense_groups", id: r.id, field: "createdAt"),
                updatedAt: try DumpParse.timestamp(r.updatedAt, table: "shared_expense_groups", id: r.id, field: "updatedAt")
            )
            ctx.insert(m)
            maps.sharedExpenseGroups[id] = m
            summary.sharedExpenseGroups += 1
        }
    }

    @MainActor
    private static func linkTransactionsSecondPass(
        _ rows: [DumpTransaction],
        maps: IDMaps
    ) throws {
        for r in rows {
            let id = try DumpParse.uuid(r.id, table: "transactions", id: r.id, field: "id")
            guard let tx = maps.transactions[id] else {
                throw ImportError.orphanReference(
                    table: "transactions", id: r.id, field: "self", referencedId: r.id
                )
            }
            if let routedFromTxId = r.routedFromTxId {
                let routedId = try DumpParse.uuid(
                    routedFromTxId, table: "transactions",
                    id: r.id, field: "routedFromTxId"
                )
                guard let parent = maps.transactions[routedId] else {
                    throw ImportError.orphanReference(
                        table: "transactions", id: r.id,
                        field: "routedFromTxId", referencedId: routedFromTxId
                    )
                }
                tx.routedFromTx = parent
            }
            if let segId = r.sharedExpenseGroupId {
                let sid = try DumpParse.uuid(
                    segId, table: "transactions",
                    id: r.id, field: "sharedExpenseGroupId"
                )
                guard let seg = maps.sharedExpenseGroups[sid] else {
                    throw ImportError.orphanReference(
                        table: "transactions", id: r.id,
                        field: "sharedExpenseGroupId", referencedId: segId
                    )
                }
                tx.sharedExpenseGroup = seg
            }
        }
    }

    @MainActor
    private static func importPortfolioValuations(
        _ rows: [DumpPortfolioValuation],
        maps: inout IDMaps,
        summary: inout ImportSummary,
        ctx: ModelContext
    ) throws {
        for r in rows {
            let id = try DumpParse.uuid(r.id, table: "portfolio_valuations", id: r.id, field: "id")
            if let existing = try fetchByID(PortfolioValuation.self, id: id, ctx: ctx) {
                _ = existing
                continue
            }
            let account: Account = try resolveRequired(
                r.accountId, in: maps.accounts,
                table: "portfolio_valuations", id: r.id, field: "accountId"
            )
            let m = PortfolioValuation(
                id: id,
                account: account,
                asOf: try DumpParse.timestamp(r.asOf, table: "portfolio_valuations", id: r.id, field: "asOf"),
                marketValueEur: try DumpParse.decimal(r.marketValueEur, table: "portfolio_valuations", id: r.id, field: "marketValueEur"),
                cashValueEur: try DumpParse.decimal(r.cashValueEur, table: "portfolio_valuations", id: r.id, field: "cashValueEur"),
                notes: r.notes,
                createdAt: try DumpParse.timestamp(r.createdAt, table: "portfolio_valuations", id: r.id, field: "createdAt"),
                updatedAt: try DumpParse.timestamp(r.updatedAt, table: "portfolio_valuations", id: r.id, field: "updatedAt")
            )
            ctx.insert(m)
            summary.portfolioValuations += 1
        }
    }

    @MainActor
    private static func importSyncRuns(
        _ rows: [DumpSyncRun],
        maps: inout IDMaps,
        summary: inout ImportSummary,
        ctx: ModelContext
    ) throws {
        for r in rows {
            let id = try DumpParse.uuid(r.id, table: "sync_runs", id: r.id, field: "id")
            if let existing = try fetchByID(SyncRun.self, id: id, ctx: ctx) {
                _ = existing
                continue
            }
            let connector = try DumpParse.enumValue(
                r.connector, as: Connector.self,
                table: "sync_runs", id: r.id, field: "connector",
                valid: Connector.allCases.map(\.rawValue)
            )
            let status = try DumpParse.enumValue(
                r.status, as: SyncRunStatus.self,
                table: "sync_runs", id: r.id, field: "status",
                valid: SyncRunStatus.allCases.map(\.rawValue)
            )
            let connection: Connection? = try resolveOptional(
                r.connectionId, in: maps.connections,
                table: "sync_runs", id: r.id, field: "connectionId"
            )
            let m = SyncRun(
                id: id,
                connector: connector,
                connection: connection,
                startedAt: try DumpParse.timestamp(r.startedAt, table: "sync_runs", id: r.id, field: "startedAt"),
                finishedAt: try DumpParse.timestamp(r.finishedAt, table: "sync_runs", id: r.id, field: "finishedAt"),
                status: status,
                insertedTransactions: r.insertedTransactions,
                error: r.error,
                rawJSON: try r.raw?.encoded()
            )
            ctx.insert(m)
            summary.syncRuns += 1
        }
    }

    // MARK: - helpers

    @MainActor
    private static func fetchByID<T: PersistentModel>(
        _ type: T.Type,
        id: UUID,
        ctx: ModelContext
    ) throws -> T? {
        if type == Connection.self {
            let f = FetchDescriptor<Connection>(predicate: #Predicate { $0.id == id })
            return try ctx.fetch(f).first as? T
        }
        if type == AccountGroup.self {
            let f = FetchDescriptor<AccountGroup>(predicate: #Predicate { $0.id == id })
            return try ctx.fetch(f).first as? T
        }
        if type == AccountSpace.self {
            let f = FetchDescriptor<AccountSpace>(predicate: #Predicate { $0.id == id })
            return try ctx.fetch(f).first as? T
        }
        if type == Account.self {
            let f = FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })
            return try ctx.fetch(f).first as? T
        }
        if type == CoreModel.Category.self {
            let f = FetchDescriptor<CoreModel.Category>(predicate: #Predicate { $0.id == id })
            return try ctx.fetch(f).first as? T
        }
        if type == CategoryRule.self {
            let f = FetchDescriptor<CategoryRule>(predicate: #Predicate { $0.id == id })
            return try ctx.fetch(f).first as? T
        }
        if type == TransferRoute.self {
            let f = FetchDescriptor<TransferRoute>(predicate: #Predicate { $0.id == id })
            return try ctx.fetch(f).first as? T
        }
        if type == Budget.self {
            let f = FetchDescriptor<Budget>(predicate: #Predicate { $0.id == id })
            return try ctx.fetch(f).first as? T
        }
        if type == FxRate.self {
            let f = FetchDescriptor<FxRate>(predicate: #Predicate { $0.id == id })
            return try ctx.fetch(f).first as? T
        }
        if type == TransferGroup.self {
            let f = FetchDescriptor<TransferGroup>(predicate: #Predicate { $0.id == id })
            return try ctx.fetch(f).first as? T
        }
        if type == Transaction.self {
            let f = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })
            return try ctx.fetch(f).first as? T
        }
        if type == SharedExpenseGroup.self {
            let f = FetchDescriptor<SharedExpenseGroup>(predicate: #Predicate { $0.id == id })
            return try ctx.fetch(f).first as? T
        }
        if type == PortfolioValuation.self {
            let f = FetchDescriptor<PortfolioValuation>(predicate: #Predicate { $0.id == id })
            return try ctx.fetch(f).first as? T
        }
        if type == SyncRun.self {
            let f = FetchDescriptor<SyncRun>(predicate: #Predicate { $0.id == id })
            return try ctx.fetch(f).first as? T
        }
        return nil
    }

    private static func resolveOptional<T>(
        _ rawId: String?,
        in map: [UUID: T],
        table: String,
        id: String,
        field: String
    ) throws -> T? {
        guard let rawId else { return nil }
        let u = try DumpParse.uuid(rawId, table: table, id: id, field: field)
        guard let v = map[u] else {
            throw ImportError.orphanReference(
                table: table, id: id, field: field, referencedId: rawId
            )
        }
        return v
    }

    private static func resolveRequired<T>(
        _ rawId: String,
        in map: [UUID: T],
        table: String,
        id: String,
        field: String
    ) throws -> T {
        let u = try DumpParse.uuid(rawId, table: table, id: id, field: field)
        guard let v = map[u] else {
            throw ImportError.orphanReference(
                table: table, id: id, field: field, referencedId: rawId
            )
        }
        return v
    }

    private static func resolveCategorySource(
        _ r: DumpTransaction
    ) throws -> (CategorySource, Bool) {
        guard let raw = r.categorySource else {
            return (.bank, true)
        }
        let v = try DumpParse.enumValue(
            raw, as: CategorySource.self,
            table: "transactions", id: r.id, field: "categorySource",
            valid: CategorySource.allCases.map(\.rawValue)
        )
        return (v, false)
    }

    private static func buildRawData(raw: JSONValue?, backfilledCategorySource: Bool) throws -> Data? {
        let base: JSONValue
        switch raw {
        case .some(let v): base = v
        case .none:
            if !backfilledCategorySource { return nil }
            base = .object([:])
        }
        guard backfilledCategorySource else { return try base.encoded() }
        let withMarker: JSONValue
        switch base {
        case .object(var dict):
            dict["_legacyCategorySourceNull"] = .bool(true)
            withMarker = .object(dict)
        default:
            withMarker = .object([
                "_legacyCategorySourceNull": .bool(true),
                "_original": base,
            ])
        }
        return try withMarker.encoded()
    }

    private static func monthStartUTC(of date: Date) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps) ?? date
    }
}
