#if DEBUG
import Foundation
import SwiftData
import CoreModel
import CoreLogic

// One-shot balance-integrity fix, gated on OFCC_FIX=1. Idempotent — safe to re-run.
// (1) Repoints the mis-configured "EUR → Revolut X" route from Credit Card to Revolut X.
// (2) Deletes any leftover EUR→Revolut X mirror legs orphaned on the Credit Card and
//     re-mirrors their un-linked source debits onto Revolut X via the corrected route.
// (3) Adds the €7 Uber refund (05-24) skipped during import.
enum CCBalanceFix {
    static let revolutXId = UUID(uuidString: "89CE10F0-9953-432D-84BD-87AEF9ED17F8")!
    static let creditCardId = UUID(uuidString: "038A3B64-DBA8-4BB3-923D-DB1B29AC1384")!
    static let pattern = "EUR → Revolut X"

    @MainActor
    static func runIfRequested(_ container: ModelContainer) {
        guard ProcessInfo.processInfo.environment["OFCC_FIX"] == "1" else { return }
        let ctx = container.mainContext
        let rxId = revolutXId, ccId = creditCardId, pat = pattern

        let route = (try? ctx.fetch(FetchDescriptor<TransferRoute>(
            predicate: #Predicate { $0.pattern == pat })))?.first
        let rx = (try? ctx.fetch(FetchDescriptor<Account>(
            predicate: #Predicate { $0.id == rxId })))?.first
        guard let route, let rx else {
            print("[CCFix] route or Revolut X account not found"); return
        }

        // 1) Repoint the route to Revolut X (skip if already correct).
        if route.targetAccount?.id != rxId {
            _ = try? CoreLogic.TransferRoutes.updateRoute(
                route, pattern: route.pattern, target: rx, source: route.sourceAccount,
                field: route.field, matchType: route.matchType, direction: route.direction,
                enabled: route.enabled, in: ctx)
        }

        // 2) Delete EUR→Revolut X mirror legs still on the Credit Card (orphans).
        let ccLegs = (try? ctx.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.account?.id == ccId && $0.transactionDescription == pat }))) ?? []
        for m in ccLegs { ctx.delete(m) }

        // 3) Reset EUR→Revolut X debit primaries that have no linked mirror, then re-apply.
        let named = (try? ctx.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.transactionDescription == pat }))) ?? []
        var reset = 0
        for p in named where p.direction == .debit && p.mirrors.isEmpty {
            p.isTransfer = false; p.transferGroup = nil; reset += 1
        }
        try? ctx.save()
        let made = (try? CoreLogic.TransferRoutes.apply(in: ctx, sinceDays: 730, routeId: route.id))?.mirroredCreated ?? 0
        print("[CCFix] ccOrphansDeleted=\(ccLegs.count) primariesReset=\(reset) mirrorsCreated=\(made)")

        // 4) €7 Uber refund (idempotent via externalId).
        let eid = "revolutcsv:v1:2026-05-24:7.00:uber:0"
        let exists = ((try? ctx.fetchCount(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.externalId == eid }))) ?? 0) > 0
        if !exists, let cc = try? ctx.fetch(FetchDescriptor<Account>(
                predicate: #Predicate { $0.id == ccId })).first {
            let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
            ctx.insert(Transaction(
                account: cc, externalId: eid,
                bookedAt: iso.date(from: "2026-05-24T00:00:00+00:00")!,
                valueAt: iso.date(from: "2026-05-24T13:30:30+00:00"),
                amount: Decimal(string: "7.00")!, currency: "EUR",
                amountEur: Decimal(string: "7.00")!, fxRateUsed: 1,
                direction: .credit, description: "Uber", counterparty: nil, categorySource: .bank))
            print("[CCFix] added €7 Uber refund")
        }
        try? ctx.save()
    }
}
#endif
