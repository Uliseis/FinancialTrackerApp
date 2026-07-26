import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

// Records today's value for an investment account. Snapshots are the only investment data
// the app keeps, so without this the numbers age silently — money paid in after the last
// snapshot never appears.
struct RecordValuationView: View {
    let account: Account
    @Query(sort: [SortDescriptor(\PortfolioValuation.asOf, order: .reverse)])
    private var allValuations: [PortfolioValuation]
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var marketText = ""
    @State private var cashText = ""
    @State private var asOf = Date.now
    @State private var saveError: String?

    private var latest: PortfolioValuation? {
        allValuations.first { $0.account?.id == account.id }
    }

    private var market: Decimal? { CoreLogic.Transactions.parseAmount(marketText) }
    private var cash: Decimal? {
        cashText.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil : CoreLogic.Transactions.parseAmount(cashText)
    }
    private var isValid: Bool { market != nil }

    // What's come in since the last snapshot — the amount most likely missing from the
    // figure currently on screen.
    private var contributedSinceLatest: Decimal {
        guard let since = latest?.asOf else { return 0 }
        return account.transactions
            .filter { $0.bookedAt > since }
            .reduce(Decimal(0)) { $0 + ($1.amountEur ?? 0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Market value") {
                        TextField("0", text: $marketText)
                            .multilineTextAlignment(.trailing)
                            .font(.readout(.title3))
                            .keyboardType(.decimalPad)
                    }
                    LabeledContent("Cash") {
                        TextField("Optional", text: $cashText)
                            .multilineTextAlignment(.trailing)
                            .font(.readout(.body, weight: .regular))
                            .keyboardType(.decimalPad)
                    }
                    DatePicker("As of", selection: $asOf, displayedComponents: .date)
                } header: {
                    Text("Value in EUR")
                } footer: {
                    Text("Positions and cash as your broker shows them today. Recording twice on the same day replaces the earlier entry.")
                }

                if let latest {
                    Section("Last recorded") {
                        LabeledContent(
                            latest.asOf.formatted(date: .abbreviated, time: .omitted),
                            value: Money.format(latest.marketValueEur, currency: "EUR"))
                        if let cash = latest.cashValueEur, cash != 0 {
                            LabeledContent("Cash", value: Money.format(cash, currency: "EUR"))
                        }
                        if contributedSinceLatest != 0 {
                            LabeledContent("Paid in since") {
                                MoneyText(amount: contributedSinceLatest)
                            }
                        }
                    }
                }
            }
            .navigationTitle(account.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
            .saveErrorAlert($saveError)
        }
    }

    private func save() {
        guard let market else { return }
        do {
            try CoreLogic.Investments.recordValuation(
                account: account, marketValueEur: market, cashValueEur: cash,
                asOf: asOf, in: ctx)
            dismiss()
        } catch {
            saveError = "The valuation wasn’t saved."
        }
    }
}

#if DEBUG
#Preview {
    RecordValuationView(account: PreviewData.sampleAccount)
        .modelContainer(PreviewData.container)
}
#endif
