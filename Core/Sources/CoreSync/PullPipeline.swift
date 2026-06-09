import Foundation
import SwiftData
import CloudKit
import CoreModel
import CoreLogic

public struct PullReport: Equatable, Sendable {
    public var inserted: Int = 0
    public var updatedRemote: Int = 0
    public var keptLocal: Int = 0
    public var merged: Int = 0
    public var deleted: Int = 0
    public var duplicatesResolved: Int = 0
    public var skippedUnknownType: Int = 0
    public var skippedNonUUID: Int = 0
    public var skippedDecodeError: Int = 0

    public init() {}
}

public struct PullDeletion: Sendable {
    public let recordID: CKRecord.ID
    public let recordType: String

    public init(recordID: CKRecord.ID, recordType: String) {
        self.recordID = recordID
        self.recordType = recordType
    }
}

public enum PullPipeline {

    @MainActor
    public static func apply(
        modifications: [CKRecord],
        deletions: [PullDeletion],
        in ctx: ModelContext
    ) throws -> PullReport {
        var report = PullReport()

        let sorted = modifications.sorted { lhs, rhs in
            priority(of: lhs.recordType) < priority(of: rhs.recordType)
        }

        for record in sorted {
            applyOne(record, in: ctx, report: &report)
        }

        for record in sorted where record.recordType == RecordType.transaction {
            relinkTransactionCycle(record, in: ctx)
        }

        for deletion in deletions {
            applyDeletion(deletion, in: ctx, report: &report)
        }

        try ctx.save()
        return report
    }

    // MARK: - dispatch

    @MainActor
    private static func applyOne(
        _ record: CKRecord,
        in ctx: ModelContext,
        report: inout PullReport
    ) {
        switch record.recordType {
        case RecordType.connection:
            applyConnection(record, in: ctx, report: &report)
        case RecordType.accountGroup:
            applyAccountGroup(record, in: ctx, report: &report)
        case RecordType.accountSpace:
            applyAccountSpace(record, in: ctx, report: &report)
        case RecordType.account:
            applyAccount(record, in: ctx, report: &report)
        case RecordType.category:
            applyCategory(record, in: ctx, report: &report)
        case RecordType.categoryRule:
            applyCategoryRule(record, in: ctx, report: &report)
        case RecordType.transferRoute:
            applyTransferRoute(record, in: ctx, report: &report)
        case RecordType.transferGroup:
            applyTransferGroup(record, in: ctx, report: &report)
        case RecordType.budget:
            applyBudget(record, in: ctx, report: &report)
        case RecordType.fxRate:
            applyFxRate(record, in: ctx, report: &report)
        case RecordType.transaction:
            applyTransaction(record, in: ctx, report: &report)
        case RecordType.sharedExpenseGroup:
            applySharedExpenseGroup(record, in: ctx, report: &report)
        case RecordType.portfolioValuation:
            applyPortfolioValuation(record, in: ctx, report: &report)
        case RecordType.syncRun:
            applySyncRun(record, in: ctx, report: &report)
        default:
            report.skippedUnknownType += 1
        }
    }

