import SwiftUI
import SwiftData
import LocalAuthentication
import CoreModel
import CoreLogic

// The Settings tab — single home for every secondary surface (was two toolbar "More"
// menus). All navigationDestinations are registered here so DEBUG hooks can deep-push.
struct SettingsView: View {
    @State private var path = NavigationPath()
    @AppStorage(SecuritySettings.requireUnlockKey) private var requireUnlock = true
    @AppStorage(CycleSettings.startDayKey) private var cycleStartDay = 1
    @AppStorage(CycleSettings.startsEarlyOnWeekendsKey) private var startsEarlyOnWeekends = true
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
                    SettingsLinkRow(title: "Connections", systemImage: "link", destination: .connections)
                    SettingsLinkRow(title: "Trading 212", systemImage: "chart.line.uptrend.xyaxis", destination: .trading212)
                }
                Section("Money") {
                    SettingsLinkRow(title: "Transfers", systemImage: "arrow.left.arrow.right", destination: .transfers)
                    SettingsLinkRow(title: "Matches", systemImage: "plusminus.circle", destination: .sharedExpenses)
                    SettingsLinkRow(title: "Budgets", systemImage: "chart.pie", destination: .budgets)
                    SettingsLinkRow(title: "Automations", systemImage: "bolt.badge.clock", destination: .automations)
                }
                Section {
                    Picker(selection: $cycleStartDay) {
                        ForEach(1...CoreLogic.Dashboard.maxCycleStartDay, id: \.self) { day in
                            Text(day == 1 ? "1st (calendar month)" : Self.ordinal(day)).tag(day)
                        }
                    } label: {
                        HStack(spacing: Theme.Space.m) {
                            IconBadge(systemName: "calendar")
                            Text("Month Starts On")
                        }
                    }
                    .pickerStyle(.menu)
                    if cycleStartDay != 1 {
                        Toggle("Start Friday Before a Weekend", isOn: $startsEarlyOnWeekends)
                    }
                } footer: {
                    Text(cycleFooter)
                }
                Section("Manage") {
                    SettingsLinkRow(title: "Categories", systemImage: "tag", destination: .categories)
                    SettingsLinkRow(title: "Rules", systemImage: "wand.and.stars", destination: .rules)
                    SettingsLinkRow(title: "Transfer Routes", systemImage: "arrow.triangle.branch", destination: .transferRoutes)
                    SettingsLinkRow(title: "Spaces", systemImage: "rectangle.stack", destination: .spaces)
                    SettingsLinkRow(title: "Groups", systemImage: "square.stack.3d.up", destination: .groups)
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
                case .automations: AutomationsView()
                case .transfers: TransfersView()
                case .sharedExpenses: SharedExpensesView()
                case .budgets: BudgetsView()
                case .categories: ManageCategoriesView()
                case .rules: ManageRulesView()
                case .transferRoutes: ManageTransferRoutesView()
                case .spaces: ManageSpacesView()
                case .groups: ManageGroupsView()
                case .trading212: Trading212SettingsView()
                }
            }
            .navigationDestination(for: Connection.self) { ConnectionDetailView(connection: $0) }
            .navigationDestination(for: SharedExpenseGroup.self) { SharedExpenseGroupDetailView(group: $0) }
            #if DEBUG
            .task { applyHook() }
            #endif
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

    private var cycleFooter: String {
        guard cycleStartDay != 1 else { return "Income and expenses are grouped by calendar month." }
        var text = "Income and expenses are grouped from the \(Self.ordinal(cycleStartDay)) to the day before the \(Self.ordinal(cycleStartDay)) of the next month."
        if startsEarlyOnWeekends {
            text += " When the \(Self.ordinal(cycleStartDay)) is a Saturday or Sunday, the month starts on the Friday before, like a salary paid early."
        }
        return text + " Every past month is recalculated."
    }

    private static func ordinal(_ day: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        f.locale = Locale(identifier: "en_GB")
        return f.string(from: day as NSNumber) ?? "\(day)"
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
        case "trading212": path.append(SettingsDestination.trading212)
        case "automations": path.append(SettingsDestination.automations)
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
    case connections, transfers, sharedExpenses, budgets, categories, rules, transferRoutes, spaces, groups, trading212, automations
}

// A Settings navigation row: teal icon chip + title, pushing a destination.
private struct SettingsLinkRow: View {
    let title: String
    let systemImage: String
    let destination: SettingsDestination

    var body: some View {
        NavigationLink(value: destination) {
            HStack(spacing: Theme.Space.m) {
                IconBadge(systemName: systemImage)
                Text(title)
            }
        }
    }
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
