import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

// Regression guard: on iOS 26 / macOS 26, SwiftData's @Relationship deleteRules
// (.cascade and .nullify) fire reliably on a bare `ctx.delete` + save. This is what
// lets us drive deletes straight through the model graph instead of hand-rolled
// cascade helpers. If any of these fail on a future SDK, restore explicit helpers.
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

    // MARK: - .cascade

    func testDeletingSourceCascadesToMirrors() throws {
        let ctx = try makeContext()
        let src = makeAccount(ctx, name: "Source")
        let dst = makeAccount(ctx, name: "Dest")
        let source = makeTx(ctx, account: src, direction: .debit)
        let mirror = makeTx(ctx, account: dst, direction: .credit)
        mirror.routedFromTx = source
        try ctx.save()

        let mirrorID = mirror.persistentModelID
        ctx.delete(source)
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

        let group = SharedExpenseGroup(label: "Dinner", primaryTx: primary, attributionMonth: .now)
        ctx.insert(group)
        primary.primaryForGroup = group
        reimbursement.sharedExpenseGroup = group
        try ctx.save()

        let groupID = group.persistentModelID
        let reimbursementID = reimbursement.persistentModelID

        ctx.delete(primary)
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

        let route = TransferRoute(pattern: "rent", sourceAccount: source, targetAccount: target)
        ctx.insert(route)
        try ctx.save()

        let routeID = route.persistentModelID
        ctx.delete(target)
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
        ctx.delete(account)
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<Transaction>())
        XCTAssertFalse(remaining.contains { $0.persistentModelID == txID })
    }

    func testDeletingAccountCascadesToValuations() throws {
        let ctx = try makeContext()
        let account = makeAccount(ctx)
        let v = PortfolioValuation(account: account, asOf: .now, marketValueEur: 1000)
        ctx.insert(v)
        try ctx.save()

        let vID = v.persistentModelID
        ctx.delete(account)
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<PortfolioValuation>())
        XCTAssertFalse(remaining.contains { $0.persistentModelID == vID })
    }

    // Connection → Accounts → Transactions, transitively, in one delete.
    func testDeletingConnectionCascadesTransitively() throws {
        let ctx = try makeContext()
        let conn = Connection(connector: .enablebanking)
        ctx.insert(conn)
        let account = makeAccount(ctx)
        account.connection = conn
        let tx = makeTx(ctx, account: account)
        try ctx.save()

        let accountID = account.persistentModelID
        let txID = tx.persistentModelID
        ctx.delete(conn)
        try ctx.save()

        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        XCTAssertFalse(accounts.contains { $0.persistentModelID == accountID },
                       "Account should cascade-delete with its connection")
        let txs = try ctx.fetch(FetchDescriptor<Transaction>())
        XCTAssertFalse(txs.contains { $0.persistentModelID == txID },
                       "Transaction should cascade-delete transitively through its account")
    }

    // MARK: - .nullify

    func testDeletingSharedExpenseGroupNullifiesMembers() throws {
        let ctx = try makeContext()
        let account = makeAccount(ctx)
        let member = makeTx(ctx, account: account, amount: 30, direction: .credit)
        let group = SharedExpenseGroup(label: "Trip", attributionMonth: .now)
        ctx.insert(group)
        member.sharedExpenseGroup = group
        try ctx.save()

        let memberID = member.persistentModelID
        ctx.delete(group)
        try ctx.save()

        let txs = try ctx.fetch(FetchDescriptor<Transaction>())
        let survivor = txs.first { $0.persistentModelID == memberID }
        XCTAssertNotNil(survivor, "Member tx should survive group deletion")
        XCTAssertNil(survivor?.sharedExpenseGroup, "Member's group ref should be nullified, not dangling")
    }

    func testDeletingConnectionNullifiesSyncRuns() throws {
        let ctx = try makeContext()
        let conn = Connection(connector: .enablebanking)
        ctx.insert(conn)
        let run = SyncRun(connector: .enablebanking, connection: conn)
        ctx.insert(run)
        try ctx.save()

        let runID = run.persistentModelID
        ctx.delete(conn)
        try ctx.save()

        let runs = try ctx.fetch(FetchDescriptor<SyncRun>())
        let survivor = runs.first { $0.persistentModelID == runID }
        XCTAssertNotNil(survivor, "SyncRun should survive connection deletion")
        XCTAssertNil(survivor?.connection, "SyncRun's connection ref should be nullified, not dangling")
    }
}
