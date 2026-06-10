import Foundation

// "Require Face ID" preference. Defaults to ON — UserDefaults' false default inverts
// the semantics, so nil must read as true.
enum SecuritySettings {
    static let requireUnlockKey = "requireUnlock"

    static var requireUnlock: Bool {
        UserDefaults.standard.object(forKey: requireUnlockKey) as? Bool ?? true
    }
}
