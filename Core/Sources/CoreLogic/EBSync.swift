import Foundation
import SwiftData
import CoreModel
import CoreIntegrations

// The four EB endpoints the sync touches, as a seam so the orchestration tests run
// without network. EBClient is the production conformance.
public protocol EBSyncAPI: Sendable {
    func getSession(_ sessionId: String) async throws -> SessionResponse
    func getAccountDetails(_ accountUid: String) async throws -> AccountDetails
    func getAccountBalances(_ accountUid: String) async throws -> BalancesResponse
    func getAccountTransactions(_ accountUid: String, query: EBTransactionQuery) async throws -> TransactionsResponse
}

extension EBClient: EBSyncAPI {}

extension CoreLogic {
    // Ports lib/sync-enablebanking.ts: session validation, account upsert with IBAN
    // fallback + cross-connection repoint/merge guards, paginated BOOK transactions with
    // (accountId, externalId) dedupe, then the post-process pipeline. Error strings keep
    // the web's labels so SyncRun rows read the same.
    public enum EBSync {
        static let staleRunSeconds: TimeInterval = 10 * 60
        static let txPageLimit = 50
        static let txLookbackDays = 730
        static let txIncrementalOverlapDays = 7

        public struct PostProcess: Equatable, Sendable {
            public var fxBackfilled = 0
            public var fxSkipped = 0
            public var categorized = 0
            public var routedMirrors = 0
            public var transfersMatched = 0
        }

        public struct SyncResult: Sendable {
            public let connectionId: UUID
            public var accountsTouched = 0
            public var transactionsInserted = 0
            public var errors: [String] = []
            public var postProcess: PostProcess?
        }

        // MARK: - pure helpers

        static func isValidUid(_ uid: String?) -> Bool {
            guard let uid, !uid.isEmpty, uid != "undefined", uid != "null" else { return false }
            return UUID(uuidString: uid) != nil
        }

        static func isoDate(_ date: Date) -> String {
            String(isoFormatter.string(from: date).prefix(10))
        }

        static func computeDateFrom(lastSyncAt: Date?, now: Date = .now) -> String {
            let maxLookback = now.addingTimeInterval(-Double(txLookbackDays) * 86_400)
            guard let lastSyncAt else { return isoDate(maxLookback) }
            let incremental = lastSyncAt.addingTimeInterval(
                -Double(txIncrementalOverlapDays) * 86_400)
            return isoDate(max(incremental, maxLookback))
        }

        nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()

        // MARK: - stale-run reaper

        @MainActor @discardableResult
        public static func reapStaleRuns(in ctx: ModelContext, now: Date = .now) throws -> Int {
            let threshold = now.addingTimeInterval(-staleRunSeconds)
            let stale = try ctx.fetch(FetchDescriptor<SyncRun>(
                predicate: #Predicate { $0.startedAt < threshold && $0.finishedAt == nil }
            )).filter { $0.status == .running }
            for run in stale {
                run.status = .error
                run.finishedAt = now
                run.error = "abandoned"
            }
            if !stale.isEmpty { try ctx.save() }
            return stale.count
        }

        // MARK: - sync