    @MainActor
    private static func applyDeletion(
        _ d: PullDeletion,
        in ctx: ModelContext,
        report: inout PullReport
    ) {
        guard let uuid = UUID(uuidString: d.recordID.recordName) else {
            report.skippedNonUUID += 1
            return
        }
        switch d.recordType {
        case RecordType.connection:
            if let m = ModelSnapshots.find(connection: uuid, in: ctx) {
                CoreLogic.deleteConnection(m, in: ctx); report.deleted += 1
            }
        case RecordType.account:
            if let m = ModelSnapshots.find(account: uuid, in: ctx) {
                CoreLogic.deleteAccount(m, in: ctx); report.deleted += 1
            }
        case RecordType.transaction:
            if let m = ModelSnapshots.find(transaction: uuid, in: ctx) {
                CoreLogic.deleteTransaction(m, in: ctx); report.deleted += 1
            }
        case RecordType.sharedExpenseGroup:
            if let m = ModelSnapshots.find(sharedExpenseGroup: uuid, in: ctx) {
                CoreLogic.deleteSharedExpenseGroup(m, in: ctx); report.deleted += 1
            }
        case RecordType.accountGroup:
            if let m = ModelSnapshots.find(accountGroup: uuid, in: ctx) {
                ctx.delete(m); report.deleted += 1
            }
        case RecordType.accountSpace:
            if let m = ModelSnapshots.find(accountSpace: uuid, in: ctx) {
                ctx.delete(m); report.deleted += 1
            }
        case RecordType.category:
            if let m = ModelSnapshots.find(category: uuid, in: ctx) {
                ctx.delete(m); report.deleted += 1
            }
        case RecordType.categoryRule:
            if let m = ModelSnapshots.find(categoryRule: uuid, in: ctx) {
                ctx.delete(m); report.deleted += 1
            }
        case RecordType.transferRoute:
            if let m = ModelSnapshots.find(transferRoute: uuid, in: ctx) {
                ctx.delete(m); report.deleted += 1
            }
        case RecordType.transferGroup:
            if let m = ModelSnapshots.find(transferGroup: uuid, in: ctx) {
                ctx.delete(m); report.deleted += 1
            }
        case RecordType.budget:
            if let m = ModelSnapshots.find(budget: uuid, in: ctx) {
                ctx.delete(m); report.deleted += 1
            }
        case RecordType.fxRate:
            if let m = ModelSnapshots.find(fxRate: uuid, in: ctx) {
                ctx.delete(m); report.deleted += 1
            }
        case RecordType.portfolioValuation:
            if let m = ModelSnapshots.find(portfolioValuation: uuid, in: ctx) {
                ctx.delete(m); report.deleted += 1
            }
        case RecordType.syncRun:
            if let m = ModelSnapshots.find(syncRun: uuid, in: ctx) {
                ctx.delete(m); report.deleted += 1
            }
        default:
            report.skippedUnknownType += 1
        }
    }

    // MARK: - per-type apply

    @MainActor
    private static func applyConnection(_ r: CKRecord, in ctx: ModelContext, report: inout PullReport) {
        guard let snap = try? RecordCoding.decodeConnection(r) else {
            report.skippedDecodeError += 1; return
        }
        if let local = ModelSnapshots.find(connection: snap.id, in: ctx) {
            let local0 = ModelSnapshots.snapshot(local)
            switch ConflictResolver.resolve(local: local0, remote: snap) {
            case .applyRemote: ModelSnapshots.apply(snap, to: local); report.updatedRemote += 1
            case .keepLocal:   report.keptLocal += 1
            case .merge(let m): ModelSnapshots.apply(m, to: local); report.merged += 1
            }
        } else {
            _ = ModelSnapshots.insertOrUpdate(snap, in: ctx); report.inserted += 1
        }
    }

    @MainActor
    private static func applyAccountGroup(_ r: CKRecord, in ctx: ModelContext, report: inout PullReport) {
        guard let snap = try? RecordCoding.decodeAccountGroup(r) else {
            report.skippedDecodeError += 1; return
        }
        if let local = ModelSnapshots.find(accountGroup: snap.id, in: ctx) {
            let local0 = ModelSnapshots.snapshot(local)
            switch ConflictResolver.resolve(local: local0, remote: snap) {
            case .applyRemote: ModelSnapshots.apply(snap, to: local); report.updatedRemote += 1
            case .keepLocal:   report.keptLocal += 1
            case .merge(let m): ModelSnapshots.apply(m, to: local); report.merged += 1
            }
        } else {
            _ = ModelSnapshots.insertOrUpdate(snap, in: ctx); report.inserted += 1
        }
    }

    @MainActor
    private static func applyAccountSpace(_ r: CKRecord, in ctx: ModelContext, report: inout PullReport) {
        guard let snap = try? RecordCoding.decodeAccountSpace(r) else {
            report.skippedDecodeError += 1; return
        }
        if let local = ModelSnapshots.find(accountSpace: snap.id, in: ctx) {
            let local0 = ModelSnapshots.snapshot(local)
            switch ConflictResolver.resolve(local: local0, remote: snap) {
            case .applyRemote: ModelSnapshots.apply(snap, to: local); report.updatedRemote += 1
            case .keepLocal:   report.keptLocal += 1
            case .merge(let m): ModelSnapshots.apply(m, to: local); report.merged += 1
            }
        } else {
            _ = ModelSnapshots.insertOrUpdate(snap, in: ctx); report.inserted += 1
        }
    }

