#if DEBUG
import Foundation
import SwiftData
import CoreModel
import CoreLogic

// One-shot data load for the manual credit card, gated on OFCC_IMPORT=1 (set via devicectl
// on a single launch). Two optional inputs in Documents/, both deleted after a successful run:
//   statement.csv   — a Revolut statement, fed through the same StatementImport the UI uses
//   cc-import.json  — {"rules":[…],"transactions":[…],"valuations":[…]} (a bare row array
//                     still decodes). Rows carry pre-computed externalIds (e.g. screenshot
//                     rows as revolutshot:v1:…). Rule seeds are created first so everything
//                     inserted this run categorizes; then every still-uncategorized row on the
//                     account is re-run against the rules so older quick-adds catch up too.
// Inserts go through the main context so SaveObserver pushes to CloudKit. Idempotent.
enum CCStatementImport {
    struct RuleSeed: Decodable {
        let pattern: String
        let category: String
        let priority: Int?
    }

    struct ValuationSeed: Decodable {
        let accountId: String
        let marketValueEur: String
        let cashValueEur: String?
        let notes: String?
    }

    struct Payload: Decodable {
        let rules: [RuleSeed]?
        let transactions: [Row]
        let valuations: [ValuationSeed]?

        init(from decoder: Decoder) throws {
            if let bare = try? [Row](from: decoder) {
                rules = nil; transactions = bare; valuations = nil; return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            rules = try c.decodeIfPresent([RuleSeed].self, forKey: .rules)
            transactions = try c.decodeIfPresent([Row].self, forKey: .transactions) ?? []
            valuations = try c.decodeIfPresent([ValuationSeed].self, forKey: .valuations)
        }
        private enum CodingKeys: String, CodingKey { case rules, transactions, valuations }
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

    @MainActor
    static func runIfRequested(_ container: ModelContainer) {
        guard ProcessInfo.processInfo.environment["OFCC_IMPORT"] == "1" else { return }
        guard let docs = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return }
        let jsonURL = docs.appendingPathComponent("cc-import.json")
        let csvURL = docs.appendingPathComponent("statement.csv")
        let payload = (try? Data(contentsOf: jsonURL)).flatMap { try? JSONDecoder().decode(Payload.self, from: $0) }
        let csv = try? String(contentsOf: csvURL, encoding: .utf8)
        guard payload != nil || csv != nil else {
            print("[CCImport] nothing in Documents — nothing to do"); return
        }
        let ctx = container.mainContext
        let acctId = accountId
        guard let account = try? ctx.fetch(FetchDescriptor<Account>(
            predicate: #Predicate { $0.id == acctId })).first else {
            print("[CCImport] target account not found"); return
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        var seededRules = 0
        for seed in payload?.rules ?? [] {
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
        try? ctx.save()

        if let csv {
            do {
                let s = try CoreLogic.StatementImport.importRevolutCSV(csv, into: account, in: ctx)
                print("[CCImport] csv parsed=\(s.parsed) inserted=\(s.inserted) matched=\(s.matchedManual) dup=\(s.skippedDuplicate) transfers=\(s.skippedTransfers) categorized=\(s.categorized) errors=\(s.errors)")
                try? FileManager.default.removeItem(at: csvURL)
            } catch {
                print("[CCImport] csv failed: \(error)")
            }
        }

        var insertedIds: [UUID] = []
        var skipped = 0
        for r in payload?.transactions ?? [] {
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
                amountEur: amount,
                fxRateUsed: 1,
                direction: r.direction == "credit" ? .credit : .debit,
                description: r.description,
                counterparty: nil,
                categorySource: .bank)
            ctx.insert(tx)
            insertedIds.append(tx.id)
        }
        do { try ctx.save() } catch { print("[CCImport] save failed: \(error)"); return }

        var valuations = 0
        for v in payload?.valuations ?? [] {
            guard let id = UUID(uuidString: v.accountId), let value = Decimal(string: v.marketValueEur),
                  let target = try? ctx.fetch(FetchDescriptor<Account>(
                    predicate: #Predicate { $0.id == id })).first else {
                print("[CCImport] bad valuation \(v.accountId)"); continue
            }
            _ = try? CoreLogic.Investments.recordValuation(
                account: target, marketValueEur: value,
                cashValueEur: v.cashValueEur.flatMap { Decimal(string: $0) },
                notes: v.notes, in: ctx)
            valuations += 1
        }

        let uncategorized = (try? ctx.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.account?.id == acctId && $0.category == nil }))) ?? []
        let cats = (try? CoreLogic.Categorize.applyRulesToTransactions(
            in: ctx, txIds: uncategorized.map(\.id) + insertedIds))?.updated ?? 0
        try? ctx.save()
        print("[CCImport] rules=\(seededRules) inserted=\(insertedIds.count) skipped=\(skipped) valuations=\(valuations) categorized=\(cats)")
        if payload != nil { try? FileManager.default.removeItem(at: jsonURL) }
    }
}
#endif