        @MainActor
        public static func sync(
            connection: Connection, api: any EBSyncAPI,
            in ctx: ModelContext, now: Date = .now
        ) async throws -> SyncResult {
            var result = SyncResult(connectionId: connection.id)

            try reapStaleRuns(in: ctx, now: now)
            guard connection.connector == .enablebanking else {
                throw SyncError.notEnableBanking
            }
            guard let sessionId = connection.sessionId else {
                throw SyncError.noSession
            }

            let run = SyncRun(connector: .enablebanking, connection: connection, startedAt: now)
            ctx.insert(run)
            try ctx.save()

            var insertedIds: [UUID] = []

            do {
                let session = try await api.getSession(sessionId)
                guard session.status == "AUTHORIZED" else {
                    let expired = ["REVOKED", "INVALID", "CLOSED"].contains(session.status)
                    connection.status = expired ? .expired : .error
                    connection.lastError = "Session status: \(session.status)"
                    connection.updatedAt = now
                    finish(run, status: .error, error: "session \(session.status)", now: now)
                    try ctx.save()
                    result.errors.append("session \(session.status)")
                    return result
                }

                let sessionAccounts = EBHelpers.sessionAccounts(session)
                result.accountsTouched = sessionAccounts.count

                for sessionAccount in sessionAccounts {
                    do {
                        let inserted = try await syncAccount(
                            sessionAccount, connection: connection, api: api,
                            in: ctx, now: now, errors: &result.errors)
                        insertedIds.append(contentsOf: inserted)
                        result.transactionsInserted += inserted.count
                    } catch {
                        let label = sessionAccount.uid
                            ?? EBHelpers.iban(ofSession: sessionAccount)
                            ?? sessionAccount.identificationHash
                            ?? "account"
                        result.errors.append("\(label): \(describe(error))")
                    }
                }

                var post = PostProcess()
                if !insertedIds.isEmpty {
                    do {
                        let fx = try FX.backfillTransactionEurAmounts(in: ctx, sinceDays: 90)
                        post.fxBackfilled = fx.updated
                        post.fxSkipped = fx.skipped
                    } catch { result.errors.append("fx: \(describe(error))") }
                    do {
                        post.categorized = try Categorize
                            .applyRulesToTransactions(in: ctx, txIds: insertedIds).updated
                    } catch { result.errors.append("categorize: \(describe(error))") }
                    do {
                        post.routedMirrors = try TransferRoutes
                            .apply(in: ctx, txIds: insertedIds).mirroredCreated
                    } catch { result.errors.append("routes: \(describe(error))") }
                    do {
                        post.transfersMatched = try Transfers
                            .detect(in: ctx, sinceDays: 30).matched
                    } catch { result.errors.append("transfers: \(describe(error))") }
                }
                do {
                    _ = try Transfers.repairGroups(in: ctx)
                } catch { result.errors.append("repair: \(describe(error))") }
                do {
                    let violations = try TransferInvariants.assertAll(in: ctx)
                    if !violations.isEmpty {
                        result.errors.append(
                            "invariants: \(TransferInvariants.format(violations))")
                    }
                } catch { result.errors.append("invariants-check: \(describe(error))") }
                result.postProcess = post

                if let valid = session.access.validUntil,
                   let expiresAt = EBHelpers.parseDate(valid) {
                    connection.expiresAt = expiresAt
                }
                connection.status = result.errors.isEmpty ? .active : .error
                connection.lastSyncAt = now
                connection.lastError = result.errors.isEmpty
                    ? nil : result.errors.joined(separator: "; ")
                connection.updatedAt = now

                run.insertedTransactions = result.transactionsInserted
                finish(run, status: result.errors.isEmpty ? .ok : .partial,
                       error: result.errors.isEmpty ? nil : result.errors.joined(separator: "; "),
                       now: now)
                try ctx.save()
                return result
            } catch {
                let expired = (error as? EnableBankingError)
                    .map { $0.status == 401 || $0.status == 403 } ?? false
                connection.status = expired ? .expired : .error
                connection.lastError = describe(error)
                connection.updatedAt = now
                finish(run, status: .error, error: describe(error), now: now)
                try? ctx.save()
                throw error
            }
        }

        @MainActor
        public static func syncAll(
            api: any EBSyncAPI, in ctx: ModelContext, now: Date = .now
        ) async -> [SyncResult] {
            let all = (try? ctx.fetch(FetchDescriptor<Connection>())) ?? []
            var out: [SyncResult] = []
            for connection in all where connection.connector == .enablebanking {
                if connection.status == .revoked || connection.status == .expired { continue }
                do {
                    out.append(try await sync(connection: connection, api: api, in: ctx, now: now))
                } catch {
                    var failed = SyncResult(connectionId: connection.id)
                    failed.errors.append(describe(error))
                    out.append(failed)
                }
            }
            return out
        }

