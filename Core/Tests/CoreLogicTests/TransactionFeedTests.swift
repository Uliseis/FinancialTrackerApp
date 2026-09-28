import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class TransactionFeedTests: XCTestCase {
    typealias S = TransferTestSupport
    typealias F = CoreLogic.TransactionFeed

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private struct Fixture {
        let ctx: ModelContext
        let a: Account
        let b: Account
        let groceries: CoreModel.Category
    }

    private func fixture() throws -> Fixture {
        let ctx = try S.makeContext()
        let a = S.makeAccount(ctx, name: "A")
        let b = S.makeAccount(ctx, name: "B")
        let groceries = CoreModel.Category(name: "Groceries", kind: "expense")
        ctx.insert(groceries)
        return Fixture(ctx: ctx, a: a, b: b, groceries: groceries)
    }

    private func ids(_ txs: [Transaction]) -> [String?] { txs.map(\.transactionDescription) }

    func testPagesNewestFirstAcrossTheWholeSet() throws {
        let f = try fixture()
        for d in 1...5 {
            _ = S.makeTx(f.ctx, account: f.a, amount: -1, direction: .debit,
                         bookedAt: day(2026, 3, d), description: "d\(d)")
        }
        try f.ctx.save()
        let filter = F.Filter(accountIds: [f.a.id])

        XCTAssertEqual(ids(try F.page(filter, offset: 0, limit: 2, in: f.ctx)), ["d5", "d4"])
        XCTAssertEqual(ids(try F.page(filter, offset: 2, limit: 2, in: f.ctx)), ["d3", "d2"])
        XCTAssertEqual(ids(try F.page(filter, offset: 4, limit: 2, in: f.ctx)), ["d1"])
    }

    func testFiltersMatchTheOldInMemoryRules() throws {
        let f = try fixture()
        let keep = S.makeTx(f.ctx, account: f.a, amount: -5, direction: .debit,
                            bookedAt: day(2026, 3, 1), description: "Mercadona", category: f.groceries)
        _ = S.makeTx(f.ctx, account: f.b, amount: -5, direction: .debit,
                     bookedAt: day(2026, 3, 2), description: "other account")
        let transfer = S.makeTx(f.ctx, account: f.a, amount: -9, direction: .debit,
                                bookedAt: day(2026, 3, 3), description: "to savings", isTransfer: true)
        _ = S.makeTx(f.ctx, account: f.a, amount: 9, direction: .credit,
                     bookedAt: day(2026, 3, 3), description: "mirror", isTransfer: true,
                     routedFromTx: transfer)
        let uncategorized = S.makeTx(f.ctx, account: f.a, amount: -2, direction: .debit,
                                     bookedAt: day(2026, 3, 4), counterparty: "MERCADONA SA")
        try f.ctx.save()

        var filter = F.Filter(accountIds: [f.a.id])
        XCTAssertEqual(Set(try F.page(filter, offset: 0, limit: 50, in: f.ctx).map(\.id)),
                       [keep.id, uncategorized.id], "no other account, transfer or mirror leg")

        filter.includeTransfers = true
        XCTAssertEqual(Set(try F.page(filter, offset: 0, limit: 50, in: f.ctx).map(\.id)),
                       [keep.id, uncategorized.id, transfer.id], "a mirror leg never shows")

        filter = F.Filter(accountIds: [f.a.id], category: .uncategorized)
        XCTAssertEqual(try F.page(filter, offset: 0, limit: 50, in: f.ctx).map(\.id), [uncategorized.id])

        filter = F.Filter(accountIds: [f.a.id], category: .category(f.groceries.id))
        XCTAssertEqual(try F.page(filter, offset: 0, limit: 50, in: f.ctx).map(\.id), [keep.id])

        // Case- and accent-insensitive, description or counterparty.
        filter = F.Filter(accountIds: [f.a.id], search: "mercadona")
        XCTAssertEqual(Set(try F.page(filter, offset: 0, limit: 50, in: f.ctx).map(\.id)),
                       [keep.id, uncategorized.id])
    }

    func testTotalsCoverEveryMatchNotJustLoadedPages() throws {
        let f = try fixture()
        _ = S.makeTx(f.ctx, account: f.a, amount: -10, direction: .debit, bookedAt: day(2026, 3, 1, 0))
        _ = S.makeTx(f.ctx, account: f.a, amount: -5, direction: .debit, bookedAt: day(2026, 3, 31, 23))
        _ = S.makeTx(f.ctx, account: f.a, amount: 100, direction: .credit, bookedAt: day(2026, 4, 1, 0))
        _ = S.makeTx(f.ctx, account: f.b, amount: -1, direction: .debit, bookedAt: day(2026, 3, 2))
        try f.ctx.save()
        let filter = F.Filter(accountIds: [f.a.id])

        XCTAssertEqual(try F.count(filter, in: f.ctx), 3)
        XCTAssertEqual(try F.netEur(filter, in: f.ctx), 85)
        XCTAssertEqual(try F.monthNetEur(filter, month: day(2026, 3, 15), calendar: utc, in: f.ctx), -15,
                       "first and last instant of the month are in; the next month's first isn't")
        XCTAssertEqual(try F.monthNetEur(filter, month: day(2026, 4, 15), calendar: utc, in: f.ctx), 100)
        XCTAssertEqual(F.monthStart(day(2026, 3, 31, 23), calendar: utc), day(2026, 3, 1, 0))
    }

    func testEmptyAccountSetMatchesNothing() throws {
        let f = try fixture()
        _ = S.makeTx(f.ctx, account: f.a, amount: -1, direction: .debit)
        try f.ctx.save()
        XCTAssertTrue(try F.page(F.Filter(accountIds: []), offset: 0, limit: 10, in: f.ctx).isEmpty)
        XCTAssertEqual(try F.count(F.Filter(accountIds: []), in: f.ctx), 0)
        XCTAssertEqual(try F.netEur(F.Filter(accountIds: []), in: f.ctx), 0)
    }

    // Rows sharing bookedAt and createdAt need a unique last key, or offset paging relies on
    // the store happening to return ties in the same order every time.
    func testTiesBreakOnIdSoPagesAreDeterministic() throws {
        let f = try fixture()
        let when = day(2026, 6, 15)
        for i in 0..<20 {
            let tx = S.makeTx(f.ctx, account: f.a, amount: -1, direction: .debit,
                              bookedAt: when, description: "tie \(i)")
            tx.createdAt = when
        }
        try f.ctx.save()
        let filter = F.Filter(accountIds: [f.a.id])
        var paged: [UUID] = []
        while case let page = try F.page(filter, offset: paged.count, limit: 7, in: f.ctx), !page.isEmpty {
            paged += page.map(\.id)
        }
        XCTAssertEqual(paged.count, 20)
        XCTAssertEqual(paged, paged.sorted(by: >))
    }
}

