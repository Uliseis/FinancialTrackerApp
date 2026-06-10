import SwiftUI
import SwiftData
import CoreModel

// The Settings tab — single home for every secondary surface (was two toolbar "More"
// menus). All navigationDestinations are registered here so DEBUG hooks can deep-push.
struct SettingsView: View {
    @State private var path = NavigationPath()
    #if DEBUG
    @Query(sort: [SortDescriptor(\SharedExpenseGroup.createdAt, order: .reverse)])
    private var debugGroups: [SharedExpenseGroup]
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    link("Connections", systemImage: "link", to: .connections)
                }
                Section("Money") {
                    link("Shared Expenses", systemImage: "person.2", to: .sharedExpenses)
                    link("Budgets", systemImage: "chart.pie", to: .budgets)
                }
                Section("Manage") {
                    link("Categories", systemImage: "tag", to: .categories)
                    link("Rules", systemImage: "wand.and.stars", to: .rules)
                    link("Transfer Routes", systemImage: "arrow.triangle.branch", to: .transferRoutes)
                    link("Spaces", systemImage: "rectangle.stack", to: .spaces)
                    link("Groups", systemImage: "square.stack.3d.up", to: .groups)
                }
                Section {
                    LabeledContent("Version", value: Self.versionString)
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .connections: ConnectionsListView()
                case .sharedExpenses: SharedExpensesView()
                case .budgets: BudgetsView()
                case .categories: ManageCategoriesView()
                case .rules: ManageRulesView()
                case .transferRoutes: ManageTransferRoutesView()
                case .spaces: ManageSpacesView()
                case .groups: ManageGroupsView()
                }
            }
            .navigationDestination(for: Connection.self) { ConnectionDetailView(connection: $0) }
            .navigationDestination(for: SharedExpenseGroup.self) { SharedExpenseGroupDetailView(group: $0) }
            #if DEBUG
            .task { applyHook() }
            #endif
        }
    }

    private func link(_ title: String, systemImage: String, to destination: SettingsDestination) -> some View {
        NavigationLink(value: destination) {
            Label(title, systemImage: systemImage)
        }
    }

    private static var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    #if DEBUG
    private func applyHook() {
        switch UITestHooks.presentSheet {
        case "connections": path.append(SettingsDestination.connections)
        case "spaces", "space-edit": path.append(SettingsDestination.spaces)
        case "groups", "group-edit": path.append(SettingsDestination.groups)
        case "categories", "category-edit": path.append(SettingsDestination.categories)
        case "rules", "rule-edit": path.append(SettingsDestination.rules)
        case "routes", "route-edit": path.append(SettingsDestination.transferRoutes)
        case "budgets", "budget-edit": path.append(SettingsDestination.budgets)
        case "shared": path.append(SettingsDestination.sharedExpenses)
        case "shared-detail":
            path.append(SettingsDestination.sharedExpenses)
            if let first = debugGroups.first { path.append(first) }
        default: break
        }
    }
    #endif
}

enum SettingsDestination: Hashable {
    case connections, sharedExpenses, budgets, categories, rules, transferRoutes, spaces, groups
}

#if DEBUG
#Preview {
    SettingsView()
        .modelContainer(PreviewData.container)
}
#endif
