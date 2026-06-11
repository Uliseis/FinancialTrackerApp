import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

struct AccountFormView: View {
    @State private var edit: AccountEdit
    @Query(sort: [SortDescriptor(\AccountGroup.sortOrder), SortDescriptor(\AccountGroup.name)])
    private var groups: [AccountGroup]
    @Query(sort: [SortDescriptor(\AccountSpace.sortOrder), SortDescriptor(\AccountSpace.createdAt)])
    private var spaces: [AccountSpace]
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var saveError: String?

    init(edit: AccountEdit) { _edit = State(initialValue: edit) }

    // Mirrors CoreLogic normalizedCurrency so Save can't enable on input the core rejects.
    private var isValid: Bool {
        let currency = edit.currency.trimmingCharacters(in: .whitespaces)
        return !edit.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !edit.institution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        currency.count == 3 && currency.allSatisfy { $0.isLetter && $0.isASCII }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $edit.name)
                    TextField("Institution", text: $edit.institution)
                    Picker("Type", selection: $edit.type) {
                        ForEach(AccountType.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    TextField("Currency", text: $edit.currency)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Section {
                    Picker("Group", selection: $edit.groupId) {
                        Text("None").tag(UUID?.none)
                        ForEach(groups) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    Picker("Space", selection: $edit.spaceId) {
                        ForEach(spaces) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }
                if edit.isManual {
                    Section("Opening balance") {
                        TextField("Opening balance", value: $edit.openingBalance, format: .number)
                            .keyboardType(.numbersAndPunctuation)
                    }
                }
                Section {
                    Toggle("Exclude from net worth", isOn: $edit.excluded)
                    if edit.existing != nil {
                        Toggle("Archived", isOn: $edit.archived)
                    }
                }
                if edit.existing != nil {
                    Section {
                        Button("Delete Account", role: .destructive) { confirmingDelete = true }
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle(edit.existing == nil ? "New Account" : "Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
            .confirmationDialog("Delete this account?", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteAccount() }
            } message: {
                Text("This permanently deletes the account and its transactions.")
            }
            .task { if edit.spaceId == nil { edit.spaceId = defaultSpaceId } }
            .saveErrorAlert($saveError)
        }
    }

    private var defaultSpaceId: UUID? {
        (spaces.first { $0.isDefault } ?? spaces.first)?.id
    }

    private func save() {
        let group = groups.first { $0.id == edit.groupId }
        let space = spaces.first { $0.id == edit.spaceId }
        do {
            if let existing = edit.existing {
                _ = try CoreLogic.Accounts.update(
                    existing, name: edit.name, type: edit.type, institution: edit.institution,
                    currency: edit.currency, group: group, space: space,
                    excluded: edit.excluded, openingBalance: edit.openingBalance, in: ctx)
                if existing.archived != edit.archived {
                    _ = try CoreLogic.Accounts.setArchived(existing, edit.archived, in: ctx)
                }
            } else {
                try CoreLogic.Accounts.createManual(
                    name: edit.name, type: edit.type, institution: edit.institution,
                    currency: edit.currency, group: group, space: space,
                    openingBalance: edit.openingBalance, in: ctx)
            }
            dismiss()
        } catch {
            saveError = "The account wasn’t saved. Check the fields and try again."
        }
    }

    private func deleteAccount() {
        do {
            if let existing = edit.existing {
                try CoreLogic.Accounts.delete(existing, in: ctx)
            }
            dismiss()
        } catch {
            saveError = "The account wasn’t deleted."
        }
    }
}

// Identifiable form payload: nil existing ⇒ create a manual account, non-nil ⇒ edit.
struct AccountEdit: Identifiable {
    let id: UUID
    let existing: Account?
    var name: String
    var institution: String
    var type: AccountType
    var currency: String
    var groupId: UUID?
    var spaceId: UUID?
    var openingBalance: Decimal
    var excluded: Bool
    var archived: Bool

    // New accounts are always manual; only connected accounts opened from an existing row
    // hide the opening-balance field.
    var isManual: Bool { existing?.connection == nil }

    init() {
        id = UUID()
        existing = nil
        name = ""
        institution = ""
        type = .bank
        currency = "EUR"
        groupId = nil
        spaceId = nil
        openingBalance = 0
        excluded = false
        archived = false
    }

    init(_ account: Account) {
        id = account.id
        existing = account
        name = account.name
        institution = account.institution
        type = account.type
        currency = account.currency
        groupId = account.group?.id
        spaceId = account.space?.id
        openingBalance = account.manualOpeningBalance ?? 0
        excluded = account.excluded
        archived = account.archived
    }
}

extension AccountType {
    var label: String {
        switch self {
        case .bank: "Bank"
        case .broker: "Broker"
        case .crypto: "Crypto"
        case .realEstate: "Real Estate"
        case .pension: "Pension"
        case .other: "Other"
        }
    }

    var icon: String {
        switch self {
        case .bank: "building.columns.fill"
        case .broker: "chart.xyaxis.line"
        case .crypto: "bitcoinsign"
        case .realEstate: "house.fill"
        case .pension: "calendar"
        case .other: "wallet.bifold.fill"
        }
    }
}

#if DEBUG
#Preview {
    AccountFormView(edit: AccountEdit())
        .modelContainer(PreviewData.container)
}
#endif
