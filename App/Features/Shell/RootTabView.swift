import SwiftUI

struct RootTabView: View {
    @State private var selection: AppTab = .initial

    var body: some View {
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
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

#if DEBUG
#Preview {
    RootTabView()
        .modelContainer(PreviewData.container)
}
#endif
