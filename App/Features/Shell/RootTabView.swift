import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Accounts", systemImage: "creditcard") {
                AccountsView()
            }
            Tab("Transactions", systemImage: "list.bullet.rectangle") {
                TransactionsView()
            }
            Tab("Investments", systemImage: "chart.line.uptrend.xyaxis") {
                PlaceholderView(title: "Investments", systemImage: "chart.line.uptrend.xyaxis")
            }
            Tab("Connections", systemImage: "link") {
                PlaceholderView(title: "Connections", systemImage: "link")
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
