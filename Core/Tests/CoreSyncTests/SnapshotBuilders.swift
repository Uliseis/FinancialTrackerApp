import Foundation
@testable import CoreModel
@testable import CoreSync

enum Build {
    static let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    static let later = Date(timeIntervalSince1970: 1_700_100_000)

    static func connection(
        id: UUID = UUID(),
        updatedAt: Date = epoch
    ) -> ConnectionSnapshot {
        ConnectionSnapshot(
            id: id, connector: .enablebanking,
            institutionId: "INST", institutionName: "Test Bank",
            sessionId: "sess",
            accessTokenEnc: "atok", refreshTokenEnc: "rtok",
            metadataJSON: Data([0x7B, 0x7D]),
            status: .active,
            expiresAt: epoch.addingTimeInterval(86_400),
            lastSyncAt: epoch,
            lastError: nil,
            createdAt: epoch, updatedAt: updatedAt
        )
    }

    static func accountGroup(
        id: UUID = UUID(),
        updatedAt: Date = epoch
    ) -> AccountGroupSnapshot {
        AccountGroupSnapshot(
            id: id, name: "Daily", color: "#1f6feb", kind: .cash,
            sortOrder: 0, createdAt: epoch, updatedAt: updatedAt
        )
    }

    static func accountSpace(
        id: UUID = UUID(),
        updatedAt: Date = epoch
    ) -> AccountSpaceSnapshot {
        AccountSpaceSnapshot(
            id: id, name: "Personal", color: nil, isDefault: true,
            sortOrder: 0, createdAt: epoch, updatedAt: updatedAt
        )
    }

    static func account(
        id: UUID = UUID(),
        clock: Date = epoch
    ) -> AccountSnapshot {
        AccountSnapshot(
            id: id,
            connectionId: nil, groupId: nil, spaceId: nil,
            externalId: "EXT_1", type: .bank,
            institution: "Bank", name: "Checking", currency: "EUR",
            iban: "ES0000",
            balance: Decimal(string: "1234.5678"),
            balanceUpdatedAt: epoch,
            metadataJSON: nil,
            archived: false, excluded: false,
            manualOpeningBalance: nil,
            balanceAnchor: nil, balanceAnchorAt: nil,
            createdAt: epoch, clock: clock
        )
    }

    static func category(
        id: UUID = UUID(),
        clock: Date = epoch
    ) -> CategorySnapshot {
        CategorySnapshot(
            id: id, name: "Food", parentId: nil, kind: "expense",
            color: "#ff8800", createdAt: epoch, clock: clock
        )
    }

    static func categoryRule(
        id: UUID = UUID(),
        clock: Date = epoch
    ) -> CategoryRuleSnapshot {
        CategoryRuleSnapshot(
            id: id, pattern: "MERCADONA", field: .description, matchType: .contains,
            categoryId: UUID(), priority: 10,
            createdAt: epoch, clock: clock
        )
    }

    static func transferRoute(
        id: UUID = UUID(),
        updatedAt: Date = epoch
    ) -> TransferRouteSnapshot {
        TransferRouteSnapshot(
            id: id, pattern: "TRANSFER", field: .description, matchType: .contains,
            sourceAccountId: UUID(), targetAccountId: UUID(),
            direction: .debit, priority: 0, enabled: true,
            createdAt: epoch, updatedAt: updatedAt
        )
    }

    static func transferGroup(
        id: UUID = UUID(),
        clock: Date = epoch
    ) -> TransferGroupSnapshot {
        TransferGroupSnapshot(
            id: id, pairedAt: epoch, routeId: UUID(),
            createdAt: epoch, clock: clock
        )
    }

    static func budget(
        id: UUID = UUID(),
        updatedAt: Date = epoch
    ) -> BudgetSnapshot {
        BudgetSnapshot(
            id: id, categoryId: UUID(),
            amountEur: Decimal(string: "300.00")!,
            period: .month,
            startsOn: epoch, active: true,
            createdAt: epoch, updatedAt: updatedAt
        )
    }

    static func fxRate(
        id: UUID = UUID(),
        currency: String = "USD",
        date: Date = epoch,
        createdAt: Date = epoch,
        clock: Date = epoch
    ) -> FxRateSnapshot {
        FxRateSnapshot(
            id: id, date: date, currency: currency,
            rate: Decimal(string: "1.08123456")!,
            createdAt: createdAt, clock: clock
        )
    }

    static func transaction(
        id: UUID = UUID(),
        accountId: UUID = UUID(),
        externalId: String = "TX_EXT_1",
        categoryId: UUID? = nil,
        categorySource: CategorySource = .bank,
        createdAt: Date = epoch,
        clock: Date = epoch
    ) -> TransactionSnapshot {
        TransactionSnapshot(
            id: id, accountId: accountId,
            externalId: externalId, bookedAt: epoch, valueAt: nil,
            amount: Decimal(string: "-87.45")!, currency: "EUR",
            amountEur: Decimal(string: "-87.45"), fxRateUsed: nil,
            direction: .debit,
            transactionDescription: "MERCADONA", counterparty: "Mercadona",
            categoryId: categoryId, categorySource: categorySource,
            isTransfer: false,
            transferGroupId: nil, routedFromTxId: nil, routeId: nil,
            sharedExpenseGroupId: nil,
            rawJSON: nil,
            createdAt: createdAt, clock: clock
        )
    }

    static func sharedExpenseGroup(
        id: UUID = UUID(),
        updatedAt: Date = epoch
    ) -> SharedExpenseGroupSnapshot {
        SharedExpenseGroupSnapshot(
            id: id, label: "Groceries split",
            primaryTxId: UUID(), attributionMonth: epoch,
            createdAt: epoch, updatedAt: updatedAt
        )
    }

    static func portfolioValuation(
        id: UUID = UUID(),
        updatedAt: Date = epoch
    ) -> PortfolioValuationSnapshot {
        PortfolioValuationSnapshot(
            id: id, accountId: UUID(), asOf: epoch,
            marketValueEur: Decimal(string: "51234.56")!,
            cashValueEur: Decimal(string: "1234.56"),
            notes: nil,
            createdAt: epoch, updatedAt: updatedAt
        )
    }

    static func syncRun(
        id: UUID = UUID(),
        startedAt: Date = epoch
    ) -> SyncRunSnapshot {
        SyncRunSnapshot(
            id: id, connector: .enablebanking,
            connectionId: UUID(),
            startedAt: startedAt, finishedAt: startedAt.addingTimeInterval(30),
            status: .ok, insertedTransactions: 12,
            error: nil, rawJSON: nil
        )
    }
}
