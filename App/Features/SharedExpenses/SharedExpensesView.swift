import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

struct SharedExpensesView: View {
    @Query(sort: [SortDescriptor(\SharedExpenseGroup.createdAt, order: .reverse)])
    private var groups: [SharedExpenseGroup]

    @Environment(\.modelContext) private var ctx
    @State private var summaries: [UUID: CoreLogic.SharedExpenses.GroupSummary] = [:]

    // Pushed from SettingsView, which registers the SharedExpenseGroup destination
    // (and handles the shared-detail DEBUG deep-push).
    var body: some View {
        List {
            ForEach(groups) { group in
                NavigationLink(value: group) {
                    GroupRow(group: group, summary: summaries[group.id])
                }
            }
        }
        .navigationTitle("Shared Expenses")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("No Shared Expenses", systemImage: "person.2",
                                       description: Text("Track a shared expense from a transaction."))
            }
        }
        .task { reload() }
        .reloadOnModelChange { reload() }
    }

    private func reload() {
        summaries = (try? CoreLogic.SharedExpenses.netForGroups(groups.map(\.id), in: ctx)) ?? [:]
    }
}

private struct GroupRow: View {
    let group: SharedExpenseGroup
    let summary: CoreLogic.SharedExpenses.GroupSummary?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.label).lineLimit(1)
                Text(group.attributionMonth.formatted(.dateTime.month(.abbreviated).year()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let summary {
                MoneyText(amount: summary.net)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        SharedExpensesView()
            .navigationDestination(for: SharedExpenseGroup.self) { SharedExpenseGroupDetailView(group: $0) }
    }
    .modelContainer(PreviewData.container)
}
#endif
