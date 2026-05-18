import XCTest
import SwiftData
@testable import CoreLogic
@testable import CoreModel

@MainActor
final class SharedExpensesTests: XCTestCase {
    typealias S = TransferTestSupport
    typealias SE = CoreLogic.SharedExpenses

    private func happyPathContext() throws -> (
        ctx: ModelContext,
        space: AccountSpace,
        accountA: Account,
        accountB: Account
    ) {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx)
        let a = S.makeAccount(ctx, name: "Joint", space: space)
        let b = S.makeAccount(ctx, name: "Roommate", space: space)
        return (ctx, space, a, b)
    }

    // MARK: - createGroup

    func testCreateGroupHappyPath() throws {
        let (ctx, _, joint, roommate) = try happyPathContext()
        let dinner = S.makeTx(
            ctx, account: joint, amount: 100, amountEur: 100, direction: .debit,
            bookedAt: Date(timeIntervalSince1970: 1_750_000_000),
            description: "Dinner"
        )
        let refund = S.makeTx(
            ctx, account: roommate, amount: 50, amountEur: 50, direction: .credit,
            bookedAt: Date(timeIntervalSince1970: 1_750_000_000 + 86_400),
            description: "split dinner"
        )
        try ctx.save()

        let group = try SE.createGroup(
            .init(label: "Dinner split", primaryTxId: dinner.id, reimbursementTxIds: [refund.id]),
            in: ctx
        )
        XCTAssertEqual(group.label, "Dinner split")
        XCTAssertEqual(group.primaryTx?.id, dinner.id)
        XCTAssertEqual(dinner.sharedExpenseGroup?.id, group.id, "Primary tx must also be a member")
        XCTAssertEqual(refund.sharedExpenseGroup?.id, group.id)
    }

    func testCreateGroupTrimsAndRejectsEmptyLabel() throws {
        let (ctx, _, joint, roommate) = try happyPathContext()
        let p = S.makeTx(ctx, account: joint, amount: 100, amountEur: 100, direction: .debit)
        let r = S.makeTx(ctx, account: roommate, amount: 50, amountEur: 50, direction: .credit)
        try ctx.save()

        XCTAssertThrowsError(
            try SE.createGroup(.init(label: "   ", primaryTxId: p.id, reimbursementTxIds: [r.id]), in: ctx)
        ) { error in
            XCTAssertEqual(error as? SE.Error, .labelRequired)
        }
    }

    func testCreateGroupRejectsEmptyReimbursements() throws {
        let (ctx, _, joint, _) = try happyPathContext()
        let p = S.makeTx(ctx, account: joint, amount: 100, amountEur: 100, direction: .debit)
        try ctx.save()
        XCTAssertThrowsError(
            try SE.createGroup(.init(label: "Dinner", primaryTxId: p.id, reimbursementTxIds: []), in: ctx)
        ) { error in
            XCTAssertEqual(error as? SE.Error, .noReimbursements)
        }
    }

    func testCreateGroupRejectsPrimaryAlsoInReimbursementList() throws {
        let (ctx, _, joint, _) = try happyPathContext()
        let p = S.makeTx(ctx, account: joint, amount: 100, amountEur: 100, direction: .debit)
        try ctx.save()
        XCTAssertThrowsError(
            try SE.createGroup(.init(label: "X", primaryTxId: p.id, reimbursementTxIds: [p.id]), in: ctx)
        ) { error in
            XCTAssertEqual(error as? SE.Error, .primaryIsAlsoReimbursement)
        }
    }

    func testCreateGroupRejectsCreditPrimary() throws {
        let (ctx, _, joint, roommate) = try happyPathContext()
        let p = S.makeTx(ctx, account: joint, amount: 100, amountEur: 100, direction: .credit)
        let r = S.makeTx(ctx, account: roommate, amount: 50, amountEur: 50, direction: .credit)
        try ctx.save()
        XCTAssertThrowsError(
            try SE.createGroup(.init(label: "X", primaryTxId: p.id, reimbursementTxIds: [r.id]), in: ctx)
        ) { error in
            XCTAssertEqual(error as? SE.Error, .primaryMustBeDebit)
        }
    }

    func testCreateGroupRejectsTransferPrimary() throws {
        let (ctx, _, joint, roommate) = try happyPathContext()
        let p = S.makeTx(
            ctx, account: joint, amount: 100, amountEur: 100, direction: .debit, isTransfer: true
        )
        let r = S.makeTx(ctx, account: roommate, amount: 50, amountEur: 50, direction: .credit)
        try ctx.save()
        XCTAssertThrowsError(
            try SE.createGroup(.init(label: "X", primaryTxId: p.id, reimbursementTxIds: [r.id]), in: ctx)
        ) { error in
            XCTAssertEqual(error as? SE.Error, .primaryIsTransfer)
        }
    }

    func testCreateGroupRejectsPrimaryAlreadyInGroup() throws {
        let (ctx, _, joint, roommate) = try happyPathContext()
        let existing = SharedExpenseGroup(label: "old", attributionMonth: .now)
        ctx.insert(existing)
        let p = S.makeTx(
            ctx, account: joint, amount: 100, amountEur: 100, direction: .debit,
            sharedExpenseGroup: existing
        )
        let r = S.makeTx(ctx, account: roommate, amount: 50, amountEur: 50, direction: .credit)
        try ctx.save()
        XCTAssertThrowsError(
            try SE.createGroup(.init(label: "X", primaryTxId: p.id, reimbursementTxIds: [r.id]), in: ctx)
        ) { error in
            XCTAssertEqual(error as? SE.Error, .primaryAlreadyInGroup)
        }
    }

    func testCreateGroupRejectsPrimaryWithoutEur() throws {
        let (ctx, _, joint, roommate) = try happyPathContext()
        let p = S.makeTx(
            ctx, account: joint, amount: 100, currency: "USD", amountEur: nil, direction: .debit
        )
        let r = S.makeTx(ctx, account: roommate, amount: 50, amountEur: 50, direction: .credit)
        try ctx.save()
        XCTAssertThrowsError(
            try SE.createGroup(.init(label: "X", primaryTxId: p.id, reimbursementTxIds: [r.id]), in: ctx)
        ) { error in
            XCTAssertEqual(error as? SE.Error, .primaryHasNoEurAmount)
        }
    }

    func testCreateGroupRejectsDebitReimbursement() throws {
        let (ctx, _, joint, roommate) = try happyPathContext()
        let p = S.makeTx(ctx, account: joint, amount: 100, amountEur: 100, direction: .debit)
        let r = S.makeTx(ctx, account: roommate, amount: 50, amountEur: 50, direction: .debit)
        try ctx.save()
        XCTAssertThrowsError(
            try SE.createGroup(.init(label: "X", primaryTxId: p.id, reimbursementTxIds: [r.id]), in: ctx)
        ) { error in
            XCTAssertEqual(error as? SE.Error, .reimbursementNotCredit(txId: r.id))
        }
    }

    func testCreateGroupRejectsOvercoverage() throws {
        let (ctx, _, joint, roommate) = try happyPathContext()
        let p = S.makeTx(ctx, account: joint, amount: 100, amountEur: 100, direction: .debit)
        let r1 = S.makeTx(ctx, account: roommate, amount: 60, amountEur: 60, direction: .credit)
        let r2 = S.makeTx(ctx, account: roommate, amount: 60, amountEur: 60, direction: .credit)
        try ctx.save()
        XCTAssertThrowsError(
            try SE.createGroup(
                .init(label: "X", primaryTxId: p.id, reimbursementTxIds: [r1.id, r2.id]),
                in: ctx
            )
        ) { error in
            guard case .overcoverage(let total, let primary) = error as? SE.Error else {
                XCTFail("Expected .overcoverage, got \(error)")
                return
            }
            XCTAssertEqual(total, 120)
            XCTAssertEqual(primary, 100)
        }
    }

    func testCreateGroupRejectsOutsideWindow() throws {
        let (ctx, _, joint, roommate) = try happyPathContext()
        let t0 = Date(timeIntervalSince1970: 1_750_000_000)
        let p = S.makeTx(
            ctx, account: joint, amount: 100, amountEur: 100, direction: .debit, bookedAt: t0
        )
        // Reimbursement 70 days later (> 60-day window)
        let r = S.makeTx(
            ctx, account: roommate, amount: 50, amountEur: 50, direction: .credit,
            bookedAt: t0.addingTimeInterval(70 * 86_400)
        )
        try ctx.save()
        XCTAssertThrowsError(
            try SE.createGroup(.init(label: "X", primaryTxId: p.id, reimbursementTxIds: [r.id]), in: ctx)
        ) { error in
            XCTAssertEqual(
                error as? SE.Error,
                .reimbursementOutsideWindow(txId: r.id, windowDays: 60)
            )
        }
    }

    func testCreateGroupRejectsCrossSpace() throws {
        let ctx = try S.makeContext()
        let s1 = S.makeSpace(ctx, name: "Personal")
        let s2 = S.makeSpace(ctx, name: "Joint")
        let a = S.makeAccount(ctx, name: "A", space: s1)
        let b = S.makeAccount(ctx, name: "B", space: s2)
        let p = S.makeTx(ctx, account: a, amount: 100, amountEur: 100, direction: .debit)
        let r = S.makeTx(ctx, account: b, amount: 50, amountEur: 50, direction: .credit)
        try ctx.save()
        XCTAssertThrowsError(
            try SE.createGroup(.init(label: "X", primaryTxId: p.id, reimbursementTxIds: [r.id]), in: ctx)
        ) { error in
            XCTAssertEqual(error as? SE.Error, .crossSpace(txId: r.id))
        }
    }

    func testCreateGroupAttributionMonthIsPrimaryMonthStart() throws {
        let (ctx, _, joint, roommate) = try happyPathContext()
        // 2026-03-15 14:30 UTC
        let mar15 = Date(timeIntervalSince1970: 1_773_323_400)
        let p = S.makeTx(ctx, account: joint, amount: 100, amountEur: 100, direction: .debit, bookedAt: mar15)
        let r = S.makeTx(ctx, account: roommate, amount: 50, amountEur: 50, direction: .credit, bookedAt: mar15)
        try ctx.save()

        let g = try SE.createGroup(
            .init(label: "X", primaryTxId: p.id, reimbursementTxIds: [r.id]), in: ctx
        )
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: g.attributionMonth)
        XCTAssertEqual(comps.day, 1)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
        XCTAssertEqual(comps.second, 0)
    }

    // MARK: - addReimbursements

    func testAddReimbursementsHappyPath() throws {
        let (ctx, _, joint, roommate) = try happyPathContext()
        let p = S.makeTx(ctx, account: joint, amount: 100, amountEur: 100, direction: .debit)
        let r1 = S.makeTx(ctx, account: roommate, amount: 30, amountEur: 30, direction: .credit)
        let r2 = S.makeTx(ctx, account: roommate, amount: 40, amountEur: 40, direction: .credit)
        try ctx.save()
        let g = try SE.createGroup(
            .init(label: "X", primaryTxId: p.id, reimbursementTxIds: [r1.id]), in: ctx
        )
        try SE.addReimbursements(groupId: g.id, txIds: [r2.id], in: ctx)
        XCTAssertEqual(r2.sharedExpenseGroup?.id, g.id)
    }

    func testAddReimbursementsRejectsOvercoverageWithExistingTotal() throws {
        let (ctx, _, joint, roommate) = try happyPathContext()
        let p = S.makeTx(ctx, account: joint, amount: 100, amountEur: 100, direction: .debit)
        let r1 = S.makeTx(ctx, account: roommate, amount: 80, amountEur: 80, direction: .credit)
        let r2 = S.makeTx(ctx, account: roommate, amount: 50, amountEur: 50, direction: .credit)
        try ctx.save()
        let g = try SE.createGroup(
            .init(label: "X", primaryTxId: p.id, reimbursementTxIds: [r1.id]), in: ctx
        )
        XCTAssertThrowsError(
            try SE.addReimbursements(groupId: g.id, txIds: [r2.id], in: ctx)
        ) { error in
            guard case .overcoverage = error as? SE.Error else {
                XCTFail("Expected .overcoverage, got \(error)")
                return
            }
        }
    }

    // MARK: - removeReimbursement

    func testRemoveReimbursementUnlinksMember() throws {
        let (ctx, _, joint, roommate) = try happyPathContext()
        let p = S.makeTx(ctx, account: joint, amount: 100, amountEur: 100, direction: .debit)
        let r = S.makeTx(ctx, account: roommate, amount: 50, amountEur: 50, direction: .credit)
        try ctx.save()
        let g = try SE.createGroup(
            .init(label: "X", primaryTxId: p.id, reimbursementTxIds: [r.id]), in: ctx
        )
        try SE.removeReimbursement(groupId: g.id, txId: r.id, in: ctx)
        XCTAssertNil(r.sharedExpenseGroup)
    }

    func testRemoveReimbursementRefusesPrimary() throws {
        let (ctx, _, joint, roommate) = try happyPathContext()
        let p = S.makeTx(ctx, account: joint, amount: 100, amountEur: 100, direction: .debit)
        let r = S.makeTx(ctx, account: roommate, amount: 50, amountEur: 50, direction: .credit)
        try ctx.save()
        let g = try SE.createGroup(
            .init(label: "X", primaryTxId: p.id, reimbursementTxIds: [r.id]), in: ctx
        )
        XCTAssertThrowsError(
            try SE.removeReimbursement(groupId: g.id, txId: p.id, in: ctx)
        ) { error in
            XCTAssertEqual(error as? SE.Error, .cannotRemovePrimary)
        }
    }

    // MARK: - deleteGroup

    func testDeleteGroupUnlinksAllAndRemovesGroup() throws {
        let (ctx, _, joint, roommate) = try happyPathContext()
        let p = S.makeTx(ctx, account: joint, amount: 100, amountEur: 100, direction: .debit)
        let r = S.makeTx(ctx, account: roommate, amount: 50, amountEur: 50, direction: .credit)
        try ctx.save()
        let g = try SE.createGroup(
            .init(label: "X", primaryTxId: p.id, reimbursementTxIds: [r.id]), in: ctx
        )
        let gid = g.persistentModelID
        try SE.deleteGroup(g, in: ctx)
        let groups = try ctx.fetch(FetchDescriptor<SharedExpenseGroup>())
        XCTAssertFalse(groups.contains { $0.persistentModelID == gid })
        XCTAssertNil(p.sharedExpenseGroup)
        XCTAssertNil(r.sharedExpenseGroup)
    }

    // MARK: - net summaries

    func testNetForGroupMath() throws {
        let (ctx, _, joint, roommate) = try happyPathContext()
        let p = S.makeTx(ctx, account: joint, amount: 100, amountEur: 100, direction: .debit)
        let r1 = S.makeTx(ctx, account: roommate, amount: 30, amountEur: 30, direction: .credit)
        let r2 = S.makeTx(ctx, account: roommate, amount: 40, amountEur: 40, direction: .credit)
        try ctx.save()
        let g = try SE.createGroup(
            .init(label: "X", primaryTxId: p.id, reimbursementTxIds: [r1.id, r2.id]), in: ctx
        )
        let net = try SE.netForGroup(g.id, in: ctx)
        XCTAssertEqual(net.gross, 100)
        XCTAssertEqual(net.reimbursed, 70)
        XCTAssertEqual(net.net, 30)
    }

    func testNetForGroupsBuildsBucketsPerId() throws {
        let (ctx, _, joint, roommate) = try happyPathContext()
        let p1 = S.makeTx(ctx, account: joint, amount: 100, amountEur: 100, direction: .debit)
        let p2 = S.makeTx(ctx, account: joint, amount: 200, amountEur: 200, direction: .debit)
        let r1 = S.makeTx(ctx, account: roommate, amount: 50, amountEur: 50, direction: .credit)
        let r2 = S.makeTx(ctx, account: roommate, amount: 80, amountEur: 80, direction: .credit)
        try ctx.save()
        let g1 = try SE.createGroup(.init(label: "A", primaryTxId: p1.id, reimbursementTxIds: [r1.id]), in: ctx)
        let g2 = try SE.createGroup(.init(label: "B", primaryTxId: p2.id, reimbursementTxIds: [r2.id]), in: ctx)

        let map = try SE.netForGroups([g1.id, g2.id], in: ctx)
        XCTAssertEqual(map[g1.id]?.gross, 100)
        XCTAssertEqual(map[g1.id]?.reimbursed, 50)
        XCTAssertEqual(map[g1.id]?.net, 50)
        XCTAssertEqual(map[g2.id]?.gross, 200)
        XCTAssertEqual(map[g2.id]?.reimbursed, 80)
        XCTAssertEqual(map[g2.id]?.net, 120)
    }

    // MARK: - candidate search

    func testFindCandidateReimbursementsRespectsWindowSpaceAndAccountFlags() throws {
        let ctx = try S.makeContext()
        let space = S.makeSpace(ctx, name: "Personal")
        let other = S.makeSpace(ctx, name: "Joint")
        let acc = S.makeAccount(ctx, name: "A", space: space)
        let archived = S.makeAccount(ctx, name: "Dead", space: space, archived: true)
        let crossSpace = S.makeAccount(ctx, name: "Cross", space: other)
        let t0 = Date(timeIntervalSince1970: 1_750_000_000)
        let primary = S.makeTx(ctx, account: acc, amount: 100, amountEur: 100, direction: .debit, bookedAt: t0)

        let good = S.makeTx(
            ctx, account: acc, amount: 30, amountEur: 30, direction: .credit,
            bookedAt: t0.addingTimeInterval(5 * 86_400), counterparty: "Anne refund"
        )
        let outOfWindow = S.makeTx(
            ctx, account: acc, amount: 30, amountEur: 30, direction: .credit,
            bookedAt: t0.addingTimeInterval(100 * 86_400)
        )
        let crossSpaceTx = S.makeTx(
            ctx, account: crossSpace, amount: 30, amountEur: 30, direction: .credit,
            bookedAt: t0.addingTimeInterval(1 * 86_400)
        )
        let archivedTx = S.makeTx(
            ctx, account: archived, amount: 30, amountEur: 30, direction: .credit,
            bookedAt: t0.addingTimeInterval(1 * 86_400)
        )
        let debitTx = S.makeTx(
            ctx, account: acc, amount: 30, amountEur: 30, direction: .debit,
            bookedAt: t0.addingTimeInterval(1 * 86_400)
        )
        try ctx.save()

        let results = try SE.findCandidateReimbursements(primaryTxId: primary.id, query: "", in: ctx)
        let ids = Set(results.map(\.id))
        XCTAssertTrue(ids.contains(good.id))
        XCTAssertFalse(ids.contains(outOfWindow.id))
        XCTAssertFalse(ids.contains(crossSpaceTx.id))
        XCTAssertFalse(ids.contains(archivedTx.id))
        XCTAssertFalse(ids.contains(debitTx.id))
    }

    func testFindCandidateReimbursementsTextSearch() throws {
        let (ctx, _, joint, roommate) = try happyPathContext()
        let t0 = Date(timeIntervalSince1970: 1_750_000_000)
        let primary = S.makeTx(ctx, account: joint, amount: 100, amountEur: 100, direction: .debit, bookedAt: t0)
        let anne = S.makeTx(
            ctx, account: roommate, amount: 30, amountEur: 30, direction: .credit,
            bookedAt: t0.addingTimeInterval(86_400), counterparty: "ANNE BRGR"
        )
        let bob = S.makeTx(
            ctx, account: roommate, amount: 30, amountEur: 30, direction: .credit,
            bookedAt: t0.addingTimeInterval(86_400), counterparty: "Bob Smith"
        )
        try ctx.save()

        let results = try SE.findCandidateReimbursements(primaryTxId: primary.id, query: "anne", in: ctx)
        let ids = Set(results.map(\.id))
        XCTAssertTrue(ids.contains(anne.id))
        XCTAssertFalse(ids.contains(bob.id))
    }

    func testFindCandidateRefundedExpensesRequiresCreditStarter() throws {
        let (ctx, _, joint, _) = try happyPathContext()
        let debit = S.makeTx(ctx, account: joint, amount: 100, amountEur: 100, direction: .debit)
        try ctx.save()
        XCTAssertThrowsError(
            try SE.findCandidateRefundedExpenses(creditTxId: debit.id, query: "", in: ctx)
        ) { error in
            XCTAssertEqual(error as? SE.Error, .startingTxNotCredit)
        }
    }

    func testFindCandidateRefundedExpensesReportsExistingReimbursed() throws {
        let (ctx, _, joint, roommate) = try happyPathContext()
        let t0 = Date(timeIntervalSince1970: 1_750_000_000)
        let primary = S.makeTx(ctx, account: joint, amount: 200, amountEur: 200, direction: .debit, bookedAt: t0)
        let r1 = S.makeTx(
            ctx, account: roommate, amount: 50, amountEur: 50, direction: .credit,
            bookedAt: t0.addingTimeInterval(86_400)
        )
        try ctx.save()
        _ = try SE.createGroup(
            .init(label: "Existing", primaryTxId: primary.id, reimbursementTxIds: [r1.id]),
            in: ctx
        )
        // Standalone credit starter to search from.
        let starter = S.makeTx(
            ctx, account: roommate, amount: 60, amountEur: 60, direction: .credit,
            bookedAt: t0.addingTimeInterval(2 * 86_400)
        )
        try ctx.save()

        let results = try SE.findCandidateRefundedExpenses(creditTxId: starter.id, query: "", in: ctx)
        let primaryHit = results.first { $0.id == primary.id }
        XCTAssertNotNil(primaryHit, "Already-grouped primary should appear as a refundable expense")
        XCTAssertEqual(primaryHit?.sharedExpenseGroupId != nil, true)
        XCTAssertEqual(primaryHit?.existingReimbursed, 50)
    }
}
