import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "rectangle.3.group") {
                DashboardView()
            }
            Tab("Accounts", systemImage: "creditcard") {
                AccountsView()
            }
            Tab("Transactions", systemImage: "list.bullet.rectangle") {
                TransactionsView()
            }
            Tab("Investments", systemImage: "chart.line.uptrend.xyaxis") {
                InvestmentsView()
            }
            Tab("Connections", systemImage: "link") {
                ConnectionsView()
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
