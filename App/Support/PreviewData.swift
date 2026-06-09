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

        try? ctx.save()
        return container
    }()
}
#endif
