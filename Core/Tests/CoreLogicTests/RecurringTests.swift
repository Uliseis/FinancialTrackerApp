import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class RecurringTests: XCTestCase {
    typealias S = TransferTestSupport

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testMonthlyChargesSurfaceWithBookedState() throws {
        let ctx = try S.makeContext()
        let card = S.makeAccount(ctx, name: "Card")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        func charge(_ amount: String, _ desc: String, _ d: Date) {
            _ = S.makeTx(ctx, account: card, amount: -Decimal(string: amount)!, direction: .debit, bookedAt: d, description: desc)
        }
        // Subscription: once a month, Jun/Jul/Aug, not yet booked in September.
        charge("4.99", "Google One", day(2026, 6, 12)); charge("4.99", "Google One", day(2026, 7, 15)); charge("4.99", "Google One", day(2026, 8, 12))
        // Booked already this month.
        charge("10", "Consorcio Transportes", day(2026, 7, 15)); charge("10", "Consorcio Transportes", day(2026, 8, 17)); charge("10", "CONSORCIO TRANSPORTES", day(2026, 9, 15))
        // A habit, not a subscription: several per month.
        charge("6", "Mimbre", day(2026, 7, 4)); charge("6", "Mimbre", day(2026, 7, 19)); charge("6", "Mimbre", day(2026, 8, 18))
        // Same merchant, different amounts: never groups.
        charge("12.99", "Supermercado", day(2026, 7, 8)); charge("46.37", "Supermercado", day(2026, 8, 4))
        // Same amount once a month but on the 31st and then the 3rd: a bar, not a subscription.
        charge("16", "Mimbre", day(2026, 7, 31)); charge("16", "Mimbre", day(2026, 8, 3))
        // Cancelled: last seen 3 months back.
        charge("9.99", "Netflix", day(2026, 5, 1)); charge("9.99", "Netflix", day(2026, 6, 1))
        // A top-up mirror is never a charge.
        _ = S.makeTx(ctx, account: card, amount: 100, direction: .credit, bookedAt: day(2026, 8, 1), description: "To EUR", isTransfer: true)

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        let items = CoreLogic.Recurring.detect(all, month: day(2026, 9, 11), calendar: utc)

        XCTAssertEqual(items.map(\.merchant), ["Google One", "Consorcio Transportes"])
        XCTAssertEqual(items[0].amount, Decimal(string: "-4.99"))
        XCTAssertEqual(items[0].expectedDay, 12)
        XCTAssertEqual(items[0].seenMonths, 3)
        XCTAssertNil(items[0].bookedAt)
        XCTAssertEqual(items[1].expectedDay, 17)
        XCTAssertEqual(items[1].bookedAt, day(2026, 9, 15))
    }

    func testPinOverridesDayAndSurvivesSpreadGuard() throws {
        let ctx = try S.makeContext()
        let card = S.makeAccount(ctx, name: "Card")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        for (m, d) in [(6, 12), (7, 12), (8, 12)] {
            _ = S.makeTx(ctx, account: card, amount: Decimal(string: "-4.99")!, direction: .debit, bookedAt: day(2026, m, d), description: "Google One")
        }
        for (m, d) in [(7, 18), (8, 20), (9, 27)] {
            _ = S.makeTx(ctx, account: card, amount: Decimal(string: "-9.99")!, direction: .debit, bookedAt: day(2026, m, d), description: "Amazon Prime")
        }
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        let october = day(2026, 10, 3)
        XCTAssertEqual(CoreLogic.Recurring.detect(all, month: october, calendar: utc).map(\.merchant), ["Google One"])

        let pins = [
            CoreLogic.Recurring.Pin(accountId: card.id, key: "google one|-4.99", merchant: "Google One", amount: Decimal(string: "-4.99")!, day: 20),
            CoreLogic.Recurring.Pin(accountId: card.id, key: "amazon prime|-9.99", merchant: "Amazon Prime", amount: Decimal(string: "-9.99")!, day: 27),
        ]
        let items = CoreLogic.Recurring.detect(all, month: october, calendar: utc, pins: pins)
        XCTAssertEqual(items.map(\.merchant), ["Google One", "Amazon Prime"])
        XCTAssertEqual(items.map(\.expectedDay), [20, 27])
        XCTAssertEqual(items[0].seenMonths, 3)
        XCTAssertEqual(items[1].amount, Decimal(string: "-9.99"))
        XCTAssertNil(items[1].bookedAt)
    }
}
