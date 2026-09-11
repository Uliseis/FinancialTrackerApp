import SwiftUI

struct RootTabView: View {
    @State private var selection: AppTab = .initial

    var body: some View {
        let pending = PendingNavigation.shared.transactionId
        TabView(selection: $selection) {
            Tab("Dashboard", systemImage: "rectangle.3.group", value: .dashboard) {
                DashboardView()
            }
            Tab("Accounts", systemImage: "creditcard", value: .accounts) {
                AccountsView()
            }
            Tab("Transactions", systemImage: "list.bullet.rectangle", value: .transactions) {
                TransactionsView()
            }
            Tab("Investments", systemImage: "chart.line.uptrend.xyaxis", value: .investments) {
                InvestmentsView()
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
        }
        // initial: true — after Face ID the tab view mounts with the id already set (a tap
        // that launched the app, or one that arrived while locked), and a change-only
        // observer would leave the user on the Dashboard.
        .onChange(of: pending, initial: true) { _, id in if id != nil { selection = .transactions } }
    }
}

#if DEBUG
#Preview {
    RootTabView()
        .modelContainer(PreviewData.container)
}
#endif
