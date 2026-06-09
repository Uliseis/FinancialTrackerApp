import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

struct ManageSpacesView: View {
    @Query(sort: [SortDescriptor(\AccountSpace.sortOrder),
                  SortDescriptor(\AccountSpace.createdAt)])
    private var spaces: [AccountSpace]

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var editing: SpaceEdit?
    @State private var pendingDelete: AccountSpace?
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(spaces) { space in
                    Button {
                        editing = SpaceEdit(space)
                    } label: {
                        SpaceRow(space: space)
                    }
                    .tint(.primary)
                    .swipeActions(edge: .trailing) {
                        if !space.isDefault {
                            Button(role: .destructive) {
                                pendingDelete = space
                                confirmingDelete = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .onMove(perform: move)
            }
            .navigationTitle("Spaces")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = SpaceEdit() } label: {
                        Label("Add Space", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editing, content: SpaceEditView.init)
            #if DEBUG
            .task { if UITestHooks.presentSheet == "space-edit" { editing = SpaceEdit() } }
            #endif
            .confirmationDialog(
                "Delete this space?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { space in
                Button("Delete \(space.name)", role: .destructive) { delete(space) }
            } message: { _ in
                Text("Accounts in this space move to the default space.")
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = spaces
        ordered.move(fromOffsets: source, toOffset: destination)
        try? CoreLogic.Spaces.reorder(ordered.map(\.id), in: ctx)
    }

    private func delete(_ space: AccountSpace) {
        try? CoreLogic.Spaces.delete(space, in: ctx)
        pendingDelete = nil
    }
}

private struct SpaceEditView: View {
    @State private var edit: SpaceEdit
    @State private var saveError: String?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    init(edit: SpaceEdit) { _edit = State(initialValue: edit) }

    private var isValid: Bool {
        !edit.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $edit.name)
                }
                Section("Color") {
                    ColorSwatchPicker(selection: $edit.color)
                }
                if edit.existing == nil || !edit.existing!.isDefault {
                    Section {
                        Toggle("Default space", isOn: $edit.isDefault)
                    } footer: {
                        Text("New accounts and space-less accounts belong to the default space.")
                    }
                }
            }
            .navigationTitle(edit.existing == nil ? "New Space" : "Edit Space")
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
        do {
            let space: AccountSpace
            if let existing = edit.existing {
                try CoreLogic.Spaces.update(existing, name: edit.name, color: edit.color, in: ctx)
                space = existing
            } else {
                space = try CoreLogic.Spaces.create(
                    name: edit.name, color: edit.color,
                    sortOrder: nextSortOrder(), in: ctx)
            }
            if edit.isDefault && !space.isDefault {
                try CoreLogic.Spaces.setDefault(space, in: ctx)
            }
            dismiss()
        } catch {
            saveError = "The space wasn’t saved."
        }
    }

    private func nextSortOrder() -> Int {
        let all = (try? ctx.fetch(FetchDescriptor<AccountSpace>())) ?? []
        return (all.map(\.sortOrder).max() ?? -1) + 1
    }
}

private struct SpaceRow: View {
    let space: AccountSpace

    var body: some View {
        HStack(spacing: 12) {
            ColorDot(hex: space.color)
            Text(space.name)
            if space.isDefault {
                TagChip(text: "Default")
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
    }
}

// Identifiable form payload: nil id ⇒ create, non-nil ⇒ edit an existing space.
struct SpaceEdit: Identifiable {
    let id: UUID
    let existing: AccountSpace?
    var name: String
    var color: String?
    var isDefault: Bool

    init() {
        id = UUID()
        existing = nil
        name = ""
        color = ColorSwatchPicker.palette.first
        isDefault = false
    }

    init(_ space: AccountSpace) {
        id = space.id
        existing = space
        name = space.name
        color = space.color
        isDefault = space.isDefault
    }
}

#if DEBUG
#Preview {
    ManageSpacesView()
        .modelContainer(PreviewData.container)
}
#endif
