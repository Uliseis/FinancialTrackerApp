import Foundation

// ^[…](inflect: true) only works in string literals (LocalizedStringKey); computed
// message strings need explicit pluralization.
func pluralized(_ count: Int, _ singular: String) -> String {
    "\(count) \(singular)\(count == 1 ? "" : "s")"
}
