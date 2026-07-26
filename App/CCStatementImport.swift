#if DEBUG
import Foundation
import SwiftData
import CoreModel
import CoreLogic

// One-shot Revolut-CSV statement import, gated on OFCC_IMPORT=1 (set via devicectl on a
// single launch). Reads pre-computed rows (externalId/dates/amount already in the exact
// web `revolutcsv:v1` scheme) from Documents/cc-import.json, inserts through the main
// context so SaveObserver pushes to CloudKit, then runs category rules. Idempotent:
// dedup on (account, externalId); the JSON is deleted after a successful run.
enum CCStatementImport {
    // Optional rule seeds, applied before the inserted rows are categorized. Lets an
    // import bring merchants the rule engine has never seen (Bolt, Zalando…) without a
    // second deploy — and they keep working for future charges.
    struct RuleSeed: Decodable {
        let pattern: String
        let category: String
        let priority: Int?
    }

    // Backward compatible: a bare [Row] array still decodes, as do the older payloads.
    struct Payload: Decodable {
        let rules: [RuleSeed]?
        let transactions: [Row]

        init(from decoder: Decoder) throws {
            if let bare = try? [Row](from: decoder) {
                rules = nil; transactions = bare; return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            rules = try c.decodeIfPresent([RuleSeed].self, forKey: .rules)
            transactions = try c.decode([Row].self, forKey: .transactions)
        }
        private enum CodingKeys: String, CodingKey { case rules, transactions }
    }

    struct Row: Decodable {
        let externalId: String
        let bookedAt: String
        let valueAt: String?
        let amount: String
        let currency: String
        let direction: String
        let description: String?
    }

    static let accountId = UUID(uuidString: "038A3B64-DBA8-4BB3-923D-DB1B29AC1384")!
    // The manual "Card Fee (rent)" row: statement fee was €35.40, logged as €35.00.
    static let feeFixExternalId = "manual:f17b5a72-b898-46ae-9b6d-083e358ce887"

    @MainActor
    static func runIfRequested(_ container: ModelContainer) {
        guard ProcessInfo.processInfo.environment["OFCC_IMPORT"] == "1" else { return }
        guard let docs = try? FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false),
              case let url = docs.appendingPathComponent("cc-import.json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            print("[CCImport] no Documents/cc-import.json — nothing to do"); return
        }
        let rows = payload.transactions
        let ctx = container.mainContext
        let acctId = accountId
        guard let account = try? ctx.fetch(FetchDescriptor<Account>(
            predicate: #Predicate { $0.id == acctId })).first else {
            print("[CCImport] target account not found"); return
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        // Seed rules first so the inserted rows categorize on this same run. Skips any
        // pattern that already exists, so a replayed import doesn't stack duplicates.
        var seededRules = 0
        for seed in payload.rules ?? [] {
            let pattern = seed.pattern
            let already = ((try? ctx.fetchCount(FetchDescriptor<CategoryRule>(
                predicate: #Predicate { $0.pattern == pattern }))) ?? 0) > 0
            if already { continue }
            let name = seed.category
            guard let category = try? ctx.fetch(FetchDescriptor<CoreModel.Category>(
                predicate: #Predicate { $0.name == name })).first else {
                print("[CCImport] no category named \(name) for rule \(pattern)"); continue
            }
            _ = try? CoreLogic.CategoryRules.create(
                pattern: pattern, category: category,
                priority: seed.priority ?? -1000, in: ctx)
            seededRules += 1
        }

        var insertedIds: [UUID] = []
        var skipped = 0
        for r in rows {
            let eid = r.externalId
            let exists = ((try? ctx.fetchCount(FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.account?.id == acctId && $0.externalId == eid }))) ?? 0) > 0
            if exists { skipped += 1; continue }
            guard let booked = iso.date(from: r.bookedAt), let amount = Decimal(string: r.amount) else {
                print("[CCImport] bad row \(eid)"); continue
            }
            let tx = Transaction(
                account: account,
                externalId: eid,
                bookedAt: booked,
                valueAt: r.valueAt.flatMap { iso.date(from: $0) },
                amount: amount,
                currency: r.currency,
                amountEur: amount,              // EUR account ⇒ EUR identity, no FX needed
                fxRateUsed: 1,
                direction: r.direction == "credit" ? .credit : .debit,
                description: r.description,
                counterparty: nil,
                categorySource: .bank)
            ctx.insert(tx)
            insertedIds.append(tx.id)
        }

        // €35.00 → €35.40 fee correction.
        let feeEid = feeFixExternalId
        if let fee = try? ctx.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.externalId == feeEid })).first {
            fee.amount = Decimal(string: "-35.40")!
            fee.amountEur = Decimal(string: "-35.40")!
            fee.updatedAt = .now
        }

        do { try ctx.save() } catch { print("[CCImport] save failed: \(error)"); return }
        let cats = (try? CoreLogic.Categorize.applyRulesToTransactions(in: ctx, txIds: insertedIds))?.updated ?? 0
        try? ctx.save()
        print("[CCImport] rules=\(seededRules) inserted=\(insertedIds.count) skipped=\(skipped) categorized=\(cats)")
        try? FileManager.default.removeItem(at: url)   // don't re-run
    }
}
#endif
