import Foundation
import SwiftData
import CoreModel
import CoreLogic

// A quick-add captured by the App Intent. The intent runs in a background app launch where
// the sync engine isn't started, so it can't safely write SwiftData (a stray context wouldn't
// be observed for CloudKit push). Instead it appends here; the foreground app drains the queue
// through mainContext → SaveObserver → normal push. Amount is stored as a string to keep the
// Decimal exact (never round-trips through Double).
struct PendingQuickAdd: Codable {
    var amount: String
    var merchant: String?
    var bookedAt: Date
}

enum QuickAddQueue {
    private static let key = "quickAddQueue.v1"

    static func append(_ entry: PendingQuickAdd) {
        var q = load()
        q.append(entry)
        save(q)
    }

    // Returns and clears the queue.
    static func drainRaw() -> [PendingQuickAdd] {
        let q = load()
        UserDefaults.standard.removeObject(forKey: key)
        return q
    }

    private static func load() -> [PendingQuickAdd] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let q = try? JSONDecoder().decode([PendingQuickAdd].self, from: data)
        else { return [] }
        return q
    }

    private static func save(_ q: [PendingQuickAdd]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(q), forKey: key)
    }

    // Parses "14.20" or the EU "14,20". Returns nil for junk / non-positive.
    static func parseAmount(_ raw: String) -> Decimal? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.contains(",") && !s.contains(".") { s = s.replacingOccurrences(of: ",", with: ".") }
        s.removeAll { $0 == " " || $0 == "€" || $0 == "$" }
        guard let d = Decimal(string: s), d > 0 else { return nil }
        return d
    }
}

enum QuickAddDrain {
    // Materializes queued quick-adds into real transactions on the observed main context.
    // Must be called AFTER syncEngine.start() so the SaveObserver pushes them.
    @MainActor
    static func run(_ ctx: ModelContext) {
        let pending = QuickAddQueue.drainRaw()
        guard !pending.isEmpty else { return }
        guard let account = targetAccount(in: ctx) else {
            // No destination account yet — re-queue rather than drop the data.
            pending.forEach(QuickAddQueue.append)
            return
        }
        for entry in pending {
            guard let amount = QuickAddQueue.parseAmount(entry.amount) else { continue }
            guard let tx = try? CoreLogic.Transactions.createManual(
                account: account, amount: amount, bookedAt: entry.bookedAt,
                description: entry.merchant, counterparty: entry.merchant, in: ctx)
            else { continue }
            _ = try? CoreLogic.Categorize.applyRulesToTransactions(in: ctx, txIds: [tx.id])
        }
    }

    // ponytail: matches the Revolut credit-card account by name. If you rename it, update the
    // match here — or add a Settings picker that stores the target account's UUID.
    @MainActor
    private static func targetAccount(in ctx: ModelContext) -> Account? {
        let accounts = (try? ctx.fetch(FetchDescriptor<Account>())) ?? []
        let manual = accounts.filter { $0.connection == nil && !$0.archived }
        func matches(_ a: Account) -> Bool {
            let hay = "\(a.name) \(a.institution)".lowercased()
            return hay.contains("revolut") && (hay.contains("cred") || hay.contains("card"))
        }
        return manual.first(where: matches)
            ?? manual.first { "\($0.name) \($0.institution)".lowercased().contains("revolut") }
    }
}
