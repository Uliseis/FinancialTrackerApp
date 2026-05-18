import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class CategorizeTests: XCTestCase {
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

    private func makeAccount(_ ctx: ModelContext) -> Account {
        let a = Account(
            externalId: UUID().uuidString,
            type: .bank,
            institution: "Test",
            name: "Checking",
            currency: "EUR"
        )
        ctx.insert(a)
        return a
    }

    private func makeTx(
        _ ctx: ModelContext,
        account: Account,
        description: String? = nil,
        counterparty: String? = nil,
        category: CoreModel.Category? = nil,
        categorySource: CategorySource = .bank
    ) -> Transaction {
        let tx = Transaction(
            account: account,
            externalId: UUID().uuidString,
            bookedAt: .now,
            amount: 10,
            currency: "EUR",
            direction: .debit,
            description: description,
            counterparty: counterparty,
            category: category,
            categorySource: categorySource
        )
        ctx.insert(tx)
        return tx
    }

    private func makeCategory(_ ctx: ModelContext, name: String) -> CoreModel.Category {
        let c = CoreModel.Category(name: name)
        ctx.insert(c)
        return c
    }

    private func makeRule(
        _ ctx: ModelContext,
        pattern: String,
        field: RuleField = .description,
        matchType: RuleMatch = .contains,
        category: CoreModel.Category,
        priority: Int = 0,
        createdAt: Date = .now
    ) -> CategoryRule {
        let r = CategoryRule(
            pattern: pattern,
            field: field,
            matchType: matchType,
            category: category,
            priority: priority,
            createdAt: createdAt
        )
        ctx.insert(r)
        return r
    }

    private func ruleFor(
        _ pattern: String,
        field: RuleField = .description,
        matchType: RuleMatch = .contains
    ) -> CategoryRule {
        CategoryRule(pattern: pattern, field: field, matchType: matchType)
    }

    // MARK: - matches()

    func testMatchesContainsIsCaseInsensitive() {
        let tx = Transaction(
            externalId: "x", bookedAt: .now, amount: 0, currency: "EUR",
            direction: .debit, description: "Spotify AB Stockholm"
        )
        XCTAssertTrue(CoreLogic.Categorize.matches(rule: ruleFor("spotify"), tx: tx))
        XCTAssertTrue(CoreLogic.Categorize.matches(rule: ruleFor("STOCKHOLM"), tx: tx))
        XCTAssertFalse(CoreLogic.Categorize.matches(rule: ruleFor("netflix"), tx: tx))
    }

    func testMatchesEquals() {
        let tx = Transaction(
            externalId: "x", bookedAt: .now, amount: 0, currency: "EUR",
            direction: .debit, description: "RENT"
        )
        XCTAssertTrue(CoreLogic.Categorize.matches(rule: ruleFor("rent", matchType: .equals), tx: tx))
        XCTAssertFalse(CoreLogic.Categorize.matches(rule: ruleFor("rent payment", matchType: .equals), tx: tx))
    }

    func testMatchesStartsWith() {
        let tx = Transaction(
            externalId: "x", bookedAt: .now, amount: 0, currency: "EUR",
            direction: .debit, description: "Amazon EU SARL"
        )
        XCTAssertTrue(CoreLogic.Categorize.matches(rule: ruleFor("amazon", matchType: .startsWith), tx: tx))
        XCTAssertFalse(CoreLogic.Categorize.matches(rule: ruleFor("sarl", matchType: .startsWith), tx: tx))
    }

    func testMatchesEndsWith() {
        let tx = Transaction(
            externalId: "x", bookedAt: .now, amount: 0, currency: "EUR",
            direction: .debit, description: "Amazon EU SARL"
        )
        XCTAssertTrue(CoreLogic.Categorize.matches(rule: ruleFor("sarl", matchType: .endsWith), tx: tx))
        XCTAssertFalse(CoreLogic.Categorize.matches(rule: ruleFor("amazon", matchType: .endsWith), tx: tx))
    }

    func testMatchesRegex() {
        let tx = Transaction(
            externalId: "x", bookedAt: .now, amount: 0, currency: "EUR",
            direction: .debit, description: "Card 1234 Amazon"
        )
        XCTAssertTrue(CoreLogic.Categorize.matches(rule: ruleFor(#"card \d+"#, matchType: .regex), tx: tx))
        XCTAssertFalse(CoreLogic.Categorize.matches(rule: ruleFor(#"card [a-z]+"#, matchType: .regex), tx: tx))
    }

    func testMatchesRegexInvalidPatternReturnsFalse() {
        let tx = Transaction(
            externalId: "x", bookedAt: .now, amount: 0, currency: "EUR",
            direction: .debit, description: "anything"
        )
        XCTAssertFalse(CoreLogic.Categorize.matches(rule: ruleFor("[unterminated", matchType: .regex), tx: tx))
    }

    func testMatchesFieldCounterparty() {
        let tx = Transaction(
            externalId: "x", bookedAt: .now, amount: 0, currency: "EUR",
            direction: .debit, description: "ignored", counterparty: "Mercadona SA"
        )
        XCTAssertTrue(CoreLogic.Categorize.matches(rule: ruleFor("mercadona", field: .counterparty), tx: tx))
        XCTAssertFalse(CoreLogic.Categorize.matches(rule: ruleFor("mercadona", field: .description), tx: tx))
    }

    func testMatchesEmptyPatternIsFalse() {
        let tx = Transaction(
            externalId: "x", bookedAt: .now, amount: 0, currency: "EUR",
            direction: .debit, description: "anything"
        )
        XCTAssertFalse(CoreLogic.Categorize.matches(rule: ruleFor(""), tx: tx))
    }

    func testMatchesNilFieldHaystackIsFalse() {
        let tx = Transaction(
            externalId: "x", bookedAt: .now, amount: 0, currency: "EUR",
            direction: .debit
        )
        XCTAssertFalse(CoreLogic.Categorize.matches(rule: ruleFor("anything"), tx: tx))
    }

    // MARK: - applyRulesToTransactions()

    func testApplyRulesDoesNotTouchManual() throws {
        let ctx = try makeContext()
        let account = makeAccount(ctx)
        let groceries = makeCategory(ctx, name: "Groceries")
        let dining = makeCategory(ctx, name: "Dining")
        _ = makeRule(ctx, pattern: "mercadona", category: groceries)
        let tx = makeTx(
            ctx,
            account: account,
            description: "MERCADONA 123",
            category: dining,
            categorySource: .manual
        )
        try ctx.save()

        let result = try CoreLogic.Categorize.applyRulesToTransactions(in: ctx)

        XCTAssertEqual(result.updated, 0, "Manual-locked tx must not be re-categorized")
        XCTAssertEqual(result.scanned, 0, "Manual-locked tx must not appear in scan set")
        XCTAssertEqual(tx.categorySource, .manual)
        XCTAssertEqual(tx.category?.id, dining.id)
    }

    func testApplyRulesPriorityDescOrdering() throws {
        let ctx = try makeContext()
        let account = makeAccount(ctx)
        let groceries = makeCategory(ctx, name: "Groceries")
        let dining = makeCategory(ctx, name: "Dining")
        _ = makeRule(ctx, pattern: "mercadona", category: groceries, priority: 1)
        _ = makeRule(ctx, pattern: "mercadona", category: dining, priority: 10)
        let tx = makeTx(ctx, account: account, description: "MERCADONA 123")
        try ctx.save()

        let result = try CoreLogic.Categorize.applyRulesToTransactions(in: ctx)

        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(tx.category?.id, dining.id, "Higher-priority rule must win")
        XCTAssertEqual(tx.categorySource, .rule)
    }

    func testApplyRulesTieBreakIsCreatedAtAscending() throws {
        let ctx = try makeContext()
        let account = makeAccount(ctx)
        let groceries = makeCategory(ctx, name: "Groceries")
        let dining = makeCategory(ctx, name: "Dining")
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_800_000_000)
        _ = makeRule(ctx, pattern: "mercadona", category: dining, priority: 5, createdAt: newer)
        _ = makeRule(ctx, pattern: "mercadona", category: groceries, priority: 5, createdAt: older)
        let tx = makeTx(ctx, account: account, description: "MERCADONA 123")
        try ctx.save()

        let result = try CoreLogic.Categorize.applyRulesToTransactions(in: ctx)

        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(tx.category?.id, groceries.id, "Older rule wins the tie-break")
    }

    func testApplyRulesIsIdempotent() throws {
        let ctx = try makeContext()
        let account = makeAccount(ctx)
        let groceries = makeCategory(ctx, name: "Groceries")
        _ = makeRule(ctx, pattern: "mercadona", category: groceries)
        _ = makeTx(ctx, account: account, description: "MERCADONA 123")
        try ctx.save()

        let first = try CoreLogic.Categorize.applyRulesToTransactions(in: ctx)
        XCTAssertEqual(first.updated, 1)

        let second = try CoreLogic.Categorize.applyRulesToTransactions(in: ctx)
        XCTAssertEqual(second.updated, 0, "Second pass must not update a tx already at the same (rule, category)")
        XCTAssertEqual(second.scanned, 1, "Tx remains in scan set; just no write")
    }

    func testApplyRulesDefaultBankSourceGetsCategorized() throws {
        // Asserts the schema invariant: categorySource is non-optional and defaults
        // to .bank at insert time, so the TS `isNull(categorySource)` branch is dead code.
        let ctx = try makeContext()
        let account = makeAccount(ctx)
        let groceries = makeCategory(ctx, name: "Groceries")
        _ = makeRule(ctx, pattern: "mercadona", category: groceries)
        let tx = makeTx(ctx, account: account, description: "MERCADONA 123")
        try ctx.save()

        XCTAssertEqual(tx.categorySource, .bank, "Default-inserted tx is .bank, never nil")

        let result = try CoreLogic.Categorize.applyRulesToTransactions(in: ctx)
        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(tx.categorySource, .rule)
        XCTAssertEqual(tx.category?.id, groceries.id)
    }

    func testApplyRulesScopedByTxIds() throws {
        let ctx = try makeContext()
        let account = makeAccount(ctx)
        let groceries = makeCategory(ctx, name: "Groceries")
        _ = makeRule(ctx, pattern: "mercadona", category: groceries)
        let inScope = makeTx(ctx, account: account, description: "MERCADONA 123")
        let outOfScope = makeTx(ctx, account: account, description: "MERCADONA 456")
        try ctx.save()

        let result = try CoreLogic.Categorize.applyRulesToTransactions(in: ctx, txIds: [inScope.id])

        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(result.scanned, 1)
        XCTAssertEqual(inScope.category?.id, groceries.id)
        XCTAssertNil(outOfScope.category, "Tx outside the txIds filter must be untouched")
    }

    func testApplyRulesNoRulesShortCircuits() throws {
        let ctx = try makeContext()
        let account = makeAccount(ctx)
        _ = makeTx(ctx, account: account, description: "anything")
        try ctx.save()

        let result = try CoreLogic.Categorize.applyRulesToTransactions(in: ctx)
        XCTAssertEqual(result.updated, 0)
        XCTAssertEqual(result.scanned, 0)
    }

    func testApplyRulesSkipsRuleWithoutCategory() throws {
        let ctx = try makeContext()
        let account = makeAccount(ctx)
        let rule = CategoryRule(pattern: "mercadona", category: nil)
        ctx.insert(rule)
        let tx = makeTx(ctx, account: account, description: "MERCADONA 123")
        try ctx.save()

        let result = try CoreLogic.Categorize.applyRulesToTransactions(in: ctx)
        XCTAssertEqual(result.updated, 0)
        XCTAssertNil(tx.category)
        XCTAssertEqual(tx.categorySource, .bank)
    }
}
