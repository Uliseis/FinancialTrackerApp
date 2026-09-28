import Foundation
import SwiftData
import CoreModel

extension CoreLogic {
    // Ports lib/accounts.ts balance computation. Three shapes per account:
    //  - anchor set        ⇒ anchor + Σ(tx since anchorAt)
    //  - manual (no conn)  ⇒ manualOpeningBalance + Σ(all tx)
    //  - connected, no anchor ⇒ the bank-reported `balance`
    // EUR variants divide native amounts by the currency's latest rate (EUR ⇒ 1).
    public enum Accounts {
        public static func isManual(_ account: Account) -> Bool {
            account.connection == nil
        }

        public static func hasAnchor(_ account: Account) -> Bool {
            account.balanceAnchor != nil && account.balanceAnchorAt != nil
        }

        @MainActor
        public static func rateFor(_ currency: String, in ctx: ModelContext) throws -> Decimal {
            (try FX.getRate(date: .now, currency: currency, in: ctx)) ?? 1
        }

        @MainActor
        public static func computeEurBalances(
            _ rows: [Account], in ctx: ModelContext
        ) throws -> [UUID: Decimal] {
            let byAccount = transactionsByAccount(for: rows, in: ctx)
            var out: [UUID: Decimal] = [:]
            for a in rows {
                let rate = try rateFor(a.currency, in: ctx)
                guard rate != 0 else { out[a.id] = 0; continue }
                let txs = byAccount[a.id] ?? []
                if hasAnchor(a), let since = a.balanceAnchorAt {
                    let anchor = (a.balanceAnchor ?? 0) / rate
                    out[a.id] = anchor + sumEur(txs, since: since)
                } else if isManual(a) {
                    let opening = (a.manualOpeningBalance ?? 0) / rate
                    out[a.id] = opening + sumEur(txs, since: nil)
                } else {
                    out[a.id] = (a.balance ?? 0) / rate
                }
            }
            return out
        }

        // What an account is worth on screen. An investment account is valued, not ledgered:
        // its transactions are money moved in and out, so their sum is not what it holds. Uses
        // the Investments tab's figure so the two tabs can't disagree; the ledger stands in
        // until there's a reading.
        @MainActor
        public static func displayBalancesEur(
            _ rows: [Account], in ctx: ModelContext
        ) throws -> [UUID: Decimal] {
            var out = try computeEurBalances(rows, in: ctx)
            let invested = rows.filter { $0.group?.kind == .investment }
            guard !invested.isEmpty else { return out }
            for (id, metrics) in try Investments.loadMetrics(for: invested, in: ctx) {
                if let value = metrics.valueEur { out[id] = value }
            }
            return out
        }

        // Native-currency balances. Connected-no-anchor accounts with a nil bank balance
        // are omitted (parity with the TS `else if a.balance != null`).
        @MainActor
        public static func computeNativeBalances(
            _ rows: [Account], in ctx: ModelContext
        ) -> [UUID: Decimal] {
            let byAccount = transactionsByAccount(for: rows, in: ctx)
            var out: [UUID: Decimal] = [:]
            for a in rows {
                let txs = byAccount[a.id] ?? []
                if hasAnchor(a), let since = a.balanceAnchorAt {
                    out[a.id] = (a.balanceAnchor ?? 0) + sumNative(txs, since: since)
                } else if isManual(a) {
                    out[a.id] = (a.manualOpeningBalance ?? 0) + sumNative(txs, since: nil)
                } else if let balance = a.balance {
                    out[a.id] = balance
                }
            }
            return out
        }

        // MARK: - Helpers

        @MainActor
        private static func transactionsByAccount(
            for rows: [Account], in ctx: ModelContext
        ) -> [UUID: [Transaction]] {
            let ids = Set(rows.map { $0.id })
            let all = (try? ctx.fetch(FetchDescriptor<Transaction>())) ?? []
            var byAccount: [UUID: [Transaction]] = [:]
            for tx in all {
                guard let aid = tx.account?.id, ids.contains(aid) else { continue }
                byAccount[aid, default: []].append(tx)
            }
            return byAccount
        }

        private static func sumEur(_ txs: [Transaction], since: Date?) -> Decimal {
            txs.reduce(Decimal(0)) { acc, tx in
                if let since, tx.bookedAt < since { return acc }
                return acc + (tx.amountEur ?? 0)
            }
        }

        private static func sumNative(_ txs: [Transaction], since: Date?) -> Decimal {
            txs.reduce(Decimal(0)) { acc, tx in
                if let since, tx.bookedAt < since { return acc }
                return acc + tx.amount
            }
        }
    }
}
