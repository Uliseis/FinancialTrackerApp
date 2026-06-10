import SwiftUI
import SwiftData
import CoreModel
import CoreLogic

// Paired-transfer browser (iOS-only surface; the web shows transfers inline in the
// transactions list). Pushed from SettingsView. Detect/Repair port the web's
// detect-transfers and repair-transfers API actions.
struct TransfersView: View {
    @Environment(\.modelContext) private var ctx
    @State private var listings: [CoreLogic.Transfers.GroupListing] = []
    @State private var pendingUnpair: CoreLogic.Transfers.GroupListing?
    @State private var confirmingUnpair = false
    @State private var resultMessage = ""
    @State private var showingResult = false

    var body: some View {
        List {
            ForEach(listings) { listing in
                TransferGroupRow(listing: listing)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingUnpair = listing
                            confirmingUnpair = true
                        } label: {
                            Label("Unpair", systemImage: "arrow.triangle.branch")
                        }
                    }
            }
        }
        .navigationTitle("Transfers")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if listings.isEmpty {
                ContentUnavailableView("No Transfers", systemImage: "arrow.left.arrow.right",
                                       description: Text("Paired transfers between accounts appear here."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Detect Transfers", systemImage: "sparkle.magnifyingglass", action: detect)
                    Button("Repair Groups", systemImage: "wrench.adjustable", action: repair)
                } label: {
                    Label("Maintenance", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Unpair this transfer?",
            isPresented: $confirmingUnpair,
            titleVisibility: .visible,
            presenting: pendingUnpair
        ) { listing in
            Button("Unpair", role: .destructive) { unpair(listing) }
        } message: { listing in
            Text(isRouted(listing)
                 ? "The mirrored transaction is deleted. Backfill the route to recreate it."
                 : "The transactions stay; only the pairing is removed.")
        }
        .alert("Transfers", isPresented: $showingResult) {} message: {
            Text(resultMessage)
        }
        .task { reload() }
        .reloadOnModelChange { reload() }
    }

    private func isRouted(_ listing: CoreLogic.Transfers.GroupListing) -> Bool {
        listing.group.route != nil || listing.legs.contains { $0.routedFromTx != nil }
    }

    private func reload() {
        listings = (try? CoreLogic.Transfers.listGroups(in: ctx)) ?? []
    }

    private func unpair(_ listing: CoreLogic.Transfers.GroupListing) {
        guard let leg = listing.legs.first else { return }
        do {
            try CoreLogic.Transfers.unpair(leg, in: ctx)
        } catch {
            resultMessage = "Couldn’t unpair this transfer."
            showingResult = true
        }
        pendingUnpair = nil
    }

    private func detect() {
        let result = try? CoreLogic.Transfers.detect(in: ctx)
        resultMessage = "Scanned \(result?.scanned ?? 0) transactions, paired \(result?.matched ?? 0)."
        showingResult = true
    }

    private func repair() {
        guard let result = try? CoreLogic.Transfers.repairGroups(in: ctx) else {
            resultMessage = "Repair failed."
            showingResult = true
            return
        }
        resultMessage = "Broke \(result.groupsBroken) invalid groups, unflagged \(result.txsUnflagged), deleted \(result.mirrorsDeleted) mirrors, fixed \(result.orphansFixed) orphans."
        showingResult = true
    }
}

private struct TransferGroupRow: View {
    let listing: CoreLogic.Transfers.GroupListing

    private var title: String {
        let from = listing.legs.first?.account?.name ?? "—"
        let to = listing.legs.count > 1 ? (listing.legs.last?.account?.name ?? "—") : "—"
        return "\(from) → \(to)"
    }

    private var tag: String {
        if let pattern = listing.group.route?.pattern { return pattern }
        return listing.group.pairedAt == nil ? "Manual" : "Auto"
    }

    private var amount: String {
        guard let leg = listing.legs.first else { return "—" }
        if let eur = leg.amountEur { return Money.format(abs(eur), currency: "EUR") }
        return Money.format(abs(leg.amount), currency: leg.currency)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                HStack(spacing: 6) {
                    Text(listing.latestAt, format: .dateTime.day().month(.abbreviated).year(.twoDigits))
                    TagChip(text: tag)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(amount)
                .font(.body.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    NavigationStack { TransfersView() }
        .modelContainer(PreviewData.container)
}
#endif
