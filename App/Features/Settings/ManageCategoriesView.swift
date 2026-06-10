import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

struct ManageCategoriesView: View {
    @Query(sort: [SortDescriptor(\CoreModel.Category.name)])
    private var categories: [CoreModel.Category]

    @Environment(\.modelContext) private var ctx
    @State private var editing: CategoryEdit?
    @State private var pendingDelete: CoreModel.Category?
    @State private var confirmingDelete = false

    var body: some View {
        Group {
            List {
                ForEach(categories) { category in
                    Button {
                        editing = CategoryEdit(category)
                    } label: {
                        CategoryManageRow(category: category)
                    }
                    .tint(.primary)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDelete = category
                            confirmingDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if categories.isEmpty {
                    ContentUnavailableView("No Categories", systemImage: "tag",
                                           description: Text("Add a category to classify transactions."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = CategoryEdit() } label: {
                        Label("Add Category", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editing, content: CategoryEditView.init)
            #if DEBUG
            .task { if UITestHooks.presentSheet == "category-edit" { editing = CategoryEdit() } }
            #endif
            .confirmationDialog(
                "Delete this category?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { category in
                Button("Delete \(category.name)", role: .destructive) { delete(category) }
            } message: { _ in
                Text("Transactions in this category become uncategorized and sub-categories detach.")
            }
        }
    }

    private func delete(_ category: CoreModel.Category) {
        try? CoreLogic.Categories.delete(category, in: ctx)
        pendingDelete = nil
    }
}

private struct CategoryManageRow: View {
    let category: CoreModel.Category

    var body: some View {
        HStack(spacing: 12) {
            ColorDot(hex: category.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(category.name)
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
        let kind = (CategoryKind(rawValue: category.kind) ?? .expense).label
        if let parent = category.parent?.name { return "\(kind) · \(parent)" }
        return kind
    }
}

// Identifiable form payload: nil existing ⇒ create, non-nil ⇒ edit.
struct CategoryEdit: Identifiable {
    let id: UUID
    let existing: CoreModel.Category?
    var name: String
    var kind: CategoryKind
    var parentId: UUID?
    var color: String?

    init() {
        id = UUID()
        existing = nil
        name = ""
        kind = .expense
        parentId = nil
        color = ColorSwatchPicker.palette.first
    }

    init(_ category: CoreModel.Category) {
        id = category.id
        existing = category
        name = category.name
        kind = CategoryKind(rawValue: category.kind) ?? .expense
        parentId = category.parent?.id
        color = category.color
    }
}

private struct CategoryEditView: View {
    @State private var edit: CategoryEdit
    @State private var saveError: String?
    @Query(sort: [SortDescriptor(\CoreModel.Category.name)])
    private var categories: [CoreModel.Category]
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    init(edit: CategoryEdit) { _edit = State(initialValue: edit) }

    private var isValid: Bool {
        !edit.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // A category can't be its own parent; descendants are not excluded (parity with the web).
    private var parentOptions: [CoreModel.Category] {
        categories.filter { $0.id != edit.existing?.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $edit.name)
                    Picker("Kind", selection: $edit.kind) {
                        ForEach(CategoryKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Parent", selection: $edit.parentId) {
                        Text("None").tag(UUID?.none)
                        ForEach(parentOptions) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }
                Section("Color") {
                    ColorSwatchPicker(selection: $edit.color)
                }
            }
            .navigationTitle(edit.existing == nil ? "New Category" : "Edit Category")
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
        let parent = categories.first { $0.id == edit.parentId }
        do {
            if let existing = edit.existing {
                try CoreLogic.Categories.update(
                    existing, name: edit.name, kind: edit.kind, parent: parent,
                    color: edit.color, in: ctx)
            } else {
                try CoreLogic.Categories.create(
                    name: edit.name, kind: edit.kind, parent: parent, color: edit.color, in: ctx)
            }
            dismiss()
        } catch CoreLogic.Categories.Error.parentCycle {
            saveError = "That parent is a sub-category of this one — pick another."
        } catch {
            saveError = "The category wasn’t saved."
        }
    }
}

extension CategoryKind {
    var label: String {
        switch self {
        case .expense: "Expense"
        case .income: "Income"
        case .reimbursement: "Reimbursement"
        case .refund: "Refund"
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { ManageCategoriesView() }
        .modelContainer(PreviewData.container)
}
#endif
