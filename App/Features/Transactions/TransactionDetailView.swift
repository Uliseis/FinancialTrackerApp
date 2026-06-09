import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

struct TransactionDetailView: View {
    let tx: CoreModel.Transaction
    @Query(sort: [SortDescriptor(\Account.name)]) private var accounts: [Account]
    @Environment(\.modelContext) private var ctx
    @State private var picking = false
    @State private var pairing = false
    @State private var trackingShared = false
    @State private var confirmingUnpair = false
    @State private var errorMessage = ""
    @State private var showingError = false
    @Environment(\.dismiss) private var dismiss

    private var canBeSharedPrimary: Bool {
        tx.direction == .debit && !tx.isTransfer && tx.routedFromTx == nil
            && tx.sharedExpenseGroup == nil && tx.amountEur != nil
    }

    private var isMirrorLeg: Bool { tx.routedFromTx != nil }
    private var hasTransfer: Bool {
        tx.isTransfer || tx.transferGroup != nil || !tx.mirrors.isEmpty
    }
    // createMirror requires the target in the source's space; don't offer accounts it
    // would reject.
    private var routeTargets: [Account] {
        accounts.filter {
            !$0.archived && $0.id != tx.account?.id && $0.space?.id == tx.account?.space?.id
        }
    }

    var body: some View {
        Form {
            Section("Amount") {
                row("Amount", Money.format(tx.amount, currency: tx.currency))
                if let eur = tx.amountEur {
                    row("EUR", Money.format(eur, currency: "EUR"))
                }
                if let fx = tx.fxRateUsed {
                    row("FX rate", fx.formatted(.number.precision(.fractionLength(0...6))))
                }
                row("Direction", tx.direction.rawValue.capitalized)
            }

            Section("When & where") {
                row("Booked", tx.bookedAt.formatted(date: .abbreviated, time: .omitted))
                if let valueAt = tx.valueAt {
                    row("Value", valueAt.formatted(date: .abbreviated, time: .omitted))
                }
                if let account = tx.account {
                    row("Account", account.name)
                    row("Institution", account.institution)
                }
            }

            Section("Classification") {
                Button { picking = true } label: {
                    LabeledContent("Category") {
                        HStack(spacing: 8) {
                            Text(tx.category?.name ?? "Uncategorized")
                                .foregroundStyle(tx.category == nil ? .secondary : .primary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .tint(.primary)
                row("Source", tx.categorySource.rawValue.capitalized)
                if let cp = tx.counterparty, !cp.isEmpty {
                    row("Counterparty", cp)
                }
                if let d = tx.transactionDescription, !d.isEmpty {
                    row("Description", d)
                }
            }

            Section("Transfer") {
                if isMirrorLeg {
                    row("Routed from", tx.routedFromTx?.account?.name ?? "—")
                    Button("Remove Transfer", role: .destructive) { confirmingUnpair = true }
                } else if hasTransfer {
                    if let paired = tx.transferGroup?.pairedAt {
                        row("Paired", paired.formatted(date: .abbreviated, time: .omitted))
                    } else if tx.transferGroup != nil {
                        row("Paired", "Manually")
                    }
                    if let route = tx.route {
                        row("Route", route.pattern)
                    }
                    if !tx.mirrors.isEmpty {
                        row("Mirror legs", "\(tx.mirrors.count)")
                    }
                    Button("Remove Transfer", role: .destructive) { confirmingUnpair = true }
                } else if tx.sharedExpenseGroup == nil {
                    Menu("Route to Account") {
                        ForEach(routeTargets) { account in
                            Button(account.name) { route(to: account) }
                        }
                    }
                    Button("Pair with Transaction…") { pairing = true }
                }
            }

            if let seg = tx.sharedExpenseGroup {
                Section("Shared expense") {
                    row("Group", seg.label)
                    row("Attribution", seg.attributionMonth.formatted(.dateTime.month(.wide).year()))
                }
            } else if canBeSharedPrimary {
                Section("Shared expense") {
                    Button("Track as Shared Expense") { trackingShared = true }
                }
            }

            Section("Metadata") {
                row("External ID", tx.externalId)
                row("Created", tx.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .navigationTitle(tx.amountEur.map { Money.format($0, currency: "EUR") } ?? "Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $picking) {
            CategoryPickerView(selectedId: tx.category?.id) { category in
                try? CoreLogic.Categories.recategorize(tx, to: category, in: ctx)
            }
        }
        .sheet(isPresented: $pairing) {
            TransferPartnerPickerView(tx: tx) { partner in pair(with: partner) }
        }
        .sheet(isPresented: $trackingShared) {
            SharedExpenseCreateView(primaryTx: tx)
        }
        .confirmationDialog("Remove this transfer?", isPresented: $confirmingUnpair,
                            titleVisibility: .visible) {
            Button("Remove Transfer", role: .destructive, action: unpair)
        } message: {
            Text(isMirrorLeg || !tx.mirrors.isEmpty
                 ? "The mirrored transaction is deleted. Backfill the route to recreate it."
                 : "The transactions stay; only the pairing is removed.")
        }
        .alert("Couldn’t Complete", isPresented: $showingError) {} message: {
            Text(errorMessage)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value)
    }

    private func unpair() {
        // Unpairing a mirror leg deletes tx itself — pop before the deleted model can
        // be re-read by this view's body.
        let popAfter = isMirrorLeg
        do {
            try CoreLogic.Transfers.unpair(tx, in: ctx)
            if popAfter { dismiss() }
        } catch {
            showError("Couldn’t remove this transfer.")
        }
    }

    private func route(to account: Account) {
        do {
            if try CoreLogic.TransferRoutes.createMirror(from: tx, to: account, in: ctx) == nil {
                showError("Couldn’t route into \(account.name). The target must be in the same space and not archived.")
            }
        } catch {
            showError("Couldn’t route this transfer.")
        }
    }

    private func pair(with partner: CoreModel.Transaction) {
        do {
            try CoreLogic.Transfers.pairManual(tx, partner, in: ctx)
        } catch let error as CoreLogic.Transfers.PairError {
            showError(pairErrorMessage(error))
        } catch {
            showError("Couldn’t pair these transactions.")
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }

    private func pairErrorMessage(_ error: CoreLogic.Transfers.PairError) -> String {
        switch error {
        case .sameTransaction: "Pick a different transaction."
        case .notOneDebitOneCredit: "A pair needs one debit and one credit."
        case .accountArchived: "One of the accounts is archived."
        case .differentSpace: "Both transactions must be in the same space."
        case .inSharedExpenseGroup: "One transaction is in a shared-expense group."
        case .isRoutedMirror: "One transaction is a routed mirror — un-route it first."
        case .missingEurAmount: "An EUR amount hasn’t been computed yet."
        case .amountsDiffer: "The amounts differ by more than €0.01."
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        TransactionDetailView(tx: PreviewData.sampleTransaction)
    }
}
#endif
