import Foundation
import SwiftData
import CoreModel
import CoreLogic
import CoreSync

// A quick-add captured by the App Intent. The intent runs in a background app launch where
// the sync engine isn't started, so it can't safely write SwiftData (a stray context wouldn't
// be observed for CloudKit push). Instead it appends here; the foreground app drains the queue
// through mainContext → SaveObserver → normal push. Amount is stored as a string to keep the
// Decimal exact (never round-trips through Double).
struct PendingQuickAdd: Codable {
    var accountId: String
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
    // Called on cold launch (after start()) and on every foreground resume — draining the
    // queue is atomic, so a double-fire just finds it empty. Enqueues created rows on the
    // sync engine directly so the push doesn't depend on SaveObserver timing.
    @MainActor
    static func run(_ ctx: ModelContext, engine: CloudKitSyncEngine?) {
        let pending = QuickAddQueue.drainRaw()
        guard !pending.isEmpty else { return }
        var created: [Transaction] = []
        var requeue: [PendingQuickAdd] = []
        for entry in pending {
            // Route strictly by the account UUID chosen in the shortcut. If it can't be resolved
            // yet (e.g. not synced to this device), re-queue rather than misroute or drop.
            guard let accountId = UUID(uuidString: entry.accountId),
                  let account = account(by: accountId, in: ctx) else {
                requeue.append(entry)
                continue
            }
            guard let amount = QuickAddQueue.parseAmount(entry.amount),
                  let tx = try? CoreLogic.Transactions.createManual(
                    account: account, amount: amount, bookedAt: entry.bookedAt,
                    description: entry.merchant, counterparty: entry.merchant, in: ctx)
            else { continue }
            _ = try? CoreLogic.Categorize.applyRulesToTransactions(in: ctx, txIds: [tx.id])
            created.append(tx)
        }
        requeue.forEach(QuickAddQueue.append)
        engine?.enqueueLocalChanges(inserted: created, updated: [], deleted: [])
    }

    @MainActor
    private static func account(by id: UUID, in ctx: ModelContext) -> Account? {
        (try? ctx.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })))?.first
    }
}
