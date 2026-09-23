import Foundation
import CoreModel

extension CoreLogic {
    // Subscriptions on a manual account, derived from history instead of a stored list:
    // same merchant + same amount, exactly once a month, in at least two of the last few
    // months. Tells the user what this month should contain and what hasn't been booked yet.
    // ponytail: derived, so a new subscription takes two months to appear and a cancelled
    // one lingers up to two months; add a stored RecurringPayment model (+ CoreSync plumbing)
    // if that ever matters.
    public enum Recurring {
        public struct Item: Identifiable, Equatable, Sendable {
            public var id: String { key }
            public let key: String
            public let merchant: String
            public let amount: Decimal
            public let expectedDay: Int
            public let seenMonths: Int
            public let bookedAt: Date?
        }

        // A subscription lands on the same day give or take a weekend; a bar that happens to
        // take the same €16 on the 31st and the 3rd is not one.
        public static let maxDaySpread = 5

        // The user's fix for a subscription the detector gets wrong (drifting history, or
        // not enough of it): booked on `day` every month regardless of the evidence.
        public struct Pin: Codable, Equatable, Sendable {
            public let accountId: UUID
            public let key: String
            public let merchant: String
            public let amount: Decimal
            public let day: Int
            public init(accountId: UUID, key: String, merchant: String, amount: Decimal, day: Int) {
                self.accountId = accountId
                self.key = key
                self.merchant = merchant
                self.amount = amount
                self.day = day
            }
        }

        public static func detect(
            _ transactions: [Transaction],
            month reference: Date = .now,
            calendar: Calendar = .current,
            lookbackMonths: Int = 4,
            minMonths: Int = 2,
            pins: [Pin] = []
        ) -> [Item] {
            let refMonth = monthIndex(reference, calendar)
            let windowStart = refMonth - lookbackMonths
            struct Occurrence { let tx: Transaction; let month: Int; let day: Int }
            var groups: [String: [Occurrence]] = [:]
            for tx in transactions {
                guard tx.routedFromTx == nil, !tx.isTransfer, tx.amount < 0,
                      let description = tx.transactionDescription else { continue }
                let merchant = normalize(description)
                guard !merchant.isEmpty else { continue }
                let month = monthIndex(tx.bookedAt, calendar)
                guard month >= windowStart, month <= refMonth else { continue }
                let key = "\(merchant)|\(tx.amount)"
                groups[key, default: []].append(Occurrence(
                    tx: tx, month: month, day: calendar.component(.day, from: tx.bookedAt)))
            }

            func bookedAt(_ key: String) -> Date? {
                groups[key]?.filter { $0.month == refMonth }.map(\.tx.bookedAt).max()
            }
            var items: [Item] = []
            for (key, occurrences) in groups {
                // An auto-booked row proves nothing; only rows the bank/statement produced
                // (or the user typed) count as evidence. Statement import rewrites a confirmed
                // auto row's id, which is exactly when it starts counting.
                let past = occurrences.filter { $0.month < refMonth && !$0.tx.externalId.hasPrefix(Automations.recurringPrefix) }
                let months = Set(past.map(\.month))
                guard months.count >= minMonths,
                      past.count == months.count,
                      let latest = months.max(), latest >= refMonth - 2 else { continue }
                let days = past.map(\.day).sorted()
                guard days.last! - days.first! <= maxDaySpread else { continue }
                let newest = past.max { $0.tx.bookedAt < $1.tx.bookedAt }!
                items.append(Item(
                    key: key,
                    merchant: newest.tx.transactionDescription ?? "",
                    amount: newest.tx.amount,
                    expectedDay: days[days.count / 2],
                    seenMonths: months.count,
                    bookedAt: bookedAt(key)))
            }
            for pin in pins {
                let day = min(max(pin.day, 1), 31)
                if let i = items.firstIndex(where: { $0.key == pin.key }) {
                    let item = items[i]
                    items[i] = Item(key: item.key, merchant: item.merchant, amount: item.amount,
                                    expectedDay: day, seenMonths: item.seenMonths, bookedAt: item.bookedAt)
                } else {
                    items.append(Item(key: pin.key, merchant: pin.merchant, amount: pin.amount,
                                      expectedDay: day, seenMonths: 0, bookedAt: bookedAt(pin.key)))
                }
            }
            return items.sorted {
                $0.expectedDay != $1.expectedDay ? $0.expectedDay < $1.expectedDay : $0.merchant < $1.merchant
            }
        }

        static func normalize(_ description: String) -> String {
            RevolutCSV.slug(description).replacingOccurrences(of: "-", with: " ")
        }

        private static func monthIndex(_ date: Date, _ calendar: Calendar) -> Int {
            let c = calendar.dateComponents([.year, .month], from: date)
            return (c.year ?? 0) * 12 + (c.month ?? 1) - 1
        }
    }
}
