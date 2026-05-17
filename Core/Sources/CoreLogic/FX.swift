import Foundation
import SwiftData
import CoreModel

public struct EcbRate: Equatable, Sendable {
    public let date: Date
    public let currency: String
    public let rate: Decimal

    public init(date: Date, currency: String, rate: Decimal) {
        self.date = date
        self.currency = currency
        self.rate = rate
    }
}

public enum FxError: Error, Equatable {
    case fetchFailed(status: Int)
    case parseFailed
}

public enum FX {
    public static let ecb90DaysURL = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist-90d.xml")!
    public static let ecbFullURL = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist.xml")!

    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    public static func parseEcbXml(_ xml: String) -> [EcbRate] {
        let dayPattern = #"<Cube\s+time="([^"]+)">([\s\S]*?)</Cube>"#
        let ccyPattern = #"<Cube\s+currency="([^"]+)"\s+rate="([^"]+)"\s*/>"#
        guard
            let dayRegex = try? NSRegularExpression(pattern: dayPattern),
            let ccyRegex = try? NSRegularExpression(pattern: ccyPattern)
        else { return [] }

        var out: [EcbRate] = []
        let ns = xml as NSString
        let dayMatches = dayRegex.matches(in: xml, range: NSRange(location: 0, length: ns.length))
        for day in dayMatches {
            let dateStr = ns.substring(with: day.range(at: 1))
            guard let date = isoDayToDate(dateStr) else { continue }
            let inner = ns.substring(with: day.range(at: 2)) as NSString
            let ccyMatches = ccyRegex.matches(
                in: inner as String,
                range: NSRange(location: 0, length: inner.length)
            )
            for ccy in ccyMatches {
                let code = inner.substring(with: ccy.range(at: 1))
                let rateStr = inner.substring(with: ccy.range(at: 2))
                guard let rate = Decimal(string: rateStr) else { continue }
                out.append(EcbRate(date: date, currency: code, rate: rate))
            }
        }
        return out
    }

    public static func fetchEcb(
        _ url: URL,
        session: URLSession = .shared
    ) async throws -> [EcbRate] {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw FxError.fetchFailed(status: status) }
        guard let xml = String(data: data, encoding: .utf8) else { throw FxError.parseFailed }
        return parseEcbXml(xml)
    }

    @MainActor
    @discardableResult
    public static func ingest(_ rates: [EcbRate], in ctx: ModelContext) throws -> Int {
        if rates.isEmpty { return 0 }
        var inserted = 0
        for r in rates {
            let date = r.date
            let currency = r.currency
            let existing = try ctx.fetch(FetchDescriptor<FxRate>(
                predicate: #Predicate { $0.date == date && $0.currency == currency }
            ))
            if !existing.isEmpty { continue }
            ctx.insert(FxRate(date: r.date, currency: r.currency, rate: r.rate))
            inserted += 1
        }
        try ctx.save()
        return inserted
    }

    @MainActor
    public static func getRate(
        date: Date,
        currency: String,
        in ctx: ModelContext
    ) throws -> Decimal? {
        let ccy = currency.uppercased()
        if ccy == "EUR" { return 1 }
        let day = startOfUTCDay(date)

        var exact = FetchDescriptor<FxRate>(
            predicate: #Predicate { $0.currency == ccy && $0.date == day }
        )
        exact.fetchLimit = 1
        if let hit = try ctx.fetch(exact).first { return hit.rate }

        var prior = FetchDescriptor<FxRate>(
            predicate: #Predicate { $0.currency == ccy && $0.date <= day },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        prior.fetchLimit = 1
        if let hit = try ctx.fetch(prior).first { return hit.rate }

        return nil
    }

    @MainActor
    public static func toEur(
        amount: Decimal,
        currency: String,
        date: Date,
        in ctx: ModelContext
    ) throws -> (amountEur: Decimal, rate: Decimal)? {
        guard let rate = try getRate(date: date, currency: currency, in: ctx) else { return nil }
        guard rate != 0 else { return nil }
        return (amount / rate, rate)
    }

    @MainActor
    public struct BackfillResult: Equatable {
        public var updated: Int
        public var skipped: Int
    }

    @MainActor
    @discardableResult
    public static func backfillTransactionEurAmounts(
        in ctx: ModelContext,
        limit: Int = 10_000,
        sinceDays: Int? = nil,
        txIds: [UUID]? = nil
    ) throws -> BackfillResult {
        var descriptor: FetchDescriptor<Transaction>
        if let ids = txIds, !ids.isEmpty {
            let idSet = Set(ids)
            descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.amountEur == nil && idSet.contains($0.id) }
            )
        } else if let sinceDays {
            let cutoff = Date().addingTimeInterval(-Double(sinceDays) * 86_400)
            descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.amountEur == nil && $0.bookedAt >= cutoff }
            )
        } else {
            descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.amountEur == nil }
            )
        }
        descriptor.fetchLimit = limit

        let rows = try ctx.fetch(descriptor)
        var result = BackfillResult(updated: 0, skipped: 0)
        for tx in rows {
            guard
                let conv = try toEur(amount: tx.amount, currency: tx.currency, date: tx.bookedAt, in: ctx)
            else {
                result.skipped += 1
                continue
            }
            tx.amountEur = roundEur(conv.amountEur)
            tx.fxRateUsed = conv.rate
            result.updated += 1
        }
        if result.updated > 0 { try ctx.save() }
        return result
    }

    public static func startOfUTCDay(_ date: Date) -> Date {
        utcCalendar.startOfDay(for: date)
    }

    public static func isoDayToDate(_ s: String) -> Date? {
        let parts = s.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2]) else { return nil }
        return utcCalendar.date(from: DateComponents(year: y, month: m, day: d))
    }

    private static func roundEur(_ value: Decimal) -> Decimal {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 2, .bankers)
        return rounded
    }
}
