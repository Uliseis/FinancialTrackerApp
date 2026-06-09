import SwiftUI
import SwiftData
import Charts
import CoreModel
import CoreLogic

struct InvestmentsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: [SortDescriptor(\AccountSpace.sortOrder),
                  SortDescriptor(\AccountSpace.createdAt)])
    private var spaces: [AccountSpace]
    @AppStorage(SpaceSelection.key) private var currentSpaceId = ""
    @State private var vm: InvestmentsModel?
    @State private var period: CoreLogic.Investments.Period = .all

    private func reload() {
        let scope = SpaceScope.resolve(rawCurrentId: currentSpaceId, spaces: spaces)
        guard let current = scope.currentId, let def = scope.defaultId else {
            vm = .empty; return
        }
        vm = InvestmentsModel.load(spaceId: current, defaultId: def, in: ctx)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let vm, !vm.rows.isEmpty {
                    List {
                        Section { SummaryCard(vm: vm) }
                        if vm.series.count > 1 {
                            Section("Value over time") {
                                PortfolioChart(series: filteredSeries(vm))
                                Picker("Period", selection: $period) {
                                    ForEach(CoreLogic.Investments.Period.allCases, id: \.self) {
                                        Text($0.label).tag($0)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                        Section("Accounts") {
                            ForEach(vm.rows) { AccountMetricRow(row: $0) }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Investments",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Investment accounts with valuations appear here.")
                    )
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .refreshable { reload() }
            .navigationTitle("Investments")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SpacePicker() }
            }
        }
        .task { reload() }
        .onChange(of: currentSpaceId) { reload() }
    }

    private func filteredSeries(_ vm: InvestmentsModel) -> [CoreLogic.Investments.PortfolioSeriesPoint] {
        guard let start = CoreLogic.Investments.periodStartDate(period) else { return vm.series }
        return vm.series.filter { $0.date >= start }
    }
}

private struct SummaryCard: View {
    let vm: InvestmentsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                StatHeader(title: "Portfolio value", amount: vm.totalValue)
                if vm.totalPositions > 0 || vm.totalCash > 0 {
                    Text("\(Money.format(vm.totalPositions, currency: "EUR")) pos · \(Money.format(vm.totalCash, currency: "EUR")) cash")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                MetricView(label: "Invested",
                           value: vm.totalCost.map { Money.format($0, currency: "EUR") } ?? "—")
                Spacer()
                MetricView(label: "P&L", value: pnlText, color: pnlColor)
            }
        }
        .padding(.vertical, 4)
    }

    private var pnlText: String {
        guard let pnl = vm.totalPnl else { return "—" }
        let amount = Money.format(pnl, currency: "EUR")
        guard let pct = vm.totalPnlPct else { return amount }
        return "\(amount)  (\(pct.formatted(.percent.precision(.fractionLength(1)))))"
    }

    private var pnlColor: Color {
        guard let pnl = vm.totalPnl else { return .secondary }
        return Theme.amountColor(pnl)
    }
}

private struct AccountMetricRow: View {
    let row: InvestmentsModel.Row

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).lineLimit(1)
                Text(row.group).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let v = row.latestEur {
                    MoneyText(amount: v)
                } else {
                    Text("—").font(.body.monospacedDigit()).foregroundStyle(.secondary)
                }
                if let pnl = row.pnlEur {
                    Text(pnlLabel(pnl, row.pnlPct))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.amountColor(pnl))
                }
            }
        }
    }

    private func pnlLabel(_ pnl: Decimal, _ pct: Decimal?) -> String {
        let a = Money.format(pnl, currency: "EUR")
        guard let pct else { return a }
        return "\(a) · \(pct.formatted(.percent.precision(.fractionLength(1))))"
    }
}

private struct PortfolioChart: View {
    let series: [CoreLogic.Investments.PortfolioSeriesPoint]

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let kind: String
    }

    private var points: [Point] {
        series.flatMap { p in
            [Point(date: p.date, value: p.marketValueEur.doubleValue, kind: "Market value"),
             Point(date: p.date, value: p.costBasisEur.doubleValue, kind: "Cost basis")]
        }
    }

    var body: some View {
        Chart(points) { p in
            LineMark(x: .value("Date", p.date), y: .value("EUR", p.value))
                .foregroundStyle(by: .value("Series", p.kind))
                .interpolationMethod(.monotone)
                .accessibilityLabel("\(p.kind), \(p.date.formatted(date: .abbreviated, time: .omitted))")
                .accessibilityValue(Money.format(Decimal(p.value), currency: "EUR"))
        }
        .chartForegroundStyleScale(["Market value": Color.accentColor, "Cost basis": Color.secondary])
        .chartLegend(.visible)
        .frame(height: 200)
        .padding(.vertical, 4)
    }
}

#if DEBUG
#Preview {
    InvestmentsView()
        .modelContainer(PreviewData.container)
}
#endif
