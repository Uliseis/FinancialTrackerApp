import SwiftUI
import SwiftData
import Charts
import CoreModel
import CoreLogic

struct DashboardView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: [SortDescriptor(\AccountSpace.sortOrder),
                  SortDescriptor(\AccountSpace.createdAt)])
    private var spaces: [AccountSpace]
    @AppStorage(SpaceSelection.key) private var currentSpaceId = ""
    @State private var model: DashboardModel = .empty

    private func reload() {
        let scope = SpaceScope.resolve(rawCurrentId: currentSpaceId, spaces: spaces)
        model = DashboardModel.load(scope: scope, in: ctx)
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.hasAccounts {
                    List {
                        Section {
                            NetWorthHeroCard(model: model)
                                .listRowInsets(EdgeInsets(top: Theme.Space.s, leading: Theme.Space.m,
                                                          bottom: Theme.Space.s, trailing: Theme.Space.m))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        if !model.groups.isEmpty { GroupBreakdownSection(groups: model.groups, cashTotal: model.cashTotal) }
                        if model.cashFlow.contains(where: { $0.income != 0 || $0.expense != 0 }) {
                            CashFlowSection(months: model.cashFlow)
                        }
                        if !model.topCategories.isEmpty { TopCategoriesSection(categories: model.topCategories) }
                        if !model.budgets.isEmpty { BudgetsSection(budgets: model.budgets) }
                    }
                    .scrollEdgeEffectStyle(.soft, for: .all)
                    .refreshable { reload() }
                } else {
                    ContentUnavailableView(
                        "Nothing to show",
                        systemImage: "rectangle.on.rectangle.angled",
                        description: Text("Add or connect an account to see your net worth and cash flow.")
                    )
                }
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SpacePicker() }
            }
        }
        .task { reload() }
        .onChange(of: currentSpaceId) { reload() }
        .reloadOnModelChange { reload() }
    }
}

// The signature screen element: a dark teal "instrument panel" carrying the
// net-worth readout, a teal compass mark, and an honest net-flow sparkline.
private struct NetWorthHeroCard: View {
    let model: DashboardModel

    private var a11y: String {
        var parts = ["Total net worth \(Money.format(model.totalNetWorth, currency: "EUR"))"]
        parts.append("cash \(Money.format(model.cashTotal, currency: "EUR"))")
        if model.investmentValue > 0 { parts.append("investments \(Money.format(model.investmentValue, currency: "EUR"))") }
        if model.liabilities != 0 { parts.append("liabilities \(Money.format(model.liabilities, currency: "EUR"))") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("TOTAL NET WORTH")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(Money.format(model.totalNetWorth, currency: "EUR"))
                        .font(.readout(.largeTitle, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: Theme.Space.s)
                CompassMark()
            }

            HStack(alignment: .top, spacing: Theme.Space.m) {
                HeroStat(label: "Cash", value: model.cashTotal)
                if model.investmentValue > 0 { HeroStat(label: "Invest", value: model.investmentValue) }
                if model.liabilities != 0 { HeroStat(label: "Liabilities", value: model.liabilities) }
            }

            if model.cashFlow.count >= 2 {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("NET FLOW · \(model.cashFlow.count) MO")
                        .font(.caption2.weight(.medium))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.4))
                    NetFlowSparkline(months: model.cashFlow)
                        .frame(height: 36)
                }
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.heroFill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
    }
}

