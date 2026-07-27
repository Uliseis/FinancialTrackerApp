import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

// An investment account is two independent numbers: what it's worth (a snapshot, or a live
// feed) and what you put in (an opening figure plus every transfer since). Keeping them apart
// is what stops a deposit from reading as a loss.
struct RecordValuationView: View {
    let account: Account
    @Query(sort: [SortDescriptor(\PortfolioValuation.asOf, order: .reverse)])
    private var allValuations: [PortfolioValuation]
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var marketText = ""
    @State private var cashText = ""
    @State private var asOf = Date.now
    @State private var basisText = ""
    @State private var basisAt = Date.now
    @State private var source = LiveSource.manual
    @State private var coinText = "bitcoin"
    @State private var quantityText = ""
    @State private var saveError: String?
    @State private var loaded = false

    enum LiveSource: String, CaseIterable, Identifiable {
        case manual, trading212, crypto
        var id: String { rawValue }
        var label: String {
            switch self {
            case .manual: "Enter by hand"
            case .trading212: "Trading 212"
            case .crypto: "Crypto price"
            }
        }
    }

    private var history: [PortfolioValuation] {
        allValuations.filter { $0.account?.id == account.id }
    }
    private var latest: PortfolioValuation? { history.first }

    private var market: Decimal? { CoreLogic.Transactions.parseAmount(marketText) }
    private var cash: Decimal? { optionalAmount(cashText) }
    private var basis: Decimal? { optionalAmount(basisText) }
    // Not optionalAmount: a holding has more than two decimals.
    private var quantity: Decimal? {
        quantityText.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil : CoreLogic.Transactions.parseQuantity(quantityText)
    }

    private func optionalAmount(_ text: String) -> Decimal? {
        text.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil : CoreLogic.Transactions.parseAmount(text)
    }

    private var metrics: CoreLogic.Investments.AccountMetrics? {
        try? CoreLogic.Investments.loadMetrics(for: [account], in: ctx)[account.id]
    }

    private var repeatSuggestion: CoreLogic.Transfers.RepeatSuggestion? {
        try? CoreLogic.Transfers.lastInternalTransfer(into: account, in: ctx)
    }

