import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

// The mirror of SharedExpenseCreateView: start from an incoming payment and pick the
// expenses it covers. The running total is the whole point of the screen — the group is
// only valid once the selected expenses add up to at least the income, so the coverage
// bar stays pinned while you search and select.
struct MatchIncomeView: View {
    let incomeTx: CoreModel.Transaction
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var search = ""
    @State private var selected: Set<UUID> = []
    @State private var candidates: [CoreLogic.SharedExpenses.CandidateRefundedExpense] = []
    @State private var errorMessage = ""
    @State private var showingError = false

    private var incomeAmount: Decimal { abs(incomeTx.amountEur ?? incomeTx.amount) }

    private var selectedTotal: Decimal {
        candidates
            .filter { selected.contains($0.id) }
            .reduce(Decimal(0)) { $0 + abs($1.amountEur ?? 0) }
    }

    private var covers: Bool { selectedTotal >= incomeAmount }
    private var remaining: Decimal { max(0, incomeAmount - selectedTotal) }

    private var isValid: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selected.isEmpty && covers
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Label") {
                    TextField("e.g. Dinner refund", text: $label)
                }
                Section("Expenses this covers") {
                    if candidates.isEmpty {
                        ContentUnavailableView(
                            search.isEmpty ? "No Nearby Expenses" : "No Matches",
                            systemImage: "magnifyingglass",
                            description: Text(search.isEmpty
                                ? "No expenses within \(CoreLogic.SharedExpenses.reimbursementWindowDays) days of this payment."
                                : "Nothing matches “\(search)”.")
                        )
                        .listRowBackground(Color.clear)
                    }
                    ForEach(candidates, id: \.id) { candidate in
                        let taken = candidate.sharedExpenseGroupId != nil
                        Button { toggle(candidate.id) } label: {
                            ExpenseCandidateRow(
                                candidate: candidate,
                                selected: selected.contains(candidate.id),
                                alreadyMatched: taken)
                        }
                        .tint(.primary)
                        .disabled(taken)
                    }
                }
            }
            .searchable(text: $search, prompt: "Search expenses")
            .safeAreaInset(edge: .bottom) { coverageBar }
            .navigationTitle("Match Income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Match") { create() }.disabled(!isValid)
                }
            }
            .task { label = defaultLabel }
            .task(id: search) { reloadCandidates() }
            .alert("Couldn’t Match", isPresented: $showingError) {} message: {
                Text(errorMessage)
            }
        }
    }

    private var coverageBar: some View {
        VStack(spacing: Theme.Space.s) {
            HStack {
                Text("Income")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Money.format(incomeAmount, currency: "EUR"))
                    .font(.subheadline.monospacedDigit())
                    .fontDesign(.rounded)
            }
            HStack {
                Text("^[\(selected.count) expense](inflect: true) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Money.format(selectedTotal, currency: "EUR"))
                    .font(.subheadline.monospacedDigit())
                    .fontDesign(.rounded)
                    .foregroundStyle(covers ? Color.positiveAmount : .secondary)
            }
            ProgressView(
                value: Double(truncating: min(selectedTotal, incomeAmount) as NSDecimalNumber),
                total: Double(truncating: max(incomeAmount, 1) as NSDecimalNumber)
            )
            .tint(covers ? Color.positiveAmount : Color.brand)
            Text(covers
                 ? "Nets to \(Money.format(selectedTotal - incomeAmount, currency: "EUR")) still spent"
                 : "\(Money.format(remaining, currency: "EUR")) more needed to cover this income")
                .font(.caption)
                .foregroundStyle(covers ? Color.positiveAmount : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.card))
        .padding(.horizontal, Theme.Space.m)
        .padding(.bottom, Theme.Space.s)
        .animation(.snappy, value: selectedTotal)
        .accessibilityElement(children: .combine)
    }

    private var defaultLabel: String {
        incomeTx.transactionDescription ?? incomeTx.counterparty ?? ""
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    // Keeps already-selected rows in the list even when the query no longer matches them,
    // so searching for a second expense can't silently drop the first.
    private func reloadCandidates() {
        let fresh = (try? CoreLogic.SharedExpenses.findCandidateRefundedExpenses(
            creditTxId: incomeTx.id, query: search, in: ctx)) ?? []
        let freshIds = Set(fresh.map(\.id))
        let pinned = candidates.filter { selected.contains($0.id) && !freshIds.contains($0.id) }
        candidates = pinned + fresh
    }

    private func create() {
        do {
            try CoreLogic.SharedExpenses.createGroupFromCredit(
                .init(label: label, creditTxId: incomeTx.id, expenseTxIds: Array(selected)),
                in: ctx)
            dismiss()
        } catch {
            errorMessage = SharedExpenseMessages.describe(error)
            showingError = true
        }
    }
}

private struct ExpenseCandidateRow: View {
    let candidate: CoreLogic.SharedExpenses.CandidateRefundedExpense
    let selected: Bool
    let alreadyMatched: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.description ?? candidate.counterparty ?? "—").lineLimit(1)
                HStack(spacing: 6) {
                    Text(candidate.bookedAt.formatted(
                        .dateTime.day().month(.abbreviated).year(.twoDigits)))
                    if alreadyMatched {
                        Text("· already matched")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let eur = candidate.amountEur {
                MoneyText(amount: eur)
            }
        }
        .opacity(alreadyMatched ? 0.45 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

#if DEBUG
#Preview {
    MatchIncomeView(incomeTx: PreviewData.sampleTransaction)
        .modelContainer(PreviewData.container)
}
#endif
