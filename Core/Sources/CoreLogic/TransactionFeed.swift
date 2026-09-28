import Foundation
import SwiftData
import CoreModel

extension CoreLogic {
    // The Transactions list, filtered, sorted and paged by the store. Loading every row and
    // filtering in memory touched each row's account and category, which on a few thousand
    // rows cost the better part of a second on every open, keystroke and save.
    public enum TransactionFeed {
        public enum CategoryFilter: Equatable, Sendable {
            case all
            case uncategorized
            case category(UUID)
        }

        public struct Filter: Equatable, Sendable {
            // Resolved by the caller from the space and the show-excluded toggle.
            public var accountIds: [UUID]
            public var includeTransfers: Bool
            public var category: CategoryFilter
            public var search: String

            public init(
                accountIds: [UUID], includeTransfers: Bool = false,
                category: CategoryFilter = .all, search: String = ""
            ) {
                self.accountIds = accountIds
                self.includeTransfers = includeTransfers
                self.category = category
                self.search = search
            }
        }

        // id last: rows can share bookedAt and createdAt, and offset paging needs a total order.
        public static let sort = [
            SortDescriptor(\Transaction.bookedAt, order: .reverse),
            SortDescriptor(\Transaction.createdAt, order: .reverse),
            SortDescriptor(\Transaction.id, order: .reverse),
        ]

        // Mirror legs never list: they are the other half of a routed transfer.
        public static func predicate(_ filter: Filter) -> Predicate<Transaction> {
            let ids = filter.accountIds
            let transfers = filter.includeTransfers
            let base = #Predicate<Transaction> { tx in
                tx.routedFromTx == nil
                    && (transfers || !tx.isTransfer)
                    && (tx.account.flatMap { ids.contains($0.id) } ?? false)
            }

            let category: Predicate<Transaction>
            switch filter.category {
            case .all:
                category = #Predicate { _ in true }
            case .uncategorized:
                category = #Predicate { $0.category == nil }
            case .category(let id):
                category = #Predicate { $0.category?.id == id }
            }

            let query = filter.search.trimmingCharacters(in: .whitespaces)
            let text: Predicate<Transaction> = query.isEmpty
                ? #Predicate { _ in true }
                : #Predicate { tx in
                    (tx.transactionDescription?.localizedStandardContains(query) ?? false)
                        || (tx.counterparty?.localizedStandardContains(query) ?? false)
                }

            return #Predicate { base.evaluate($0) && category.evaluate($0) && text.evaluate($0) }
        }

        @MainActor
        public static func page(
            _ filter: Filter, offset: Int, limit: Int, in ctx: ModelContext
        ) throws -> [Transaction] {
            guard !filter.accountIds.isEmpty, limit > 0 else { return [] }
            var d = FetchDescriptor<Transaction>(predicate: predicate(filter), sortBy: sort)
            d.fetchOffset = offset
            d.fetchLimit = limit
            return try ctx.fetch(d)
        }

        // Counted in SQL, without loading a row.
        @MainActor
        public static func count(_ filter: Filter, in ctx: ModelContext) throws -> Int {
            guard !filter.accountIds.isEmpty else { return 0 }
            return try ctx.fetchCount(FetchDescriptor<Transaction>(predicate: predicate(filter)))
        }

        // Net EUR of every match in [start, end), whether or not it's loaded yet. A month
        // header asks for its own month only; summing every match up front loaded the whole
        // table again on each open.
        @MainActor
        public static func netEur(
            _ filter: Filter, from start: Date? = nil, to end: Date? = nil, in ctx: ModelContext
        ) throws -> Decimal {
            guard !filter.accountIds.isEmpty else { return 0 }
            let matches = predicate(filter)
            let lower = start ?? .distantPast
            let upper = end ?? .distantFuture
            let window = #Predicate<Transaction> { $0.bookedAt >= lower && $0.bookedAt < upper }
            var d = FetchDescriptor<Transaction>(
                predicate: #Predicate { matches.evaluate($0) && window.evaluate($0) })
            d.propertiesToFetch = [\.amountEur]
            return try ctx.fetch(d).reduce(Decimal(0)) { $0 + ($1.amountEur ?? 0) }
        }

        @MainActor
        public static func monthNetEur(
            _ filter: Filter, month: Date, calendar: Calendar = .current, in ctx: ModelContext
        ) throws -> Decimal {
            guard let interval = calendar.dateInterval(of: .month, for: month) else { return 0 }
            return try netEur(filter, from: interval.start, to: interval.end, in: ctx)
        }

        public static func monthStart(_ date: Date, calendar: Calendar = .current) -> Date {
            calendar.dateInterval(of: .month, for: date)?.start ?? date
        }
    }
}
