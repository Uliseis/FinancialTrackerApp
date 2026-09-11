import Foundation
import CoreLogic

// ponytail: UserDefaults, per-device. Mutes and refusals would need NSUbiquitousKeyValueStore
// the day a second device runs the app; the bookings themselves already sync via CloudKit.
enum AutomationSettings {
    static let recurringEnabledKey = "automation.recurring.enabled"
    static let pensionEnabledKey = "automation.pension.enabled"
    static let pensionSourceKey = "automation.pension.source"
    static let pensionTargetKey = "automation.pension.target"
    static let pensionAmountKey = "automation.pension.amount"
    static let pensionSinceKey = "automation.pension.since"
    private static let mutedKey = "automation.recurring.muted"
    private static let declinedRecurringKey = "automation.recurring.declined"
    private static let declinedSplitsKey = "automation.pension.declinedArrivals"

    private static var defaults: UserDefaults { .standard }

    static var recurringEnabled: Bool { defaults.bool(forKey: recurringEnabledKey) }

    static var muted: Set<String> {
        get { Set(defaults.stringArray(forKey: mutedKey) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: mutedKey) }
    }
    static func mute(_ key: String) { muted.insert(key) }
    static func unmute(_ key: String) { muted.remove(key) }

    static var declinedRecurring: Set<String> {
        get { Set(defaults.stringArray(forKey: declinedRecurringKey) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: declinedRecurringKey) }
    }
    static func declineRecurring(_ externalId: String) { declinedRecurring.insert(externalId) }

    static var declinedSplits: Set<UUID> {
        get { Set((defaults.stringArray(forKey: declinedSplitsKey) ?? []).compactMap(UUID.init(uuidString:))) }
        set { defaults.set(newValue.map(\.uuidString).sorted(), forKey: declinedSplitsKey) }
    }
    static func declineSplit(_ arrivalId: UUID) { declinedSplits.insert(arrivalId) }

    // nil unless the toggle is on and the rule is complete.
    static var splitRule: CoreLogic.Automations.SplitRule? {
        guard defaults.bool(forKey: pensionEnabledKey),
              let source = UUID(uuidString: defaults.string(forKey: pensionSourceKey) ?? ""),
              let target = UUID(uuidString: defaults.string(forKey: pensionTargetKey) ?? ""),
              source != target,
              let amount = CoreLogic.Transactions.parseAmount(defaults.string(forKey: pensionAmountKey) ?? ""),
              amount > 0 else { return nil }
        let since = defaults.double(forKey: pensionSinceKey)
        return .init(sourceAccountId: source, targetAccountId: target, amountEur: amount,
                     since: since > 0 ? Date(timeIntervalSince1970: since) : .distantPast)
    }
}
