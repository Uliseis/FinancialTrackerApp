import XCTest
@testable import CoreLogic

final class ChartAxisTests: XCTestCase {
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // The real valuation history: one reading in May, then a cluster from July on. Picking by
    // index put two of four ticks a fortnight apart and their labels overran each other.
    func testClusteredDatesSpreadEvenlyInTime() {
        var dates = [day(2026, 5, 14)]
        for d in stride(from: 1, through: 31, by: 3) { dates.append(day(2026, 7, d)) }
        for d in stride(from: 1, through: 31, by: 3) { dates.append(day(2026, 8, d)) }
        dates += [day(2026, 9, 10), day(2026, 9, 28)]

        let ticks = CoreLogic.ChartAxis.ticks(dates, count: 4)

        XCTAssertEqual(ticks.first, day(2026, 5, 14))
        XCTAssertEqual(ticks.last, day(2026, 9, 28))
        let slot = day(2026, 9, 28).timeIntervalSince(day(2026, 5, 14)) / 3
        for (a, b) in zip(ticks, ticks.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.timeIntervalSince(a), slot / 2)
        }
        XCTAssertTrue(ticks.allSatisfy(dates.contains))
    }

    func testEvenlySpacedDatesKeepEveryTarget() {
        let dates = [day(2026, 1, 1), day(2026, 2, 1), day(2026, 3, 1), day(2026, 4, 1)]
        XCTAssertEqual(CoreLogic.ChartAxis.ticks(dates, count: 4), dates)
    }

    func testDegenerateInputs() {
        XCTAssertEqual(CoreLogic.ChartAxis.ticks([], count: 4), [])
        XCTAssertEqual(CoreLogic.ChartAxis.ticks([day(2026, 5, 14)], count: 4), [day(2026, 5, 14)])
        let same = [day(2026, 5, 14), day(2026, 5, 14)]
        XCTAssertEqual(CoreLogic.ChartAxis.ticks(same, count: 4), [day(2026, 5, 14)])
    }

    func testUnsortedInputIsHandled() {
        let dates = [day(2026, 4, 1), day(2026, 1, 1), day(2026, 3, 1), day(2026, 2, 1)]
        XCTAssertEqual(CoreLogic.ChartAxis.ticks(dates, count: 4), dates.sorted())
    }
}
