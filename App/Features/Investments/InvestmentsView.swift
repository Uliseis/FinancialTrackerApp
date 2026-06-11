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
                        Section {
                            SummaryCard(vm: vm)
                                .listRowInsets(EdgeInsets(top: Theme.Space.s, leading: Theme.Space.m,
                                                          bottom: Theme.Space.s, trailing: Theme.Space.m))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
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
        .reloadOnModelChange { reload() }
    }

    private func filteredSeries(_ vm: InvestmentsModel) -> [CoreLogic.Investments.PortfolioSeriesPoint] {
        guard let start = CoreLogic.Investments.periodStartDate(period) else { return vm.series }
        return vm.series.filter { $0.date >= start }
    }
}

private struct SummaryCard: View {
    let vm: InvestmentsModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("PORTFOLIO VALUE")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                Text(Money.format(vm.totalValue, currency: "EUR"))
                    .font(.readout(.largeTitle, weight: .bold))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let pnl = vm.totalPnl {
                    Label {
                        Text(pnlText)
                    } icon: {
                        Image(systemName: pnl >= 0 ? "arrow.up.right" : "arrow.down.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Theme.amountColor(pnl))
                }
            }
            HStack(alignment: .top, spacing: Theme.Space.m) {
                MetricView(label: "Invested",
                           value: vm.totalCost.map { Money.format($0, currency: "EUR") } ?? "—")
                if vm.totalPositions > 0 {
                    MetricView(label: "Positions", value: Money.format(vm.totalPositions, currency: "EUR"))
                }
                if vm.totalCash > 0 {
                    MetricView(label: "Cash", value: Money.format(vm.totalCash, currency: "EUR"))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var pnlText: String {
        guard let pnl = vm.totalPnl else { return "—" }
        let amount = Money.format(pnl, currency: "EUR")
        let signed = pnl > 0 ? "+\(amount)" : amount
        guard let pct = vm.totalPnlPct else { return signed }
        return "\(signed)  (\(pct.formatted(.percent.precision(.fractionLength(1)))))"
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
                        .fontDesign(.rounded)
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
        Chart {
            ForEach(series, id: \.date) { p in
                AreaMark(x: .value("Date", p.date),
                         y: .value("EUR", p.marketValueEur.doubleValue))
                    .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.22), .clear],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                    .accessibilityHidden(true)
            }
            ForEach(points) { p in
                LineMark(x: .value("Date", p.date), y: .value("EUR", p.value))
                    .foregroundStyle(by: .value("Series", p.kind))
                    .interpolationMethod(.monotone)
                    .accessibilityLabel("\(p.kind), \(p.date.formatted(date: .abbreviated, time: .omitted))")
                    .accessibilityValue(Money.format(Decimal(p.value), currency: "EUR"))
            }
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
