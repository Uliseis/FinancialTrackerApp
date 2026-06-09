import Foundation

enum AppTab: String, CaseIterable {
    case dashboard, accounts, transactions, investments, connections

    static var initial: AppTab {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["UITEST_TAB"],
           let tab = AppTab(rawValue: raw) {
            return tab
        }
        #endif
        return .dashboard
    }
}