private struct HeroStat: View {
    let label: String
    let value: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.5))
            Text(Money.format(value, currency: "EUR"))
                .font(.readout(.subheadline, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Honest net cash-flow (income − expense) sparkline over the months we have.
// Decorative on the hero; the same data is labelled in the Cash flow section.
private struct NetFlowSparkline: View {
    let months: [DashboardModel.MonthBar]

    private struct Point: Identifiable {
        let id: Date
        let value: Double
    }
    private var points: [Point] {
        months.map { Point(id: $0.id, value: ($0.income - $0.expense).doubleValue) }
    }

    var body: some View {
        Chart(points) { p in
            AreaMark(x: .value("Month", p.id), y: .value("Net", p.value))
                .foregroundStyle(LinearGradient(colors: [Theme.heroAccent.opacity(0.30), .clear],
                                                startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Month", p.id), y: .value("Net", p.value))
                .foregroundStyle(Theme.heroAccent)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }
}

private struct GroupBreakdownSection: View {
    let groups: [DashboardModel.GroupBucket]
    let cashTotal: Decimal

    var body: some View {
        Section("Net worth by group") {
            ForEach(groups) { g in
                ProgressRow(
                    value: Money.format(g.eur, currency: "EUR"),
                    fraction: (!g.excluded && cashTotal > 0) ? Theme.fraction(g.eur, of: cashTotal) : nil
                ) {
                    ColorDot(hex: g.colorHex)
                    Text(g.name)
                    Text("\(g.count)").font(.caption).foregroundStyle(.secondary)
                    if g.kind == .credit { TagChip(text: "liability") }
                    else if g.kind == .investment { TagChip(text: "investments") }
                }
            }
        }
    }
}

private struct CashFlowSection: View {
    let months: [DashboardModel.MonthBar]

    private struct FlowPoint: Identifiable {
        let id = UUID()
        let date: Date
        let label: String
        let flow: String
        let value: Double
    }

    private var points: [FlowPoint] {
        months.flatMap { m in
            [FlowPoint(date: m.id, label: m.label, flow: "Income", value: m.income.doubleValue),
             FlowPoint(date: m.id, label: m.label, flow: "Expense", value: m.expense.doubleValue)]
        }
    }

    var body: some View {
        Section("Cash flow") {
            Chart(points) { p in
                BarMark(
                    x: .value("Month", p.date, unit: .month),
                    y: .value("EUR", p.value)
                )
                .foregroundStyle(by: .value("Flow", p.flow))
                .position(by: .value("Flow", p.flow))
                .accessibilityLabel("\(p.label), \(p.flow)")
                .accessibilityValue(Money.format(Decimal(p.value), currency: "EUR"))
            }
            .chartForegroundStyleScale(["Income": Color.positiveAmount, "Expense": Color.secondary])
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .chartLegend(.visible)
            .frame(height: 200)
            .padding(.vertical, 4)

            if let current = months.last {
                HStack {
                    MetricView(label: "Income",
                               value: Money.format(current.income, currency: "EUR"),
                               color: .positiveAmount)
                    Spacer()
                    MetricView(label: "Expense",
                               value: Money.format(current.expense, currency: "EUR"))
                }
            }
        }
    }
}

private struct TopCategoriesSection: View {
    let categories: [DashboardModel.CategorySlice]

    private var maxTotal: Decimal { categories.map { $0.total }.max() ?? 0 }

    var body: some View {
        Section("Top categories this month") {
            ForEach(categories) { c in
                ProgressRow(
                    value: Money.format(c.total, currency: "EUR"),
                    fraction: Theme.fraction(c.total, of: maxTotal)
                ) {
                    ColorDot(hex: c.colorHex)
                    Text(c.name).lineLimit(1)
                }
            }
        }
    }
}

private struct BudgetsSection: View {
    let budgets: [DashboardModel.BudgetBar]

    var body: some View {
        Section("Budgets") {
            ForEach(budgets) { b in
                ProgressRow(
                    value: "\(Money.format(b.spent, currency: "EUR")) / \(Money.format(b.amount, currency: "EUR"))",
                    fraction: min(1, b.pct / 100),
                    tint: b.over ? .negativeAmount : .accentColor,
                    valueColor: b.over ? .negativeAmount : .primary
                ) {
                    if b.over {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.negativeAmount)
                            .accessibilityLabel("Over budget")
                    }
                    Text(b.name)
                    TagChip(text: b.period.rawValue)
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    DashboardView()
        .modelContainer(PreviewData.container)
}
#endif