    var body: some View {
        NavigationStack {
            Form {
                valueSection
                topUpSection
                costBasisSection
                liveSourceSection
                historySection
            }
            .navigationTitle(account.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .saveErrorAlert($saveError)
            .task { loadExisting() }
        }
    }

    @ViewBuilder
    private var valueSection: some View {
        Section {
            LabeledContent("Market value") {
                TextField(source == .manual ? "0" : "Fetched automatically", text: $marketText)
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
            if let m = metrics, m.contributionsSinceValueEur != 0 {
                LabeledContent("Paid in since this reading") {
                    MoneyText(amount: m.contributionsSinceValueEur)
                }
            }
        } header: {
            Text("What it's worth")
        } footer: {
            Text("Positions and cash as your broker shows them. Money transferred in after this date is added on top automatically, so this figure only has to keep up with the market. Recording twice on the same day replaces the earlier entry.")
        }
    }

    // An account fed by hand from another one — a pension wrapper topped up from the broker's
    // cash — gets its recurring move as a single tap, taken from the last one made.
    @ViewBuilder
    private var topUpSection: some View {
        if let suggestion = repeatSuggestion {
            Section {
                Button {
                    repeat_(suggestion)
                } label: {
                    LabeledContent {
                        Text(Money.format(suggestion.amountEur, currency: "EUR"))
                            .font(.readout(.body))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Top Up Again", systemImage: "arrow.trianglehead.2.clockwise")
                            Text("from \(suggestion.sourceName)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Books the same move again, dated today. Last one \(suggestion.lastBookedAt.formatted(date: .abbreviated, time: .omitted)).")
            }
        }
    }

    @ViewBuilder
    private var costBasisSection: some View {
        Section {
            LabeledContent("Already in") {
                TextField("Optional", text: $basisText)
                    .multilineTextAlignment(.trailing)
                    .font(.readout(.body, weight: .regular))
                    .keyboardType(.decimalPad)
            }
            DatePicker("On", selection: $basisAt, displayedComponents: .date)
            if let m = metrics, let cost = m.costBasisEur {
                LabeledContent("Still invested") { MoneyText(amount: cost) }
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("What you paid in")
        } footer: {
            Text("Set this once: what the account already held on that date. Every transfer booked afterwards is counted for you, so paying money in never shows up as a loss.")
        }

        // Only meaningful once something has come back out — a fund account that has never
        // paid a distribution would just show three zeros.
        if let m = metrics, m.distributionsEur != 0 || m.capitalReturnedEur != 0 {
            Section {
                if m.distributionsEur != 0 {
                    LabeledContent("Income received") { MoneyText(amount: m.distributionsEur) }
                }
                if m.capitalReturnedEur != 0 {
                    LabeledContent("Capital returned") { MoneyText(amount: m.capitalReturnedEur) }
                }
                if let total = m.totalReturnEur {
                    LabeledContent("Total return") {
                        Text(signed(total, pct: m.totalReturnPct))
                            .font(.readout(.body))
                            .foregroundStyle(Theme.amountColor(total))
                    }
                }
            } header: {
                Text("What it's given back")
            } footer: {
                Text("Value today, plus everything paid out and handed back, less what went in. Money out counts as income when you categorise it as income — rent or dividends — and as capital returned otherwise.")
            }
        }
    }

    private func signed(_ amount: Decimal, pct: Decimal?) -> String {
        let text = Money.format(amount, currency: "EUR")
        let base = amount > 0 ? "+\(text)" : text
        guard let pct else { return base }
        return "\(base)  (\(pct.formatted(.percent.precision(.fractionLength(1)))))"
    }

    @ViewBuilder
    private var liveSourceSection: some View {
        Section {
            Picker("Value source", selection: $source) {
                ForEach(LiveSource.allCases) { Text($0.label).tag($0) }
            }
            if source == .crypto {
                LabeledContent("Coin") {
                    TextField("bitcoin", text: $coinText)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                LabeledContent("Quantity held") {
                    TextField("0", text: $quantityText)
                        .multilineTextAlignment(.trailing)
                        .font(.readout(.body, weight: .regular))
                        .keyboardType(.decimalPad)
                }
            }
        } footer: {
            switch source {
            case .manual:
                Text("You'll enter the value yourself whenever you want to update it.")
            case .trading212:
                Text("Refreshed from Trading 212 each time you open the app. Add your API key in Settings → Trading 212.")
            case .crypto:
                Text("Value = quantity × today's price, refreshed when you open the app. Use the CoinGecko id, e.g. bitcoin or ethereum. Update the quantity whenever you buy or sell.")
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !history.isEmpty {
            Section {
                ForEach(history) { v in
                    LabeledContent {
                        Text(Money.format(v.marketValueEur, currency: "EUR"))
                            .font(.readout(.body, weight: .regular))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(v.asOf.formatted(date: .abbreviated, time: .omitted))
                            if let note = v.notes, note.hasPrefix("auto:") {
                                Text("automatic").font(.caption).foregroundStyle(.secondary)
                            } else if let cash = v.cashValueEur, cash != 0 {
                                Text("incl. \(Money.format(cash, currency: "EUR")) cash")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(v) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("History")
            } footer: {
                Text("Readings of what the account was worth. Deleting one doesn't affect what you've paid in.")
            }
        }
    }

    private func loadExisting() {
        guard !loaded else { return }
        loaded = true
        if let opening = account.costBasisOpeningEur {
            basisText = decimalField(opening)
            basisAt = account.costBasisOpeningAt ?? .now
        }
        if let live = account.liveValueSource {
            if live == CoreLogic.InvestmentRefresh.trading212Source {
                source = .trading212
            } else if let coin = CoreLogic.InvestmentRefresh.coinId(from: live) {
                source = .crypto
                coinText = coin
            }
        }
        if let qty = account.assetQuantity { quantityText = decimalField(qty) }
    }

    // Plain "1234.56" for a text field: the display formatter's grouping separators would
    // have to be parsed back out again.
    private func decimalField(_ value: Decimal) -> String {
        "\(value)"
    }

    private func repeat_(_ suggestion: CoreLogic.Transfers.RepeatSuggestion) {
        // #Predicate can't reach through a struct property; bind it first.
        let sourceId = suggestion.sourceId
        guard let source = try? ctx.fetch(FetchDescriptor<Account>(
            predicate: #Predicate { $0.id == sourceId })).first else {
            saveError = "That account is no longer available."
            return
        }
        do {
            try CoreLogic.Transfers.createInternalTransfer(
                from: source, to: account, amountEur: suggestion.amountEur, in: ctx)
            dismiss()
        } catch {
            saveError = "The top-up wasn’t saved."
        }
    }

    private func delete(_ valuation: PortfolioValuation) {
        do { try CoreLogic.Investments.deleteValuation(valuation, in: ctx) }
        catch { saveError = "The reading wasn’t deleted." }
    }

    private func save() {
        do {
            try CoreLogic.Investments.setCostBasisOpening(
                account, amountEur: basis, at: basisAt, in: ctx)
            let liveSource: String? = switch source {
            case .manual: nil
            case .trading212: CoreLogic.InvestmentRefresh.trading212Source
            case .crypto: CoreLogic.InvestmentRefresh.cryptoPrefix
                + coinText.trimmingCharacters(in: .whitespaces).lowercased()
            }
            try CoreLogic.Investments.setLiveSource(
                account, source: liveSource, quantity: quantity, in: ctx)
            if let market {
                try CoreLogic.Investments.recordValuation(
                    account: account, marketValueEur: market, cashValueEur: cash,
                    asOf: asOf, in: ctx)
            }
            dismiss()
        } catch {
            saveError = "The changes weren’t saved."
        }
    }
}

#if DEBUG
#Preview {
    RecordValuationView(account: PreviewData.sampleAccount)
        .modelContainer(PreviewData.container)
}
#endif
