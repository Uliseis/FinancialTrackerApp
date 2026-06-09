import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

struct ManageTransferRoutesView: View {
    @Query(sort: [SortDescriptor(\TransferRoute.priority, order: .reverse),
                  SortDescriptor(\TransferRoute.createdAt)])
    private var routes: [TransferRoute]

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var editing: RouteEdit?
    @State private var pendingDelete: TransferRoute?
    @State private var confirmingDelete = false
    @State private var resultMessage = ""
    @State private var showingResult = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(routes) { route in
                        Button {
                            editing = RouteEdit(route)
                        } label: {
                            RouteRow(route: route)
                        }
                        .tint(.primary)
                        .swipeActions(edge: .leading) {
                            Button {
                                backfill(route)
                            } label: {
                                Label("Backfill", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDelete = route
                                confirmingDelete = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onMove(perform: move)
                } footer: {
                    Text("Routes mirror a matching transaction into the target account, forming a transfer pair. Higher routes win.")
                }
            }
            .navigationTitle("Transfer Routes")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if routes.isEmpty {
                    ContentUnavailableView("No Transfer Routes", systemImage: "arrow.triangle.branch",
                                           description: Text("Add a route to auto-pair transfers into another account."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = RouteEdit() } label: {
                        Label("Add Route", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editing) { edit in
                TransferRouteEditView(edit: edit) { message in
                    resultMessage = message
                    showingResult = true
                }
            }
            #if DEBUG
            .task { if UITestHooks.presentSheet == "route-edit" { editing = RouteEdit() } }
            #endif
            .confirmationDialog(
                "Delete this route?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { route in
                Button("Delete “\(route.pattern)”", role: .destructive) { delete(route) }
            } message: { _ in
                Text("Mirror transactions created by this route are removed.")
            }
            .alert("Transfer Routes", isPresented: $showingResult) {} message: {
                Text(resultMessage)
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = routes
        ordered.move(fromOffsets: source, toOffset: destination)
        try? CoreLogic.TransferRoutes.reorderRoutes(ordered.map(\.id), in: ctx)
    }

    private func delete(_ route: TransferRoute) {
        let removed = try? CoreLogic.TransferRoutes.deleteRoute(route, in: ctx)
        pendingDelete = nil
        resultMessage = "Removed \(removed?.deleted ?? 0) mirror transactions."
        showingResult = true
    }

    private func backfill(_ route: TransferRoute) {
        let result = try? CoreLogic.TransferRoutes.backfillRoute(route, in: ctx)
        resultMessage = "Scanned \(result?.scanned ?? 0), created \(result?.mirroredCreated ?? 0) mirror transactions."
        showingResult = true
    }
}

private struct RouteRow: View {
    let route: TransferRoute

    var body: some View {
        HStack(spacing: 12) {
            ColorDot(hex: route.targetAccount?.group?.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(route.pattern).lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !route.enabled {
                TagChip(text: "Off")
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let from = route.sourceAccount?.name ?? "Any"
        let to = route.targetAccount?.name ?? "—"
        return "\(from) → \(to)"
    }
}

// Identifiable form payload: nil existing ⇒ create, non-nil ⇒ edit.
struct RouteEdit: Identifiable {
    let id: UUID
    let existing: TransferRoute?
    var pattern: String
    var field: RuleField
    var matchType: RuleMatch
    var direction: TxDirection?
    var sourceId: UUID?
    var targetId: UUID?
    var enabled: Bool

    init() {
        id = UUID()
        existing = nil
        pattern = ""
        field = .description
        matchType = .contains
        direction = nil
        sourceId = nil
        targetId = nil
        enabled = true
    }

    init(_ route: TransferRoute) {
        id = route.id
        existing = route
        pattern = route.pattern
        field = route.field
        matchType = route.matchType
        direction = route.direction
        sourceId = route.sourceAccount?.id
        targetId = route.targetAccount?.id
        enabled = route.enabled
    }
}

private struct TransferRouteEditView: View {
    @State private var edit: RouteEdit
    let onApplied: (String) -> Void
    @Query(sort: [SortDescriptor(\Account.name)])
    private var accounts: [Account]
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    init(edit: RouteEdit, onApplied: @escaping (String) -> Void) {
        _edit = State(initialValue: edit)
        self.onApplied = onApplied
    }

    private var selectableAccounts: [Account] {
        accounts.filter { !$0.archived }
    }

    private var isValid: Bool {
        !edit.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && edit.targetId != nil
            && edit.sourceId != edit.targetId
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
                    Picker("Direction", selection: $edit.direction) {
                        Text("Any").tag(TxDirection?.none)
                        Text("Debit").tag(TxDirection?.some(.debit))
                        Text("Credit").tag(TxDirection?.some(.credit))
                    }
                }
                Section("Accounts") {
                    Picker("From", selection: $edit.sourceId) {
                        Text("Any").tag(UUID?.none)
                        ForEach(selectableAccounts) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    Picker("To", selection: $edit.targetId) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(selectableAccounts) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }
                Section {
                    Toggle("Enabled", isOn: $edit.enabled)
                }
            }
            .navigationTitle(edit.existing == nil ? "New Route" : "Edit Route")
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
        guard let target = accounts.first(where: { $0.id == edit.targetId }) else { return }
        let source = accounts.first { $0.id == edit.sourceId }
        if let existing = edit.existing {
            let result = try? CoreLogic.TransferRoutes.updateRoute(
                existing, pattern: edit.pattern, target: target, source: source,
                field: edit.field, matchType: edit.matchType,
                direction: edit.direction, enabled: edit.enabled, in: ctx)
            onApplied(updateMessage(result))
        } else {
            let result = try? CoreLogic.TransferRoutes.createRoute(
                pattern: edit.pattern, target: target, source: source,
                field: edit.field, matchType: edit.matchType,
                direction: edit.direction, priority: nextPriority(), enabled: edit.enabled, in: ctx)
            onApplied("Created \(result?.applied?.mirroredCreated ?? 0) mirror transactions.")
        }
        dismiss()
    }

    private func updateMessage(_ result: CoreLogic.TransferRoutes.UpdateRouteResult?) -> String {
        let removed = result?.mirrorsRemoved?.deleted ?? 0
        let created = result?.reapplied?.mirroredCreated ?? 0
        return "Removed \(removed), created \(created) mirror transactions."
    }

    private func nextPriority() -> Int {
        let all = (try? ctx.fetch(FetchDescriptor<TransferRoute>())) ?? []
        return (all.map(\.priority).max() ?? -1) + 1
    }
}

#if DEBUG
#Preview {
    ManageTransferRoutesView()
        .modelContainer(PreviewData.container)
}
#endif
