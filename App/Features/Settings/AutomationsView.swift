import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

struct AutomationsView: View {
    @AppStorage(AutomationSettings.recurringEnabledKey) private var recurringEnabled = false
    @AppStorage(AutomationSettings.pensionEnabledKey) private var pensionEnabled = false
    @AppStorage(AutomationSettings.pensionSourceKey) private var pensionSource = ""
    @AppStorage(AutomationSettings.pensionTargetKey) private var pensionTarget = ""
    @AppStorage(AutomationSettings.pensionAmountKey) private var pensionAmount = "125"
    @AppStorage(AutomationSettings.pensionSinceKey) private var pensionSince = 0.0
    @Query(sort: [SortDescriptor(\Account.name)]) private var accounts: [Account]
    @State private var muted = AutomationSettings.muted
    @State private var notificationsDenied = false

    private var manualAccounts: [Account] {
        accounts.filter { $0.connection == nil && !$0.archived }
    }

    private var sinceDate: Binding<Date> {
        Binding(get: { pensionSince > 0 ? Date(timeIntervalSince1970: pensionSince) : .now },
                set: { pensionSince = Calendar.current.startOfDay(for: $0).timeIntervalSince1970 })
    }

    var body: some View {
        Form {
            recurringSection
            if !muted.isEmpty { stoppedSection }
            pensionSection
            if notificationsDenied {
                Section {
                    Text("Notifications are off for Odyssey Finance. Bookings still happen; turn them on in Settings to be asked about each one.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Automations")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: recurringEnabled) { _, on in if on { requestPermission() } }
        .onChange(of: pensionEnabled) { _, on in
            if on {
                requestPermission()
                if pensionSince == 0 { pensionSince = Calendar.current.startOfDay(for: .now).timeIntervalSince1970 }
            }
        }
        .onAppear { muted = AutomationSettings.muted }
    }

    private var recurringSection: some View {
        Section {
            Toggle("Book recurring charges", isOn: $recurringEnabled)
        } header: {
            Text("Recurring charges")
        } footer: {
            Text("On the day a subscription usually lands, the charge is booked and you get a notification with Keep, Delete and Stop. A booking only counts as real once a statement import confirms it, so a cancelled subscription fades out on its own.")
        }
    }

    private var stoppedSection: some View {
        Section("Stopped") {
            ForEach(muted.sorted(), id: \.self) { key in
                Text(Self.label(for: key))
                    .swipeActions {
                        Button("Resume") {
                            AutomationSettings.unmute(key)
                            muted = AutomationSettings.muted
                        }
                        .tint(.accentColor)
                    }
            }
        }
    }

    private var pensionSection: some View {
        Section {
            Toggle("Split broker top-ups", isOn: $pensionEnabled)
            if pensionEnabled {
                Picker("From", selection: $pensionSource) {
                    Text("Choose…").tag("")
                    ForEach(manualAccounts) { Text($0.displayName).tag($0.id.uuidString) }
                }
                Picker("To", selection: $pensionTarget) {
                    Text("Choose…").tag("")
                    ForEach(manualAccounts) { Text($0.displayName).tag($0.id.uuidString) }
                }
                LabeledContent("Amount (EUR)") {
                    TextField("125", text: $pensionAmount)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                DatePicker("Transfers since", selection: sinceDate, displayedComponents: .date)
            }
        } header: {
            Text("Pension split")
        } footer: {
            Text("Every transfer that arrives in the source account on or after the date is followed by a move of this amount to the target, dated the same day. Each one comes with a notification and an Undo.")
        }
    }

    private func requestPermission() {
        Task { notificationsDenied = !(await AutomationNotifications.requestPermission()) }
    }

    // Keys are "merchant|amount"; show them the way the row did.
    private static func label(for key: String) -> String {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let amount = Decimal(string: parts[1]) else { return key }
        return "\(parts[0].capitalized) · \(Money.format(amount, currency: "EUR"))"
    }
}