    @MainActor
    private static func applyAccount(_ r: CKRecord, in ctx: ModelContext, report: inout PullReport) {
        guard let snap = try? RecordCoding.decodeAccount(r) else {
            report.skippedDecodeError += 1; return
        }
        if let local = ModelSnapshots.find(account: snap.id, in: ctx) {
            let local0 = ModelSnapshots.snapshot(local)
            switch ConflictResolver.resolve(local: local0, remote: snap) {
            case .applyRemote: ModelSnapshots.apply(snap, to: local, in: ctx); report.updatedRemote += 1
            case .keepLocal:   report.keptLocal += 1
            case .merge(let m): ModelSnapshots.apply(m, to: local, in: ctx); report.merged += 1
            }
        } else {
            _ = ModelSnapshots.insertOrUpdate(snap, in: ctx); report.inserted += 1
        }
    }

    @MainActor
    private static func applyCategory(_ r: CKRecord, in ctx: ModelContext, report: inout PullReport) {
        guard let snap = try? RecordCoding.decodeCategory(r) else {
            report.skippedDecodeError += 1; return
        }
        if let local = ModelSnapshots.find(category: snap.id, in: ctx) {
            let local0 = ModelSnapshots.snapshot(local)
            switch ConflictResolver.resolve(local: local0, remote: snap) {
            case .applyRemote: ModelSnapshots.apply(snap, to: local, in: ctx); report.updatedRemote += 1
            case .keepLocal:   report.keptLocal += 1
            case .merge(let m): ModelSnapshots.apply(m, to: local, in: ctx); report.merged += 1
            }
        } else {
            _ = ModelSnapshots.insertOrUpdate(snap, in: ctx); report.inserted += 1
        }
    }

    @MainActor
    private static func applyCategoryRule(_ r: CKRecord, in ctx: ModelContext, report: inout PullReport) {
        guard let snap = try? RecordCoding.decodeCategoryRule(r) else {
            report.skippedDecodeError += 1; return
        }
        if let local = ModelSnapshots.find(categoryRule: snap.id, in: ctx) {
            let local0 = ModelSnapshots.snapshot(local)
            switch ConflictResolver.resolve(local: local0, remote: snap) {
            case .applyRemote: ModelSnapshots.apply(snap, to: local, in: ctx); report.updatedRemote += 1
            case .keepLocal:   report.keptLocal += 1
            case .merge(let m): ModelSnapshots.apply(m, to: local, in: ctx); report.merged += 1
            }
        } else {
            _ = ModelSnapshots.insertOrUpdate(snap, in: ctx); report.inserted += 1
        }
    }

    @MainActor
    private static func applyTransferRoute(_ r: CKRecord, in ctx: ModelContext, report: inout PullReport) {
        guard let snap = try? RecordCoding.decodeTransferRoute(r) else {
            report.skippedDecodeError += 1; return
        }
        if let local = ModelSnapshots.find(transferRoute: snap.id, in: ctx) {
            let local0 = ModelSnapshots.snapshot(local)
            switch ConflictResolver.resolve(local: local0, remote: snap) {
            case .applyRemote: ModelSnapshots.apply(snap, to: local, in: ctx); report.updatedRemote += 1
            case .keepLocal:   report.keptLocal += 1
            case .merge(let m): ModelSnapshots.apply(m, to: local, in: ctx); report.merged += 1
            }
        } else {
            _ = ModelSnapshots.insertOrUpdate(snap, in: ctx); report.inserted += 1
        }
    }

    @MainActor
    private static func applyTransferGroup(_ r: CKRecord, in ctx: ModelContext, report: inout PullReport) {
        guard let snap = try? RecordCoding.decodeTransferGroup(r) else {
            report.skippedDecodeError += 1; return
        }
        if let local = ModelSnapshots.find(transferGroup: snap.id, in: ctx) {
            let local0 = ModelSnapshots.snapshot(local)
            switch ConflictResolver.resolve(local: local0, remote: snap) {
            case .applyRemote: ModelSnapshots.apply(snap, to: local, in: ctx); report.updatedRemote += 1
            case .keepLocal:   report.keptLocal += 1
            case .merge(let m): ModelSnapshots.apply(m, to: local, in: ctx); report.merged += 1
            }
        } else {
            _ = ModelSnapshots.insertOrUpdate(snap, in: ctx); report.inserted += 1
        }
    }

