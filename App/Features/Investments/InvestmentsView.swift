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
    @State private var valuing: Account?
    @State private var period: CoreLogic.Investments.Period = .all
    @State private var refreshError: String?

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
                        Section {
                            ForEach(vm.rows) { row in
                                Button {
                                    valuing = account(for: row.id)
                                } label: {
                                    AccountMetricRow(row: row)
                                }
                                .tint(.primary)
                            }
                        } header: {
                            Text("Accounts")
                        } footer: {
                            if let refreshError {
                                Text(refreshError).foregroundStyle(.orange)
                            } else {
                                Text("Tap an account to set what it's worth and what you've paid in. Pull down to refresh live prices.")
                            }
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
            // Pull-to-refresh fetches live prices immediately. The foreground sync is throttled
            // to 15 minutes, which is right for a background refresh but wrong for someone who
            // just pulled the list down asking for today's number.
            .refreshable {
                let outcome = await CoreLogic.InvestmentRefresh.run(in: ctx)
                refreshError = outcome.failures.first
                reload()
            }
            .navigationTitle("Investments")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SpacePicker() }
            }
        }
        .sheet(item: $valuing) { RecordValuationView(account: $0) }
        .task { reload() }
        .onChange(of: currentSpaceId) { reload() }
        .reloadOnModelChange { reload() }
    }

    private func account(for id: UUID) -> Account? {
        try? ctx.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })).first
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
                HStack(spacing: 4) {
                    if row.isLive {
                        Image(systemName: "bolt.fill").font(.caption2)
                            .foregroundStyle(Theme.heroAccent)
                    }
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let v = row.valueEur {
                    MoneyText(amount: v)
                } else {
                    Text("—").font(.body.monospacedDigit()).foregroundStyle(.secondary)
                }
                if let pnl = row.pnlEur {
                    Text(pnlLabel(pnl, row.pnlPct))
                        .font(.caption.monospacedDigit())
                        .fontDesign(.rounded)
                        .foregroundStyle(Theme.amountColor(pnl))
                } else {
                    Text("No cost basis")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // Surfaces the two things a typed valuation can't tell you on its own: money that landed
    // after it, and that it's old enough to be worth refreshing.
    private var subtitle: String {
        if row.contributionsSinceValueEur != 0 {
            return "incl. \(Money.format(row.contributionsSinceValueEur, currency: "EUR")) paid in"
        }
        if row.isStale { return "\(row.group) · needs a refresh" }
        return row.group
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

    // A flat zero line for every account that has no opening figure reads as "you invested
    // nothing", which is worse than not drawing it.
    private var hasCostBasis: Bool { series.contains { $0.costBasisEur != 0 } }

    private var points: [Point] {
        series.flatMap { p in
            var out = [Point(date: p.date, value: p.marketValueEur.doubleValue, kind: "Market value")]
            if hasCostBasis {
                out.append(Point(date: p.date, value: p.costBasisEur.doubleValue, kind: "Cost basis"))
            }
            return out
        }
    }

    // Label real data points, never interpolated ones: with only a couple of valuations
    // an automatic axis puts four ticks inside a single day and repeats the same label.
    // Also drops picks that render the same label as the one before: at month resolution
    // several deposit days collapse to "May 26" and the axis reads as a stutter.
    private var axisDates: [Date] {
        let dates = series.map(\.date)
        let picked: [Date]
        if dates.count > 4 {
            let step = (dates.count - 1) / 3
            picked = stride(from: 0, to: dates.count, by: max(step, 1)).map { dates[$0] }
        } else {
            picked = dates
        }
        var seen = Set<String>()
        return picked.filter { seen.insert($0.formatted(axisFormat)).inserted }
    }

    // Days for a short window, months within a year, years beyond it.
    private var axisFormat: Date.FormatStyle {
        guard let first = series.first?.date, let last = series.last?.date else {
            return .dateTime.month(.abbreviated)
        }
        let days = last.timeIntervalSince(first) / 86_400
        if days > 720 { return .dateTime.year() }
        if days > 60 { return .dateTime.month(.abbreviated).year(.twoDigits) }
        return .dateTime.day().month(.abbreviated)
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
        // Without an explicit stride Swift Charts labels a multi-year series with
        // day-of-month numbers ("02 08 14 20").
        .chartXAxis {
            AxisMarks(values: axisDates) { value in
                AxisGridLine()
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(date, format: axisFormat)
                    }
                }
            }
        }
        .chartLegend(hasCostBasis ? .visible : .hidden)
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
