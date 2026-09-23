import Foundation
import SwiftData
import SwiftUI
import UserNotifications
import CoreModel
import CoreLogic
import CoreSync

// Runs after every bank sync (foreground and BGProcessingTask). Books what is due, then
// tells the user with an actionable notification so the answer is a tap on the banner,
// not a trip through the app. Rows are saved on the observed main context, so CloudKit
// push rides the same SaveObserver as any user edit.
enum AutomationRunner {
    @MainActor
    static func run(_ ctx: ModelContext) async {
        if AutomationSettings.recurringEnabled {
            let booked = (try? CoreLogic.Automations.bookDueRecurring(
                in: ctx, muted: AutomationSettings.muted, declined: AutomationSettings.declinedRecurring,
                pins: AutomationSettings.pins)) ?? []
            for b in booked { await AutomationNotifications.recurringBooked(b) }
        }
        if let rule = AutomationSettings.splitRule {
            let splits = (try? CoreLogic.Automations.bookSplits(
                rule: rule, in: ctx, declined: AutomationSettings.declinedSplits)) ?? []
            for s in splits { await AutomationNotifications.splitBooked(s) }
        }
    }
}

enum AutomationNotifications {
    static let recurringCategory = "RECURRING_BOOKED"
    static let splitCategory = "PENSION_SPLIT"
    static let keepAction = "KEEP"
    static let deleteAction = "DELETE"
    static let stopAction = "STOP"
    static let undoAction = "UNDO"

    static func registerCategories() {
        let keep = UNNotificationAction(identifier: keepAction, title: "Keep")
        let delete = UNNotificationAction(identifier: deleteAction, title: "Delete", options: [.destructive])
        let stop = UNNotificationAction(identifier: stopAction, title: "Stop This Subscription", options: [.destructive])
        let undo = UNNotificationAction(identifier: undoAction, title: "Undo", options: [.destructive])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: recurringCategory, actions: [keep, delete, stop], intentIdentifiers: []),
            UNNotificationCategory(identifier: splitCategory, actions: [keep, undo], intentIdentifiers: []),
        ])
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func recurringBooked(_ b: CoreLogic.Automations.BookedRecurring) async {
        let content = UNMutableNotificationContent()
        content.title = "Booked \(b.merchant)"
        content.body = "\(Money.format(b.amount, currency: b.currency)) on \(b.accountName). Not charged this month? Delete it, or stop the subscription."
        content.categoryIdentifier = recurringCategory
        content.sound = .default
        content.userInfo = ["txId": b.transactionId.uuidString, "externalId": b.externalId, "key": b.key]
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "recurring-\(b.transactionId.uuidString)", content: content, trigger: nil))
    }

    static func splitBooked(_ s: CoreLogic.Automations.BookedSplit) async {
        let content = UNMutableNotificationContent()
        content.title = "Pension split booked"
        content.body = "\(Money.format(s.amountEur, currency: "EUR")) moved to the pension for the \(Money.format(s.arrivedEur, currency: "EUR")) transfer of \(s.arrivedAt.formatted(.dateTime.day().month())). Undo if this one didn’t go to the pension."
        content.categoryIdentifier = splitCategory
        content.sound = .default
        content.userInfo = ["debitTxId": s.debitTxId.uuidString]
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "split-\(s.debitTxId.uuidString)", content: content, trigger: nil))
    }
}

// Where a notification tap should land. RootTabView switches tabs, TransactionsView pushes.
@MainActor @Observable
final class PendingNavigation {
    static let shared = PendingNavigation()
    var transactionId: UUID?
}

final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate {
    nonisolated(unsafe) static let shared = NotificationResponder()
    var container: ModelContainer?
    var engine: CloudKitSyncEngine?

    // Completion-handler variants on purpose: the async ones resume on the cooperative pool
    // and UIKit asserts (SIGABRT in _updateSnapshotAndStateRestoration) when the completion
    // is called off the main thread. Crashed on the first real tap, 2026-09-11.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let txId = (info["txId"] as? String).flatMap(UUID.init(uuidString:))
        let debitId = (info["debitTxId"] as? String).flatMap(UUID.init(uuidString:))
        let externalId = info["externalId"] as? String
        let key = info["key"] as? String
        Task { @MainActor in
            Self.handle(action: action, txId: txId, debitId: debitId, externalId: externalId, key: key)
            await Self.shared.engine?.sendPendingChanges()
            completionHandler()
        }
    }

    @MainActor
    private static func handle(action: String, txId: UUID?, debitId: UUID?, externalId: String?, key: String?) {
        guard let container = shared.container else { return }
        // An action can launch the app in the background before RootView's task has
        // started the engine; start it here so the SaveObserver sees these writes.
        if let engine = shared.engine, !engine.isRunning, CloudKitGate.isAvailable { try? engine.start() }
        let ctx = container.mainContext
        switch action {
        case AutomationNotifications.deleteAction, AutomationNotifications.stopAction:
            if action == AutomationNotifications.stopAction, let key { AutomationSettings.mute(key) }
            if let externalId { AutomationSettings.declineRecurring(externalId) }
            if let txId, let tx = transaction(txId, in: ctx) {
                try? CoreLogic.Transactions.delete(tx, in: ctx)
            }
        case AutomationNotifications.undoAction:
            if let debitId, let arrival = try? CoreLogic.Automations.undoSplit(debitTxId: debitId, in: ctx) {
                AutomationSettings.declineSplit(arrival)
            }
        case UNNotificationDefaultActionIdentifier:
            PendingNavigation.shared.transactionId = txId ?? debitId
        default:
            break
        }
    }

    @MainActor
    private static func transaction(_ id: UUID, in ctx: ModelContext) -> CoreModel.Transaction? {
        (try? ctx.fetch(FetchDescriptor<CoreModel.Transaction>(predicate: #Predicate { $0.id == id })))?.first
    }
}