    @MainActor
    private static func applyBudget(_ r: CKRecord, in ctx: ModelContext, report: inout PullReport) {
        guard let snap = try? RecordCoding.decodeBudget(r) else {
            report.skippedDecodeError += 1; return
        }
        if let local = ModelSnapshots.find(budget: snap.id, in: ctx) {
            let local0 = ModelSnapshots.snapshot(local)
            switch ConflictResolver.resolve(local: local0, remote: snap) {
            case .applyRemote: ModelSnapshots.apply(snap, to: local, in: ctx); report.updatedRemote += 1
            case .keepLocal:   report.keptLocal += 1
            case .merge(let m): ModelSnapshots.apply(m, to: local, in: ctx); report.merged += 1
            }
        } else {
            _ = ModelSnapshots.insertOrUpdate(snap, in: ctx); report.inserted += 1
        }
    }

    @MainActor
    private static func applyFxRate(_ r: CKRecord, in ctx: ModelContext, report: inout PullReport) {
        guard let snap = try? RecordCoding.decodeFxRate(r) else {
            report.skippedDecodeError += 1; return
        }
        if let local = ModelSnapshots.find(fxRate: snap.id, in: ctx) {
            let local0 = ModelSnapshots.snapshot(local)
            switch ConflictResolver.resolve(local: local0, remote: snap) {
            case .applyRemote: ModelSnapshots.apply(snap, to: local); report.updatedRemote += 1
            case .keepLocal:   report.keptLocal += 1
            case .merge(let m): ModelSnapshots.apply(m, to: local); report.merged += 1
            }
            return
        }
        if let dup = ModelSnapshots.findFxRate(date: snap.date, currency: snap.currency, in: ctx) {
            let dupSnap = ModelSnapshots.snapshot(dup)
            switch CompositeDedupe.dedupe(incoming: snap, existing: dupSnap) {
            case .duplicate(let winnerId, _):
                report.duplicatesResolved += 1
                if winnerId == snap.id {
                    ctx.delete(dup)
                    _ = ModelSnapshots.insertOrUpdate(snap, in: ctx)
                    report.inserted += 1
                }
            case .insert, .sameRow:
                _ = ModelSnapshots.insertOrUpdate(snap, in: ctx); report.inserted += 1
            }
            return
        }
        _ = ModelSnapshots.insertOrUpdate(snap, in: ctx); report.inserted += 1
    }

    @MainActor
    private static func applyTransaction(_ r: CKRecord, in ctx: ModelContext, report: inout PullReport) {
        guard let snap = try? RecordCoding.decodeTransaction(r) else {
            report.skippedDecodeError += 1; return
        }
        if let local = ModelSnapshots.find(transaction: snap.id, in: ctx) {
            let local0 = ModelSnapshots.snapshot(local)
            switch ConflictResolver.resolveTransaction(local: local0, remote: snap) {
            case .applyRemote: ModelSnapshots.apply(snap, to: local, in: ctx); report.updatedRemote += 1
            case .keepLocal:   report.keptLocal += 1
            case .merge(let m): ModelSnapshots.apply(m, to: local, in: ctx); report.merged += 1
            }
            return
        }
        if let accountId = snap.accountId,
           let dup = ModelSnapshots.findTransaction(accountId: accountId, externalId: snap.externalId, in: ctx) {
            let dupSnap = ModelSnapshots.snapshot(dup)
            switch CompositeDedupe.dedupe(incoming: snap, existing: dupSnap) {
            case .duplicate(let winnerId, _):
                report.duplicatesResolved += 1
                if winnerId == snap.id {
                    CoreLogic.deleteTransaction(dup, in: ctx)
                    _ = ModelSnapshots.insertOrUpdate(snap, in: ctx)
                    report.inserted += 1
                }
            case .insert, .sameRow:
                _ = ModelSnapshots.insertOrUpdate(snap, in: ctx); report.inserted += 1
            }
            return
        }
        _ = ModelSnapshots.insertOrUpdate(snap, in: ctx); report.inserted += 1
    }

