import Foundation
import SwiftData
import CoreModel

// SwiftData's `@Relationship(deleteRule: .cascade)` is unreliable, and the inverse
// arrays it back-populates aren't always available without a save. All destructive
// operations go through these helpers, which fetch related objects by predicate so
// the cascade graph is expressed in code we can read, test, and trust.
extension CoreLogic {
    @MainActor
    public static func deleteTransaction(_ tx: Transaction, in ctx: ModelContext) {
        let txID = tx.id
        if let group = (try? ctx.fetch(FetchDescriptor<SharedExpenseGroup>(
            predicate: #Predicate { $0.primaryTx?.id == txID }
        )))?.first {
            deleteSharedExpenseGroup(group, in: ctx)
        }
        let mirrors = (try? ctx.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.routedFromTx?.id == txID }
        ))) ?? []
        for mirror in mirrors {
            ctx.delete(mirror)
        }
        ctx.delete(tx)
    }

    @MainActor
    public static func deleteSharedExpenseGroup(
        _ group: SharedExpenseGroup,
        in ctx: ModelContext
    ) {
        let groupID = group.id
        let members = (try? ctx.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.sharedExpenseGroup?.id == groupID }
        ))) ?? []
        for member in members {
            member.sharedExpenseGroup = nil
        }
        ctx.delete(group)
    }

    @MainActor
    public static func deleteAccount(_ account: Account, in ctx: ModelContext) {
        let accountID = account.id
        let txs = (try? ctx.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.account?.id == accountID }
        ))) ?? []
        for tx in txs {
            deleteTransaction(tx, in: ctx)
        }
        let valuations = (try? ctx.fetch(FetchDescriptor<PortfolioValuation>(
            predicate: #Predicate { $0.account?.id == accountID }
        ))) ?? []
        for v in valuations {
            ctx.delete(v)
        }
        let routes = (try? ctx.fetch(FetchDescriptor<TransferRoute>(
            predicate: #Predicate {
                $0.targetAccount?.id == accountID || $0.sourceAccount?.id == accountID
            }
        ))) ?? []
        for route in routes {
            ctx.delete(route)
        }
        ctx.delete(account)
    }

    @MainActor
    public static func deleteConnection(_ connection: Connection, in ctx: ModelContext) {
        let connectionID = connection.id
        let accounts = (try? ctx.fetch(FetchDescriptor<Account>(
            predicate: #Predicate { $0.connection?.id == connectionID }
        ))) ?? []
        for account in accounts {
            deleteAccount(account, in: ctx)
        }
        let runs = (try? ctx.fetch(FetchDescriptor<SyncRun>(
            predicate: #Predicate { $0.connection?.id == connectionID }
        ))) ?? []
        for run in runs {
            run.connection = nil
        }
        ctx.delete(connection)
    }
}
