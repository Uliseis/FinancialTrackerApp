import SwiftUI
import SwiftData
import LocalAuthentication
import CoreModel

// The Settings tab — single home for every secondary surface (was two toolbar "More"
// menus). All navigationDestinations are registered here so DEBUG hooks can deep-push.
struct SettingsView: View {
    @State private var path = NavigationPath()
    @AppStorage(SecuritySettings.requireUnlockKey) private var requireUnlock = true
    #if DEBUG
    @Query(sort: [SortDescriptor(\SharedExpenseGroup.createdAt, order: .reverse)])
    private var debugGroups: [SharedExpenseGroup]
    @Query(sort: [SortDescriptor(\Connection.institutionName)])
    private var debugConnections: [Connection]
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    SettingsBrandHeader(version: Self.versionString)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                Section {
                    link("Connections", systemImage: "link", to: .connections)
                }
                Section("Money") {
                    link("Transfers", systemImage: "arrow.left.arrow.right", to: .transfers)
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
                    Toggle("Require Face ID", isOn: $requireUnlock)
                        .onChange(of: requireUnlock) { wasOn, isOn in
                            if wasOn && !isOn { confirmDisable() }
                        }
                    LabeledContent("iCloud Sync", value: CloudKitGate.isAvailable ? "On" : "Unavailable")
                } header: {
                    Text("App")
                } footer: {
                    Text(CloudKitGate.isAvailable
                         ? "Locks when the app goes to the background. Turning the lock off requires Face ID."
                         : "Locks when the app goes to the background. Turning the lock off requires Face ID. Sync needs an iCloud-signed-in, entitled build.")
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .connections: ConnectionsListView()
                case .transfers: TransfersView()
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
            HStack(spacing: Theme.Space.m) {
                IconBadge(systemName: systemImage)
                Text(title)
            }
        }
    }

    // Disabling the lock is itself a privileged action: without this, anyone holding the
    // unlocked phone could silently strip the protection. Fails closed — if authentication
    // can't run or fails, the lock stays on.
    private func confirmDisable() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            requireUnlock = true
            return
        }
        Task {
            let success = (try? await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Confirm turning off the app lock"
            )) ?? false
            if !success { requireUnlock = true }
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
        case "connections", "eb-setup", "connect-bank", "eb-sync-all":
            path.append(SettingsDestination.connections)
        case "connection-detail":
            path.append(SettingsDestination.connections)
            if let first = debugConnections.first { path.append(first) }
        case "transfers": path.append(SettingsDestination.transfers)
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
    case connections, transfers, sharedExpenses, budgets, categories, rules, transferRoutes, spaces, groups
}

// Brand identity block at the top of Settings.
private struct SettingsBrandHeader: View {
    let version: String

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            CompassMark(size: 56, tint: .brand, ringOpacity: 0)
            Text("Odyssey Finance")
                .font(.title3.weight(.semibold))
            Text("Version \(version)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.s)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Odyssey Finance, version \(version)")
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .modelContainer(PreviewData.container)
}
#endif
