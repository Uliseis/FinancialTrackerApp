import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

struct BudgetsView: View {
    @Query(sort: [SortDescriptor(\Budget.createdAt, order: .reverse)])
    private var budgets: [Budget]

    @Environment(\.modelContext) private var ctx
    @State private var editing: BudgetEdit?
    @State private var pendingDelete: Budget?
    @State private var confirmingDelete = false

    var body: some View {
        Group {
            List {
                ForEach(budgets) { budget in
                    Button {
                        editing = BudgetEdit(budget)
                    } label: {
                        BudgetRow(budget: budget)
                    }
                    .tint(.primary)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDelete = budget
                            confirmingDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Budgets")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if budgets.isEmpty {
                    ContentUnavailableView("No Budgets", systemImage: "chart.pie",
                                           description: Text("Add a monthly budget for a category."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = BudgetEdit() } label: {
                        Label("Add Budget", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editing, content: BudgetEditView.init)
            #if DEBUG
            .task { if UITestHooks.presentSheet == "budget-edit" { editing = BudgetEdit() } }
            #endif
            .confirmationDialog(
                "Delete this budget?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { budget in
                Button("Delete", role: .destructive) { delete(budget) }
            }
        }
    }

    private func delete(_ budget: Budget) {
        try? CoreLogic.Budgets.delete(budget, in: ctx)
        pendingDelete = nil
    }
}

private struct BudgetRow: View {
    let budget: Budget

    var body: some View {
        HStack(spacing: 12) {
            ColorDot(hex: budget.category?.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(budget.category?.name ?? "Uncategorized")
                Text(budget.period.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !budget.active {
                TagChip(text: "Off")
            }
            MoneyText(amount: budget.amountEur)
        }
        .accessibilityElement(children: .combine)
    }
}

// Identifiable form payload: nil existing ⇒ create, non-nil ⇒ edit.
struct BudgetEdit: Identifiable {
    let id: UUID
    let existing: Budget?
    var categoryId: UUID?
    var amount: Decimal
    var period: BudgetPeriod
    var startsOn: Date
    var active: Bool

    init() {
        id = UUID()
        existing = nil
        categoryId = nil
        amount = 0
        period = .month
        startsOn = .now
        active = true
    }

    init(_ budget: Budget) {
        id = budget.id
        existing = budget
        categoryId = budget.category?.id
        amount = budget.amountEur
        period = budget.period
        startsOn = budget.startsOn
        active = budget.active
    }
}

private struct BudgetEditView: View {
    @State private var edit: BudgetEdit
    @State private var saveError: String?
    @Query(sort: [SortDescriptor(\CoreModel.Category.name)])
    private var categories: [CoreModel.Category]
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    init(edit: BudgetEdit) { _edit = State(initialValue: edit) }

    private var isValid: Bool { edit.categoryId != nil && edit.amount > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Category", selection: $edit.categoryId) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(categories) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    LabeledContent("Amount (EUR)") {
                        TextField("Amount", value: $edit.amount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Period", selection: $edit.period) {
                        ForEach(BudgetPeriod.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    DatePicker("Starts", selection: $edit.startsOn, displayedComponents: .date)
                }
                Section {
                    Toggle("Active", isOn: $edit.active)
                }
            }
            .navigationTitle(edit.existing == nil ? "New Budget" : "Edit Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
            .saveErrorAlert($saveError)
        }
    }

    private func save() {
        guard let category = categories.first(where: { $0.id == edit.categoryId }) else { return }
        do {
            if let existing = edit.existing {
                try CoreLogic.Budgets.update(
                    existing, category: category, amountEur: edit.amount,
                    period: edit.period, startsOn: edit.startsOn, active: edit.active, in: ctx)
            } else {
                try CoreLogic.Budgets.create(
                    category: category, amountEur: edit.amount, period: edit.period,
                    startsOn: edit.startsOn, active: edit.active, in: ctx)
            }
            dismiss()
        } catch {
            saveError = "The budget wasn’t saved."
        }
    }
}

extension BudgetPeriod {
    var label: String {
        switch self {
        case .week: "Weekly"
        case .month: "Monthly"
        case .year: "Yearly"
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { BudgetsView() }
        .modelContainer(PreviewData.container)
}
#endif
