import Foundation

enum Money {
    static func format(_ amount: Decimal, currency: String) -> String {
        amount.formatted(.currency(code: currency))
    }
}
