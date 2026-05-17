import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class CascadeTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema(CoreModelSchema.allTypes)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeAccount(_ ctx: ModelContext, name: String = "Test") -> Account {
        let account = Account(
            externalId: UUID().uuidString,
            type: .bank,
            institution: "Test Bank",
            name: name,
            currency: "EUR"
        )
        ctx.insert(account)
        return account
    }

    private func makeTx(
        _ ctx: ModelContext,
        account: Account,
        amount: Decimal = 100,
        direction: TxDirection = .debit
    ) -> Transaction {
        let tx = Transaction(
            account: account,
            externalId: UUID().uuidString,
            bookedAt: .now,
            amount: amount,
            currency: "EUR",
            direction: direction
        )
        ctx.insert(tx)
        return tx
    }

    func testDeletingSourceCascadesToMirrors() throws {
        let ctx = try makeContext()
        let src = makeAccount(ctx, name: "Source")
        let dst = makeAccount(ctx, name: "Dest")
        let source = makeTx(ctx, account: src, direction: .debit)
        let mirror = makeTx(ctx, account: dst, direction: .credit)
        mirror.routedFromTx = source
        try ctx.save()

        let mirrorID = mirror.persistentModelID

        CoreLogic.deleteTransaction(source, in: ctx)
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<Transaction>())
        XCTAssertFalse(
            remaining.contains { $0.persistentModelID == mirrorID },
            "Mirror tx should cascade-delete when its source is deleted"
        )
    }

    func testDeletingPrimaryCascadesToSharedExpenseGroup() throws {
        let ctx = try makeContext()
        let account = makeAccount(ctx)
        let primary = makeTx(ctx, account: account, amount: 100, direction: .debit)
        let reimbursement = makeTx(ctx, account: account, amount: 30, direction: .credit)

        let group = SharedExpenseGroup(
            label: "Dinner",
            primaryTx: primary,
            attributionMonth: .now
        )
        ctx.insert(group)
        primary.primaryForGroup = group
        reimbursement.sharedExpenseGroup = group
        try ctx.save()

        let groupID = group.persistentModelID
        let reimbursementID = reimbursement.persistentModelID

        CoreLogic.deleteTransaction(primary, in: ctx)
        try ctx.save()

        let groups = try ctx.fetch(FetchDescriptor<SharedExpenseGroup>())
        XCTAssertFalse(
            groups.contains { $0.persistentModelID == groupID },
            "Group should cascade-delete when its primary tx is deleted"
        )

        let txs = try ctx.fetch(FetchDescriptor<Transaction>())
        let leftover = txs.first { $0.persistentModelID == reimbursementID }
        XCTAssertNotNil(leftover, "Non-primary member should still exist")
        XCTAssertNil(leftover?.sharedExpenseGroup, "Non-primary member's group ref should be nullified")
    }

    func testDeletingAccountCascadesToTransferRoutes() throws {
        let ctx = try makeContext()
        let source = makeAccount(ctx, name: "Source")
        let target = makeAccount(ctx, name: "Target")

        let route = TransferRoute(
            pattern: "rent",
            sourceAccount: source,
            targetAccount: target
        )
        ctx.insert(route)
        try ctx.save()

        let routeID = route.persistentModelID

        CoreLogic.deleteAccount(target, in: ctx)
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<TransferRoute>())
        XCTAssertFalse(
            remaining.contains { $0.persistentModelID == routeID },
            "Route should cascade-delete when its target account is deleted"
        )
    }

    func testDeletingAccountCascadesToTransactions() throws {
        let ctx = try makeContext()
        let account = makeAccount(ctx)
        let tx = makeTx(ctx, account: account)
        try ctx.save()

        let txID = tx.persistentModelID

        CoreLogic.deleteAccount(account, in: ctx)
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<Transaction>())
        XCTAssertFalse(remaining.contains { $0.persistentModelID == txID })
    }
}
