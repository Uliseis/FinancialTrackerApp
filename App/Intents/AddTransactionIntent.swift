import AppIntents

// Logs a Revolut credit-card charge (not pulled by Enable Banking). Runs in the background —
// captures amount + merchant into QuickAddQueue; the app materializes it on next launch.
// Feeds the Wallet transaction automation, Control Center / Back Tap, and Siri from one intent.
struct AddTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Card Charge"
    static let description = IntentDescription(
        "Logs a charge to your Revolut credit card. Map the Wallet automation's Amount and Merchant here.")
    static let openAppWhenRun = false

    @Parameter(title: "Amount") var amount: String
    @Parameter(title: "Merchant") var merchant: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) at \(\.$merchant)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard QuickAddQueue.parseAmount(amount) != nil else {
            return .result(dialog: "Couldn't read an amount from “\(amount)”.")
        }
        let name = merchant?.trimmingCharacters(in: .whitespacesAndNewlines)
        QuickAddQueue.append(PendingQuickAdd(
            amount: amount, merchant: (name?.isEmpty == false ? name : nil), bookedAt: Date()))
        return .result(dialog: "Logged \(name ?? "charge") · \(amount) to Revolut CC.")
    }
}

struct OdysseyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTransactionIntent(),
            phrases: [
                "Log a charge in \(.applicationName)",
                "Add a Revolut charge in \(.applicationName)",
            ],
            shortTitle: "Log Charge",
            systemImageName: "creditcard")
    }
}
