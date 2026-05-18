import Foundation
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
enum TransferTestSupport {
    static func makeContext() throws -> ModelContext {
        let schema = Schema(CoreModelSchema.allTypes)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    static func makeSpace(_ ctx: ModelContext, name: String = "Personal") -> AccountSpace {
        let s = AccountSpace(name: name, isDefault: true)
        ctx.insert(s)
        return s
    }

    static func makeAccount(
        _ ctx: ModelContext,
        name: String,
        space: AccountSpace? = nil,
        archived: Bool = false,
        excluded: Bool = false,
        connection: Connection? = nil
    ) -> Account {
        let a = Account(
            connection: connection,
            space: space,
            externalId: UUID().uuidString,
            type: .bank,
            institution: "Test",
            name: name,
            currency: "EUR",
            archived: archived,
            excluded: excluded
        )
        ctx.insert(a)
        return a
    }

    static func makeTx(
        _ ctx: ModelContext,
        account: Account,
        amount: Decimal,
        currency: String = "EUR",
        amountEur: Decimal? = nil,
        direction: TxDirection,
        bookedAt: Date = .now,
        description: String? = nil,
        counterparty: String? = nil,
        isTransfer: Bool = false,
        transferGroup: TransferGroup? = nil,
        routedFromTx: Transaction? = nil,
        route: TransferRoute? = nil,
        sharedExpenseGroup: SharedExpenseGroup? = nil,
        categorySource: CategorySource = .bank,
        externalId: String? = nil
    ) -> Transaction {
        let tx = Transaction(
            account: account,
            externalId: externalId ?? UUID().uuidString,
            bookedAt: bookedAt,
            amount: amount,
            currency: currency,
            amountEur: amountEur ?? (currency == "EUR" ? amount : nil),
            direction: direction,
            description: description,
            counterparty: counterparty,
            categorySource: categorySource,
            isTransfer: isTransfer,
            transferGroup: transferGroup,
            routedFromTx: routedFromTx,
            route: route,
            sharedExpenseGroup: sharedExpenseGroup
        )
        ctx.insert(tx)
        return tx
    }

    static func makeRoute(
        _ ctx: ModelContext,
        pattern: String,
        field: RuleField = .description,
        matchType: RuleMatch = .contains,
        source: Account? = nil,
        target: Account,
        direction: TxDirection? = nil,
        priority: Int = 0,
        enabled: Bool = true,
        createdAt: Date = .now
    ) -> TransferRoute {
        let r = TransferRoute(
            pattern: pattern,
            field: field,
            matchType: matchType,
            sourceAccount: source,
            targetAccount: target,
            direction: direction,
            priority: priority,
            enabled: enabled,
            createdAt: createdAt
        )
        ctx.insert(r)
        return r
    }
}
