import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

struct ManageRulesView: View {
    @Query(sort: [SortDescriptor(\CategoryRule.priority, order: .reverse),
                  SortDescriptor(\CategoryRule.createdAt)])
    private var rules: [CategoryRule]

    @Environment(\.modelContext) private var ctx
    @State private var editing: RuleEdit?
    @State private var pendingDelete: CategoryRule?
    @State private var confirmingDelete = false
    @State private var applyMessage = ""
    @State private var showingApplyResult = false

    var body: some View {
        Group {
            List {
                Section {
                    ForEach(rules) { rule in
                        Button {
                            editing = RuleEdit(rule)
                        } label: {
                            RuleRow(rule: rule)
                        }
                        .tint(.primary)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDelete = rule
                                confirmingDelete = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onMove(perform: move)
                } footer: {
                    Text("Higher rules win. Manual categories are never overwritten.")
                }
                if !rules.isEmpty {
                    Section {
                        Button("Apply Rules Now", action: applyRules)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Rules")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if rules.isEmpty {
                    ContentUnavailableView("No Rules", systemImage: "wand.and.stars",
                                           description: Text("Add a rule to auto-categorize transactions."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = RuleEdit() } label: {
                        Label("Add Rule", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editing, content: RuleEditView.init)
            #if DEBUG
            .task { if UITestHooks.presentSheet == "rule-edit" { editing = RuleEdit() } }
            #endif
            .confirmationDialog(
                "Delete this rule?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { rule in
                Button("Delete “\(rule.pattern)”", role: .destructive) { delete(rule) }
            }
            .alert("Rules Applied", isPresented: $showingApplyResult) {} message: {
                Text(applyMessage)
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = rules
        ordered.move(fromOffsets: source, toOffset: destination)
        try? CoreLogic.CategoryRules.reorder(ordered.map(\.id), in: ctx)
    }

    private func delete(_ rule: CategoryRule) {
        try? CoreLogic.CategoryRules.delete(rule, in: ctx)
        pendingDelete = nil
    }

    private func applyRules() {
        let result = (try? CoreLogic.Categorize.applyRulesToTransactions(in: ctx))
            ?? CoreLogic.Categorize.Result(updated: 0, scanned: 0)
        applyMessage = "Categorized \(result.updated) of \(result.scanned) transactions."
        showingApplyResult = true
    }
}

private struct RuleRow: View {
    let rule: CategoryRule

    var body: some View {
        HStack(spacing: 12) {
            ColorDot(hex: rule.category?.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(rule.pattern).lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        "\(rule.field.label) \(rule.matchType.label.lowercased()) → \(rule.category?.name ?? "—")"
    }
}

// Identifiable form payload: nil existing ⇒ create, non-nil ⇒ edit.
struct RuleEdit: Identifiable {
    let id: UUID
    let existing: CategoryRule?
    var pattern: String
    var field: RuleField
    var matchType: RuleMatch
    var categoryId: UUID?

    init() {
        id = UUID()
        existing = nil
        pattern = ""
        field = .description
        matchType = .contains
        categoryId = nil
    }

    init(_ rule: CategoryRule) {
        id = rule.id
        existing = rule
        pattern = rule.pattern
        field = rule.field
        matchType = rule.matchType
        categoryId = rule.category?.id
    }
}

private struct RuleEditView: View {
    @State private var edit: RuleEdit
    @State private var previewCount: Int?
    @State private var saveError: String?
    @Query(sort: [SortDescriptor(\CoreModel.Category.name)])
    private var categories: [CoreModel.Category]
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    init(edit: RuleEdit) { _edit = State(initialValue: edit) }

    private var isValid: Bool {
        !edit.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && edit.categoryId != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Pattern", text: $edit.pattern)
                        .autocorrectionDisabled()
                    Picker("Field", selection: $edit.field) {
                        ForEach(RuleField.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Match", selection: $edit.matchType) {
                        ForEach(RuleMatch.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } footer: {
                    if let previewCount {
                        Text("Matches ^[\(previewCount) transaction](inflect: true).")
                    }
                }
                Section("Category") {
                    Picker("Category", selection: $edit.categoryId) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(categories) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    .labelsHidden()
                }
            }
            .navigationTitle(edit.existing == nil ? "New Rule" : "Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
            .task(id: previewKey) { await refreshPreview() }
            .saveErrorAlert($saveError)
        }
    }

    private var previewKey: String { "\(edit.pattern)|\(edit.field.rawValue)|\(edit.matchType.rawValue)" }

    // Debounced: preview scans every transaction, so don't run it on each keystroke.
    private func refreshPreview() async {
        guard (try? await Task.sleep(for: .milliseconds(300))) != nil else { return }
        previewCount = (try? CoreLogic.Categorize.preview(
            pattern: edit.pattern, field: edit.field, matchType: edit.matchType, in: ctx))?.count
    }

    private func save() {
        guard let category = categories.first(where: { $0.id == edit.categoryId }) else { return }
        do {
            if let existing = edit.existing {
                try CoreLogic.CategoryRules.update(
                    existing, pattern: edit.pattern, category: category,
                    field: edit.field, matchType: edit.matchType, in: ctx)
            } else {
                try CoreLogic.CategoryRules.create(
                    pattern: edit.pattern, category: category,
                    field: edit.field, matchType: edit.matchType,
                    priority: nextPriority(), in: ctx)
            }
            dismiss()
        } catch {
            saveError = "The rule wasn’t saved."
        }
    }

    private func nextPriority() -> Int {
        let all = (try? ctx.fetch(FetchDescriptor<CategoryRule>())) ?? []
        return (all.map(\.priority).max() ?? -1) + 1
    }
}

extension RuleField {
    var label: String {
        switch self {
        case .description: "Description"
        case .counterparty: "Counterparty"
        }
    }
}

extension RuleMatch {
    var label: String {
        switch self {
        case .contains: "Contains"
        case .equals: "Equals"
        case .startsWith: "Starts with"
        case .endsWith: "Ends with"
        case .regex: "Regex"
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { ManageRulesView() }
        .modelContainer(PreviewData.container)
}
#endif