    @MainActor
    private static func applySharedExpenseGroup(_ r: CKRecord, in ctx: ModelContext, report: inout PullReport) {
        guard let snap = try? RecordCoding.decodeSharedExpenseGroup(r) else {
            report.skippedDecodeError += 1; return
        }
        if let local = ModelSnapshots.find(sharedExpenseGroup: snap.id, in: ctx) {
            let local0 = ModelSnapshots.snapshot(local)
            switch ConflictResolver.resolve(local: local0, remote: snap) {
            case .applyRemote: ModelSnapshots.apply(snap, to: local, in: ctx); report.updatedRemote += 1
            case .keepLocal:   report.keptLocal += 1
            case .merge(let m): ModelSnapshots.apply(m, to: local, in: ctx); report.merged += 1
            }
        } else {
            _ = ModelSnapshots.insertOrUpdate(snap, in: ctx); report.inserted += 1
        }
    }

    @MainActor
    private static func applyPortfolioValuation(_ r: CKRecord, in ctx: ModelContext, report: inout PullReport) {
        guard let snap = try? RecordCoding.decodePortfolioValuation(r) else {
            report.skippedDecodeError += 1; return
        }
        if let local = ModelSnapshots.find(portfolioValuation: snap.id, in: ctx) {
            let local0 = ModelSnapshots.snapshot(local)
            switch ConflictResolver.resolve(local: local0, remote: snap) {
            case .applyRemote: ModelSnapshots.apply(snap, to: local, in: ctx); report.updatedRemote += 1
            case .keepLocal:   report.keptLocal += 1
            case .merge(let m): ModelSnapshots.apply(m, to: local, in: ctx); report.merged += 1
            }
        } else {
            _ = ModelSnapshots.insertOrUpdate(snap, in: ctx); report.inserted += 1
        }
    }

    @MainActor
    private static func applySyncRun(_ r: CKRecord, in ctx: ModelContext, report: inout PullReport) {
        guard let snap = try? RecordCoding.decodeSyncRun(r) else {
            report.skippedDecodeError += 1; return
        }
        if let local = ModelSnapshots.find(syncRun: snap.id, in: ctx) {
            let local0 = ModelSnapshots.snapshot(local)
            switch ConflictResolver.resolve(local: local0, remote: snap) {
            case .applyRemote: ModelSnapshots.apply(snap, to: local, in: ctx); report.updatedRemote += 1
            case .keepLocal:   report.keptLocal += 1
            case .merge(let m): ModelSnapshots.apply(m, to: local, in: ctx); report.merged += 1
            }
        } else {
            _ = ModelSnapshots.insertOrUpdate(snap, in: ctx); report.inserted += 1
        }
    }

    // MARK: - cycle relink

    @MainActor
    private static func relinkTransactionCycle(_ r: CKRecord, in ctx: ModelContext) {
        guard let snap = try? RecordCoding.decodeTransaction(r) else { return }
        guard let local = ModelSnapshots.find(transaction: snap.id, in: ctx) else { return }
        if let segId = snap.sharedExpenseGroupId, local.sharedExpenseGroup == nil {
            local.sharedExpenseGroup = ModelSnapshots.find(sharedExpenseGroup: segId, in: ctx)
        }
        if let routedFromId = snap.routedFromTxId, local.routedFromTx == nil {
            local.routedFromTx = ModelSnapshots.find(transaction: routedFromId, in: ctx)
        }
    }

    // MARK: - dependency ordering

    private static func priority(of recordType: String) -> Int {
        switch recordType {
        case RecordType.connection, RecordType.accountGroup,
             RecordType.accountSpace, RecordType.category,
             RecordType.fxRate:
            return 0
        case RecordType.account:
            return 1
        case RecordType.categoryRule, RecordType.transferRoute:
            return 2
        case RecordType.transferGroup, RecordType.budget,
             RecordType.portfolioValuation, RecordType.syncRun:
            return 3
        case RecordType.transaction:
            return 4
        case RecordType.sharedExpenseGroup:
            return 5
        default:
            return 99
        }
    }
}
