#if DEBUG
import SwiftData
import CoreModel
import Foundation

@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let schema = Schema(CoreModelSchema.allTypes)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let ctx = container.mainContext

        let individual = AccountSpace(name: "Individual", isDefault: true, sortOrder: 0)
        let shared = AccountSpace(name: "Uli & Jimmy", sortOrder: 1)
        ctx.insert(individual)
        ctx.insert(shared)

        func add(_ name: String, _ inst: String, _ type: AccountType,
                 _ currency: String, _ balance: Decimal?, _ space: AccountSpace,
                 excluded: Bool = false) {
            ctx.insert(Account(
                space: space, externalId: UUID().uuidString, type: type,
                institution: inst, name: name, currency: currency,
                balance: balance, excluded: excluded
            ))
        }

        add("Checking", "Abanca", .bank, "EUR", 1281.66, individual)
        add("Revolut Savings", "Revolut", .bank, "EUR", 165.45, individual)
        add("Trading212", "Trading212", .broker, "EUR", nil, individual)
        add("Revolut X", "Revolut", .crypto, "USD", 420.00, individual, excluded: true)
        add("Joint Account", "Revolut", .bank, "EUR", 27.00, shared)

        let invGroup = AccountGroup(name: "Investment Accounts", kind: .investment)
        ctx.insert(invGroup)
        let broker = Account(
            group: invGroup, space: individual, externalId: UUID().uuidString,
            type: .broker, institution: "Trading212", name: "Trading212 Brokerage",
            currency: "EUR"
        )
        ctx.insert(broker)
        ctx.insert(PortfolioValuation(
            account: broker, asOf: Date(timeIntervalSinceNow: -120 * 86_400),
            marketValueEur: 8000, cashValueEur: 500
        ))
        ctx.insert(PortfolioValuation(
            account: broker, asOf: Date(timeIntervalSinceNow: -2 * 86_400),
            marketValueEur: 9450, cashValueEur: 300
        ))

        let groceries = CoreModel.Category(name: "Groceries")
        ctx.insert(groceries)
        let checking = (try? ctx.fetch(FetchDescriptor<Account>(
            predicate: #Predicate { $0.name == "Checking" }
        )))?.first

        func tx(_ desc: String, _ amount: Decimal, _ dir: TxDirection,
                _ days: Int, category: CoreModel.Category? = nil, transfer: Bool = false) {
            let when = Date(timeIntervalSinceNow: -Double(days) * 86_400)
            ctx.insert(CoreModel.Transaction(
                account: checking, externalId: UUID().uuidString,
                bookedAt: when, amount: amount, currency: "EUR", amountEur: amount,
                direction: dir, description: desc, counterparty: desc,
                category: category, categorySource: category == nil ? .bank : .manual,
                isTransfer: transfer
            ))
        }

        tx("Mercadona", -42.18, .debit, 1, category: groceries)
        tx("Payroll", 2100.00, .credit, 3)
        tx("Transfer to Savings", -200.00, .debit, 5, transfer: true)
        tx("Netflix", -13.99, .debit, 8)

        try? ctx.save()
        return container
    }()

    static var sampleTransaction: CoreModel.Transaction {
        let ctx = container.mainContext
        var d = FetchDescriptor<CoreModel.Transaction>(
            sortBy: [SortDescriptor(\.bookedAt, order: .reverse)]
        )
        d.fetchLimit = 1
        return (try? ctx.fetch(d))?.first
            ?? CoreModel.Transaction(externalId: "preview", bookedAt: .now,
                                     amount: 0, currency: "EUR", direction: .debit)
    }
}
#endif
