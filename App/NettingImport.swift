#if DEBUG
import Foundation
import SwiftData
import CoreModel
import CoreLogic

// One-shot, gated on OFNET=1: applies user-approved nettings from Documents/net.json.
//   {"matches":[{"label":"…","primary":"<tx uuid>","reimbursements":["<tx uuid>"]}],
//    "creditMatches":[{"label":"…","credit":"<tx uuid>","expenses":["<tx uuid>"]}],
//    "pairs":[["<tx uuid>","<tx uuid>"]],
//    "categorize":[{"tx":"<tx uuid>","category":"Other Income"}]}
// matches → shared-expense groups (an expense netted by the Bizums that repaid it);
// pairs → manual transfer pairs (an own-money move the detector missed). Idempotent: a row
// already in a group / pair makes CoreLogic throw, which is logged and skipped.
enum NettingImport {
    struct Match: Decodable { let label: String; let primary: String; let reimbursements: [String] }
    struct CreditMatch: Decodable { let label: String; let credit: String; let expenses: [String] }
    struct Categorize: Decodable { let tx: String; let category: String }
    struct Payload: Decodable { let matches: [Match]?; let creditMatches: [CreditMatch]?; let pairs: [[String]]?; let categorize: [Categorize]? }

    @MainActor
    static func runIfRequested(_ container: ModelContainer) {
        guard ProcessInfo.processInfo.environment["OFNET"] == "1" else { return }
        guard let docs = try? FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false),
              case let url = docs.appendingPathComponent("net.json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            print("[Netting] no Documents/net.json — nothing to do"); return
        }
        let ctx = container.mainContext
        var done = 0
        for m in payload.matches ?? [] {
            guard let primary = UUID(uuidString: m.primary) else { continue }
            let reimbursements = m.reimbursements.compactMap(UUID.init(uuidString:))
            do {
                _ = try CoreLogic.SharedExpenses.createGroup(
                    .init(label: m.label, primaryTxId: primary, reimbursementTxIds: reimbursements), in: ctx)
                done += 1
            } catch { print("[Netting] match \(m.label) failed: \(error)") }
        }
        for m in payload.creditMatches ?? [] {
            guard let credit = UUID(uuidString: m.credit) else { continue }
            do {
                _ = try CoreLogic.SharedExpenses.createGroupFromCredit(
                    .init(label: m.label, creditTxId: credit,
                          expenseTxIds: m.expenses.compactMap(UUID.init(uuidString:))), in: ctx)
                done += 1
            } catch { print("[Netting] credit match \(m.label) failed: \(error)") }
        }
        for pair in payload.pairs ?? [] {
            guard pair.count == 2, let a = UUID(uuidString: pair[0]), let b = UUID(uuidString: pair[1]),
                  let first = fetch(a, in: ctx), let second = fetch(b, in: ctx) else { continue }
            do { _ = try CoreLogic.Transfers.pairManual(first, second, in: ctx); done += 1 }
            catch { print("[Netting] pair \(pair) failed: \(error)") }
        }
        for c in payload.categorize ?? [] {
            let name = c.category
            guard let id = UUID(uuidString: c.tx), let tx = fetch(id, in: ctx),
                  let category = try? ctx.fetch(FetchDescriptor<CoreModel.Category>(
                    predicate: #Predicate { $0.name == name })).first else { print("[Netting] categorize \(c.tx) skipped"); continue }
            tx.category = category
            tx.categorySource = .manual
            tx.updatedAt = .now
            done += 1
        }
        try? ctx.save()
        print("[Netting] applied \(done)")
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    private static func fetch(_ id: UUID, in ctx: ModelContext) -> Transaction? {
        (try? ctx.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })))?.first
    }
}
#endif
