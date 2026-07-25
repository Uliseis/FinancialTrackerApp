import AppIntents

// Logs a manual charge to the account you pick. Runs in the background — captures
// {account, amount, merchant} into QuickAddQueue; the app materializes it on next launch/resume.
// Feeds the Wallet transaction automation, Control Center / Back Tap, and Siri from one intent.
struct AddTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Card Charge"
    static let description = IntentDescription(
        "Logs a charge to a chosen account. In a Wallet automation, map its Amount and Merchant here.")
    static let openAppWhenRun = false

    @Parameter(title: "Account") var account: ManualAccountEntity
    @Parameter(title: "Amount") var amount: String
    @Parameter(title: "Merchant") var merchant: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) at \(\.$merchant) to \(\.$account)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard QuickAddQueue.parseAmount(amount) != nil else {
            return .result(dialog: "Couldn't read an amount from “\(amount)”.")
        }
        let name = merchant?.trimmingCharacters(in: .whitespacesAndNewlines)
        QuickAddQueue.append(PendingQuickAdd(
            accountId: account.id.uuidString,
            amount: amount,
            merchant: (name?.isEmpty == false ? name : nil),
            bookedAt: Date()))
        return .result(dialog: "Logged \(name ?? "charge") · \(amount) to \(account.name).")
    }
}

struct OdysseyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTransactionIntent(),
            phrases: [
                "Log a charge in \(.applicationName)",
                "Add a charge in \(.applicationName)",
            ],
            shortTitle: "Log Charge",
            systemImageName: "creditcard")
    }
}
