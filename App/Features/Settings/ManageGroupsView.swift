import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

struct ManageGroupsView: View {
    @Query(sort: [SortDescriptor(\AccountGroup.sortOrder),
                  SortDescriptor(\AccountGroup.name)])
    private var groups: [AccountGroup]

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var editing: GroupEdit?
    @State private var pendingDelete: AccountGroup?
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups) { group in
                    Button {
                        editing = GroupEdit(group)
                    } label: {
                        GroupRow(group: group)
                    }
                    .tint(.primary)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDelete = group
                            confirmingDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onMove(perform: move)
            }
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if groups.isEmpty {
                    ContentUnavailableView("No Groups", systemImage: "square.stack.3d.up",
                                           description: Text("Add a group to organize accounts."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = GroupEdit() } label: {
                        Label("Add Group", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editing, content: GroupEditView.init)
            #if DEBUG
            .task { if UITestHooks.presentSheet == "group-edit" { editing = GroupEdit() } }
            #endif
            .confirmationDialog(
                "Delete this group?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { group in
                Button("Delete \(group.name)", role: .destructive) { delete(group) }
            } message: { _ in
                Text("Accounts in this group become ungrouped.")
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = groups
        ordered.move(fromOffsets: source, toOffset: destination)
        try? CoreLogic.AccountGroups.reorder(ordered.map(\.id), in: ctx)
    }

    private func delete(_ group: AccountGroup) {
        try? CoreLogic.AccountGroups.delete(group, in: ctx)
        pendingDelete = nil
    }
}

private struct GroupRow: View {
    let group: AccountGroup

    var body: some View {
        HStack(spacing: 12) {
            ColorDot(hex: group.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.name)
                Text(group.kind.label)
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
}

// Identifiable form payload: nil existing ⇒ create, non-nil ⇒ edit.
struct GroupEdit: Identifiable {
    let id: UUID
    let existing: AccountGroup?
    var name: String
    var kind: AccountGroupKind
    var color: String?

    init() {
        id = UUID()
        existing = nil
        name = ""
        kind = .other
        color = ColorSwatchPicker.palette.first
    }

    init(_ group: AccountGroup) {
        id = group.id
        existing = group
        name = group.name
        kind = group.kind
        color = group.color
    }
}

private struct GroupEditView: View {
    @State private var edit: GroupEdit
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    init(edit: GroupEdit) { _edit = State(initialValue: edit) }

    private var isValid: Bool {
        !edit.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $edit.name)
                    Picker("Kind", selection: $edit.kind) {
                        ForEach(AccountGroupKind.allCases, id: \.self) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                }
                Section("Color") {
                    ColorSwatchPicker(selection: $edit.color)
                }
            }
            .navigationTitle(edit.existing == nil ? "New Group" : "Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        if let existing = edit.existing {
            try? CoreLogic.AccountGroups.update(
                existing, name: edit.name, kind: edit.kind, color: edit.color, in: ctx)
        } else {
            try? CoreLogic.AccountGroups.create(
                name: edit.name, kind: edit.kind, color: edit.color,
                sortOrder: nextSortOrder(), in: ctx)
        }
        dismiss()
    }

    private func nextSortOrder() -> Int {
        let all = (try? ctx.fetch(FetchDescriptor<AccountGroup>())) ?? []
        return (all.map(\.sortOrder).max() ?? -1) + 1
    }
}

extension AccountGroupKind {
    var label: String {
        switch self {
        case .cash: "Cash"
        case .savings: "Savings"
        case .investment: "Investment"
        case .credit: "Credit"
        case .other: "Other"
        }
    }
}

#if DEBUG
#Preview {
    ManageGroupsView()
        .modelContainer(PreviewData.container)
}
#endif
