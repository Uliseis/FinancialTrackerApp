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
        vm = InvestmentsModel.load(spaceId: current, defaultId: def, period: period, in: ctx)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let vm, !vm.rows.isEmpty {
                    List {
                        Section {
                            SummaryCard(vm: vm, period: period)
                                .listRowInsets(EdgeInsets(top: Theme.Space.s, leading: Theme.Space.m,
                                                          bottom: Theme.Space.s, trailing: Theme.Space.m))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            Picker("Period", selection: $period) {
                                ForEach(CoreLogic.Investments.Period.allCases, id: \.self) {
                                    Text($0.label).tag($0)
                                }
                            }
                            .pickerStyle(.segmented)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        if vm.series.count > 1 {
                            Section("Value over time") {
                                PortfolioChart(series: filteredSeries(vm))
                            }
                        }
                        Section {
                            ForEach(vm.rows) { row in
                                Button {
                                    valuing = account(for: row.id)
                                } label: {
                                    AccountMetricRow(row: row, period: period)
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
        .task {
            #if DEBUG
            if let raw = ProcessInfo.processInfo.environment["UITEST_INV_PERIOD"],
               let p = CoreLogic.Investments.Period(rawValue: raw) { period = p }
            #endif
            reload()
            #if DEBUG
            if UITestHooks.presentSheet == "valuation", let id = vm?.rows.first?.id {
                valuing = account(for: id)
            }
            #endif
        }
        .onChange(of: currentSpaceId) { reload() }
        .onChange(of: period) { reload() }
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
    let period: CoreLogic.Investments.Period

    private var gain: Decimal? { period == .all ? vm.totalPnl : vm.periodGain?.gainEur }
    private var gainPct: Decimal? { period == .all ? vm.totalPnlPct : vm.periodGain?.gainPct }

    // History only reaches back to the first valuation, so a window that starts earlier is
    // measured from that reading and says so rather than pretending to cover the full span.
    // "All" and the periods measure different things, and read as contradictory without it:
    // All is lifetime profit (so it includes gains made before the app's first reading), a
    // period is only the market move inside the window.
    private var gainCaption: String {
        guard period != .all, let pg = vm.periodGain else {
            guard let first = vm.firstReadingAt else { return "All-time profit on what you paid in" }
            let since = Self.unbroken(first)
            return "All-time profit on what you paid in, including gains before \(since)"
        }
        let clamped = CoreLogic.Investments.periodStartDate(period).map { pg.from > $0 } ?? false
        let since = Self.unbroken(pg.from)
        var text = clamped
            ? "Market change since your first reading, \(since)"
            : "\(period.longLabel), market change"
        if pg.netContributionsEur != 0 {
            text += " · excl. \(Money.format(pg.netContributionsEur, currency: "EUR")) paid in"
        }
        return text
    }

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
                if let pnl = gain {
                    Label {
                        Text(pnlText)
                    } icon: {
                        Image(systemName: pnl >= 0 ? "arrow.up.right" : "arrow.down.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Theme.amountColor(pnl))
                    .contentTransition(.numericText())
                    Text(gainCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            AdaptiveStack(alignment: .top, spacing: Theme.Space.m) {
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

    // Non-breaking, so a wrapped caption never splits "14 / May 2026".
    private static func unbroken(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
            .replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    private var pnlText: String {
        guard let pnl = gain else { return "—" }
        let amount = Money.format(pnl, currency: "EUR")
        let signed = pnl > 0 ? "+\(amount)" : amount
        guard let pct = gainPct else { return signed }
        return "\(signed)  (\(pct.formatted(.percent.precision(.fractionLength(1)))))"
    }
}

private struct AccountMetricRow: View {
    let row: InvestmentsModel.Row
    let period: CoreLogic.Investments.Period

    private var gain: Decimal? { period == .all ? row.pnlEur : row.periodGainEur }
    private var gainPct: Decimal? { period == .all ? row.pnlPct : row.periodGainPct }
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        AdaptiveStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).axLineLimit(1)
                HStack(spacing: 4) {
                    if row.isLive {
                        // heroAccent is tuned for the dark panel; on a light row it washes out.
                        Image(systemName: "bolt.fill").font(.caption2)
                            .foregroundStyle(Color.brand)
                            .accessibilityLabel("Live price")
                    }
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                if let v = row.valueEur {
                    MoneyText(amount: v)
                } else {
                    Text("—").font(.body.monospacedDigit()).foregroundStyle(.secondary)
                }
                if let pnl = gain {
                    Text(pnlLabel(pnl, gainPct))
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
    // several deposit days collapse to one month and the axis reads as a stutter.
    private var axisDates: [Date] {
        var seen = Set<String>()
        return CoreLogic.ChartAxis.ticks(series.map(\.date), count: 4)
            .filter { seen.insert($0.formatted(axisFormat)).inserted }
    }

    // Days for a short window, months within a year, years beyond it. Within a single year
    // the month stands alone: "Jul 26" read as the 26th of July, not July 2026.
    private var axisFormat: Date.FormatStyle {
        guard let first = series.first?.date, let last = series.last?.date else {
            return .dateTime.month(.abbreviated)
        }
        let days = last.timeIntervalSince(first) / 86_400
        if days > 720 { return .dateTime.year() }
        if days > 60 {
            let sameYear = Calendar.current.isDate(first, equalTo: last, toGranularity: .year)
            return sameYear ? .dateTime.month(.abbreviated) : .dateTime.month(.abbreviated).year()
        }
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
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
