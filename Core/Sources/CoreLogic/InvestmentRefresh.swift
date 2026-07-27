import Foundation
import SwiftData
import CoreModel
import CoreIntegrations

extension CoreLogic {
    // Pulls today's market value for every investment account that has a live source and
    // records it as that day's snapshot. Accounts without a source keep their typed snapshot;
    // contributions since it are added by Investments.computeAccountMetrics, so a stale
    // snapshot is only ever wrong by market movement, never by money paid in.
    public enum InvestmentRefresh {
        public struct Outcome: Equatable, Sendable {
            public var updated: [UUID] = []
            public var failures: [String] = []
        }

        public static let cryptoPrefix = "crypto:"
        public static let trading212Source = "t212"

        // A mistyped holding quantity produces a plausible-looking number that is wrong by
        // orders of magnitude (0,06033031 BTC read as 6033031 wrote a €345bn valuation).
        // Automatic writes are refused past this factor; typing a value by hand is not
        // guarded, because typing it IS the confirmation.
        public static let implausibleFactor: Decimal = 100

        public static func isImplausible(_ candidate: Decimal, previous: Decimal?) -> Bool {
            guard let previous, previous > 0, candidate > 0 else { return false }
            return candidate > previous * implausibleFactor
                || candidate * implausibleFactor < previous
        }

        public static func coinId(from source: String?) -> String? {
            guard let source, source.hasPrefix(cryptoPrefix) else { return nil }
            let id = String(source.dropFirst(cryptoPrefix.count))
            return id.isEmpty ? nil : id
        }

        @MainActor
        public static func liveValuedAccounts(in ctx: ModelContext) throws -> [Account] {
            try ctx.fetch(FetchDescriptor<Account>(
                predicate: #Predicate { $0.archived == false && $0.liveValueSource != nil }
            ))
        }

        @MainActor
        @discardableResult
        public static func run(
            in ctx: ModelContext,
            keychain: MarketKeychain = MarketKeychain(),
            crypto: any CryptoPriceSource = CryptoPriceClient(),
            now: Date = .now
        ) async -> Outcome {
            var outcome = Outcome()
            guard let accounts = try? liveValuedAccounts(in: ctx), !accounts.isEmpty else {
                return outcome
            }

            // One request for every coin held, not one per account.
            let coinIds = Array(Set(accounts.compactMap { coinId(from: $0.liveValueSource) }))
            var prices: [String: Decimal] = [:]
            if !coinIds.isEmpty {
                do { prices = try await crypto.prices(for: coinIds) }
                catch { outcome.failures.append("Crypto prices: \(error)") }
            }

            var t212: Trading212Summary?
            if accounts.contains(where: { $0.liveValueSource == trading212Source }) {
                do {
                    let creds = try keychain.loadTrading212()
                    t212 = try await Trading212Client(credentials: creds).accountSummary()
                } catch {
                    outcome.failures.append("Trading 212: \(error)")
                }
            }

            for account in accounts {
                guard let source = account.liveValueSource else { continue }
                var market: Decimal?
                var cash: Decimal?

                if source == trading212Source, let t212 {
                    market = t212.totalValueEur
                    cash = t212.cashEur
                } else if let coin = coinId(from: source), let price = prices[coin] {
                    guard let qty = account.assetQuantity else {
                        outcome.failures.append("\(account.displayName): no quantity set")
                        continue
                    }
                    market = qty * price
                }

                guard let market, market > 0 else { continue }

                // Compare against the newest reading that wasn't itself written today, so a
                // bad value recorded an hour ago can still be corrected by a good one.
                let previous = (try? Investments.listValuations(for: [account.id], in: ctx))?
                    .last(where: { Calendar.current.compare($0.asOf, to: now, toGranularity: .day) != .orderedSame })?
                    .marketValueEur
                if isImplausible(market, previous: previous) {
                    outcome.failures.append(
                        "\(account.displayName): \(Self.plain(market)) is far from the last "
                        + "reading (\(Self.plain(previous ?? 0))). Check the quantity; not saved.")
                    continue
                }

                do {
                    try Investments.recordValuation(
                        account: account, marketValueEur: market, cashValueEur: cash,
                        asOf: now, notes: "auto: \(source)", in: ctx, now: now)
                    outcome.updated.append(account.id)
                } catch {
                    outcome.failures.append("\(account.displayName): \(error)")
                }
            }
            return outcome
        }

        // No currency formatter in Core; the message only needs to be readable.
        private static func plain(_ value: Decimal) -> String {
            var rounded = Decimal()
            var input = value
            NSDecimalRound(&rounded, &input, 2, .plain)
            return "\(rounded) EUR"
        }
    }
}