        public enum SyncError: Swift.Error, Equatable {
            case notEnableBanking
            case noSession
        }

        // MARK: - per-account

        @MainActor
        private static func syncAccount(
            _ sessionAccount: SessionAccount, connection: Connection, api: any EBSyncAPI,
            in ctx: ModelContext, now: Date, errors: inout [String]
        ) async throws -> [UUID] {
            guard isValidUid(sessionAccount.uid), let uid = sessionAccount.uid else {
                mergeMetadata([
                    "lastBadAccount": jsonObject(sessionAccount) ?? [:],
                    "lastBadAccountAt": isoFormatter.string(from: now),
                ], into: connection)
                try ctx.save()
                errors.append("bad-uid: Enable Banking returned an account with an invalid uid (\(sessionAccount.uid ?? "nil")). Re-authorize the connection.")
                return []
            }

            let details = try await api.getAccountDetails(uid)
            let balances = try await api.getAccountBalances(uid)
            let interim = EBHelpers.preferredBalance(balances.balances)
            let iban = EBHelpers.iban(ofDetails: details) ?? EBHelpers.iban(ofSession: sessionAccount)
            let currency = EBHelpers.normalizeCurrency(details.currency)
                ?? EBHelpers.normalizeCurrency(sessionAccount.currency)
                ?? EBHelpers.normalizeCurrency(interim?.balanceAmount.currency)
                ?? "EUR"
            let name = details.name ?? sessionAccount.name
                ?? details.product ?? sessionAccount.product ?? iban ?? "Account"
            let institution = connection.institutionName ?? connection.institutionId ?? "Unknown"
            let balance = interim.flatMap { EBHelpers.decimal($0.balanceAmount.amount) }
            let discoveredMeta: [String: Any] = [
                "session": jsonObject(sessionAccount) ?? [:],
                "details": jsonObject(details) ?? [:],
            ]

            let connectionId = connection.id
            let existingByExternal = try ctx.fetch(FetchDescriptor<Account>(
                predicate: #Predicate { $0.connection?.id == connectionId && $0.externalId == uid }
            )).first

            var resolved = existingByExternal
            if resolved == nil, let iban {
                let byIban = try ctx.fetch(FetchDescriptor<Account>(
                    predicate: #Predicate { $0.iban == iban }
                )).filter { $0.connection?.connector == .enablebanking }
                if byIban.count > 1 {
                    errors.append("iban-ambiguous: \(iban) matches \(byIban.count) accounts across connections; refusing to re-point automatically. Resolve manually before continuing.")
                    return []
                }
                resolved = byIban.first
            }

            if let account = resolved,
               account.connection?.id != connectionId || account.externalId != uid {
                if account.connection?.id != connectionId, existingByExternal != nil {
                    errors.append("merge-conflict: \(iban ?? uid) already exists on this connection under a different account row; skipping cross-connection merge.")
                    return []
                }
                let previousConnection = account.connection
                account.connection = connection
                account.externalId = uid
                if let old = previousConnection, old.id != connectionId {
                    old.status = .revoked
                    mergeMetadata([
                        "replacedBy": connectionId.uuidString,
                        "replacedAt": isoFormatter.string(from: now),
                    ], into: old)
                    old.updatedAt = now
                }
            }

            if let account = resolved, account.archived {
                mergeMetadata(["lastDiscoveredAt": isoFormatter.string(from: now)], into: account)
                try ctx.save()
                return []
            }

            guard let account = resolved else {
                // Never-seen account: parked archived + pendingApproval, no transactions
                // until the user unarchives it (web parity).
                let space = try Spaces.ensureDefault(in: ctx, now: now)
                let discovered = Account(
                    connection: connection, space: space, externalId: uid,
                    type: .bank, institution: institution, name: name,
                    currency: currency, iban: iban)
                discovered.archived = true
                var meta = discoveredMeta
                meta["discoveredAt"] = isoFormatter.string(from: now)
                meta["pendingApproval"] = true
                discovered.metadataJSON = try? JSONSerialization.data(withJSONObject: meta)
                ctx.insert(discovered)
                try ctx.save()
                return []
            }

            let prevMeta = metadata(of: account.metadataJSON)
            let fullSync = prevMeta["fullSyncRequested"] as? Bool == true
            let currencyOverridden = prevMeta["currencyOverride"] as? Bool == true
            account.name = name
            if !currencyOverridden { account.currency = currency }
            account.iban = iban
            account.balance = balance
            account.balanceUpdatedAt = now
            var merged = prevMeta.merging(discoveredMeta) { _, new in new }
            if fullSync { merged.removeValue(forKey: "fullSyncRequested") }
            account.metadataJSON = try? JSONSerialization.data(withJSONObject: merged)
            try ctx.save()

            let dateFrom = fullSync
                ? isoDate(now.addingTimeInterval(-Double(txLookbackDays) * 86_400))
                : computeDateFrom(lastSyncAt: connection.lastSyncAt, now: now)

            var insertedIds: [UUID] = []
            var continuationKey: String?
            var pages = 0
            repeat {
                let resp = try await api.getAccountTransactions(uid, query: EBTransactionQuery(
                    dateFrom: dateFrom, transactionStatus: "BOOK",
                    continuationKey: continuationKey, strategy: "longest"))
                for (index, t) in resp.transactions.enumerated() {
                    guard let amount = EBHelpers.signedAmount(t), amount != 0 else { continue }
                    let fallbackId = "\(uid):\(t.bookingDate ?? t.valueDate ?? ""):\(t.transactionAmount.amount):\(t.creditDebitIndicator):\(t.entryReference ?? "p\(pages)-i\(index)")"
                    let externalId = EBHelpers.externalId(t, fallback: fallbackId)
                    let accountId = account.id
                    let exists = try ctx.fetchCount(FetchDescriptor<Transaction>(
                        predicate: #Predicate {
                            $0.account?.id == accountId && $0.externalId == externalId
                        }
                    )) > 0
                    if exists { continue }
                    let description = EBHelpers.description(t)
                    let tx = Transaction(
                        account: account,
                        externalId: externalId,
                        bookedAt: EBHelpers.bookingDate(t) ?? now,
                        valueAt: EBHelpers.valueDate(t),
                        amount: amount,
                        currency: t.transactionAmount.currency,
                        direction: EBHelpers.direction(t.creditDebitIndicator),
                        description: description.isEmpty ? nil : description,
                        counterparty: EBHelpers.counterparty(t),
                        categorySource: .bank,
                        rawJSON: try? EBJSON.encoder.encode(t),
                        createdAt: now)
                    ctx.insert(tx)
                    insertedIds.append(tx.id)
                }
                continuationKey = resp.continuationKey
                pages += 1
            } while continuationKey != nil && pages < txPageLimit
            try ctx.save()
            return insertedIds
        }

        // MARK: - small utilities

        private static func finish(_ run: SyncRun, status: SyncRunStatus, error: String?, now: Date) {
            run.status = status
            run.finishedAt = now
            run.error = error
        }

        private static func describe(_ error: Error) -> String {
            if let eb = error as? EnableBankingError { return "\(eb.status) \(eb.body)" }
            return String(describing: error)
        }

        private static func jsonObject<T: Encodable>(_ value: T) -> Any? {
            (try? EBJSON.encoder.encode(value))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) }
        }

        private static func metadata(of data: Data?) -> [String: Any] {
            guard let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return [:] }
            return object
        }

        private static func mergeMetadata(_ updates: [String: Any], into connection: Connection) {
            var meta = metadata(of: connection.metadataJSON)
            for (key, value) in updates { meta[key] = value }
            connection.metadataJSON = try? JSONSerialization.data(withJSONObject: meta)
        }

        private static func mergeMetadata(_ updates: [String: Any], into account: Account) {
            var meta = metadata(of: account.metadataJSON)
            for (key, value) in updates { meta[key] = value }
            account.metadataJSON = try? JSONSerialization.data(withJSONObject: meta)
        }
    }
}
