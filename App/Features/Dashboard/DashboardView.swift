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
                        NetWorthCard(model: model)
                        if !model.groups.isEmpty { GroupBreakdownSection(groups: model.groups, cashTotal: model.cashTotal) }
                        if model.cashFlow.contains(where: { $0.income != 0 || $0.expense != 0 }) {
                            CashFlowSection(months: model.cashFlow)
                        }
                        if !model.topCategories.isEmpty { TopCategoriesSection(categories: model.topCategories) }
                        if !model.budgets.isEmpty { BudgetsSection(budgets: model.budgets) }
                    }
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
    }
}

private struct NetWorthCard: View {
    let model: DashboardModel

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                StatHeader(title: "Total net worth", amount: model.totalNetWorth)
                if model.investmentValue > 0 {
                    Text("cash \(Money.format(model.cashTotal, currency: "EUR")) · inv \(Money.format(model.investmentValue, currency: "EUR"))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.liabilities != 0 {
                    Text("liabilities \(Money.format(model.liabilities, currency: "EUR"))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
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
        let label: String
        let flow: String
        let value: Double
    }

    private var points: [FlowPoint] {
        months.flatMap { m in
            [FlowPoint(label: m.label, flow: "Income", value: m.income.doubleValue),
             FlowPoint(label: m.label, flow: "Expense", value: m.expense.doubleValue)]
        }
    }

    var body: some View {
        Section("Cash flow") {
            Chart(points) { p in
                BarMark(
                    x: .value("Month", p.label),
                    y: .value("EUR", p.value)
                )
                .foregroundStyle(by: .value("Flow", p.flow))
                .position(by: .value("Flow", p.flow))
            }
            .chartXScale(domain: months.map { $0.label })
            .chartForegroundStyleScale(["Income": Color.positiveAmount, "Expense": Color.secondary])
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
