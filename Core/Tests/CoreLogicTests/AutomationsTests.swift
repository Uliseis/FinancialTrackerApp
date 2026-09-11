import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class AutomationsTests: XCTestCase {
    typealias S = TransferTestSupport
    typealias A = CoreLogic.Automations

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testBooksDueRecurringOnceAndHonoursMuteAndDecline() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let card = try CoreLogic.Accounts.createManual(
            name: "Card", institution: "Revolut", currency: "EUR", space: space, in: ctx)
        for d in [day(2026, 6, 12), day(2026, 7, 15), day(2026, 8, 12)] {
            _ = S.makeTx(ctx, account: card, amount: Decimal(string: "-4.99")!, direction: .debit, bookedAt: d, description: "Google One")
        }

        // Not due yet on the 5th.
        XCTAssertEqual(try A.bookDueRecurring(in: ctx, muted: [], declined: [], now: day(2026, 9, 5), calendar: utc).count, 0)

        let booked = try A.bookDueRecurring(in: ctx, muted: [], declined: [], now: day(2026, 9, 15), calendar: utc)
        XCTAssertEqual(booked.count, 1)
        XCTAssertEqual(booked[0].merchant, "Google One")
        XCTAssertEqual(booked[0].amount, Decimal(string: "-4.99"))
        XCTAssertEqual(booked[0].externalId, "auto-recurring:v1:2026-09:google-one-4-99")
        let tx = try XCTUnwrap(ctx.fetch(FetchDescriptor<Transaction>()).first { $0.externalId == booked[0].externalId })
        XCTAssertEqual(tx.amount, Decimal(string: "-4.99"))
        XCTAssertEqual(tx.direction, .debit)

        // Idempotent.
        XCTAssertEqual(try A.bookDueRecurring(in: ctx, muted: [], declined: [], now: day(2026, 9, 16), calendar: utc).count, 0)

        // Deleted by the user ⇒ declined for the month, never re-booked.
        try CoreLogic.Transactions.delete(tx, in: ctx)
        XCTAssertEqual(try A.bookDueRecurring(in: ctx, muted: [], declined: [booked[0].externalId], now: day(2026, 9, 20), calendar: utc).count, 0)
        // Stopped ⇒ never again, even next month.
        XCTAssertEqual(try A.bookDueRecurring(in: ctx, muted: [booked[0].key], declined: [], now: day(2026, 9, 20), calendar: utc).count, 0)
    }

    // An auto-booked row is not evidence that the subscription still exists; only a row the
    // statement import confirmed (id rewritten to revolutcsv) keeps the pattern alive.
    func testAutoBookedRowsDoNotSelfPerpetuate() throws {
        let ctx = try S.makeContext()
        let card = S.makeAccount(ctx, name: "Card")
        for (m, d) in [(6, 12), (7, 12), (8, 12)] {
            _ = S.makeTx(ctx, account: card, amount: Decimal(string: "-4.99")!, direction: .debit, bookedAt: day(2026, m, d),
                         description: "Google One", externalId: "auto-recurring:v1:2026-0\(m):google-one-4-99")
        }
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        XCTAssertTrue(CoreLogic.Recurring.detect(all, month: day(2026, 9, 15), calendar: utc).isEmpty)
    }

    func testPensionSplitBooksOncePerArrivalAndUndoes() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let funds = S.makeAccount(ctx, name: "MyInvestor Investment", space: space)
        let pension = S.makeAccount(ctx, name: "MyInvestor Pension", space: space)
        let arrival = S.makeTx(ctx, account: funds, amount: 1600, direction: .credit,
                               bookedAt: day(2026, 8, 24), description: "TRANSFER MYINVESTOR",
                               isTransfer: true, externalId: "mirror:abc")
        _ = S.makeTx(ctx, account: funds, amount: 1000, direction: .credit,
                     bookedAt: day(2026, 7, 20), description: "old", isTransfer: true, externalId: "mirror:old")
        let rule = A.SplitRule(sourceAccountId: funds.id, targetAccountId: pension.id,
                               amountEur: 125, since: day(2026, 8, 1))

        let splits = try A.bookSplits(rule: rule, in: ctx, declined: [])
        XCTAssertEqual(splits.count, 1)
        XCTAssertEqual(splits[0].arrivalTxId, arrival.id)
        XCTAssertEqual(splits[0].arrivedEur, 1600)
        let debit = try XCTUnwrap(ctx.fetch(FetchDescriptor<Transaction>()).first { $0.id == splits[0].debitTxId })
        XCTAssertEqual(debit.amount, -125)
        XCTAssertEqual(debit.bookedAt, arrival.bookedAt)
        XCTAssertEqual(A.splitSource(of: debit), arrival.id)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Transaction>()).filter { $0.account?.id == pension.id }.map(\.amount), [125])

        XCTAssertEqual(try A.bookSplits(rule: rule, in: ctx, declined: []).count, 0)

        let undone = try A.undoSplit(debitTxId: splits[0].debitTxId, in: ctx)
        XCTAssertEqual(undone, arrival.id)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Transaction>()), 2)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<TransferGroup>()), 0)
        XCTAssertEqual(try A.bookSplits(rule: rule, in: ctx, declined: [arrival.id]).count, 0)
    }
}
