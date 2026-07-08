import AppIntents
import SwiftData
import CoreModel

// Exposes each manual account (no bank connection) as a pickable option in the "Log Card Charge"
// Shortcuts action. Picking one in an automation IS the per-account routing — no app-side tags.
struct ManualAccountEntity: AppEntity, Identifiable {
    let id: UUID
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static let defaultQuery = ManualAccountQuery()
}

struct ManualAccountQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ManualAccountEntity] {
        let ids = Set(identifiers)
        return try manualAccounts().filter { ids.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ManualAccountEntity] {
        try manualAccounts()
    }

    // Reads the app's store directly. App Intents run in the app's own sandbox, so a container on
    // the default store URL sees the same data. Read-only, so a second container is safe.
    @MainActor
    private func manualAccounts() throws -> [ManualAccountEntity] {
        let schema = Schema(CoreModelSchema.allTypes)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let ctx = ModelContext(container)
        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        return accounts
            .filter { $0.connection == nil && !$0.archived }
            .sorted { $0.name < $1.name }
            .map { ManualAccountEntity(id: $0.id, name: $0.name) }
    }
}
