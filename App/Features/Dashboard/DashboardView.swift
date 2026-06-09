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
                Text("Total net worth").font(.caption).foregroundStyle(.secondary)
                Text(Money.format(model.totalNetWorth, currency: "EUR"))
                    .font(.largeTitle.weight(.semibold).monospacedDigit())
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
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Circle().fill(Color(hex: g.colorHex) ?? .secondary)
                            .frame(width: 10, height: 10)
                        Text(g.name).font(.body)
                        Text("\(g.count)").font(.caption).foregroundStyle(.secondary)
                        if g.kind == .credit {
                            Text("liability").font(.caption2).foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        } else if g.kind == .investment {
                            Text("investments").font(.caption2).foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                        Spacer()
                        Text(Money.format(g.eur, currency: "EUR"))
                            .font(.body.monospacedDigit())
                    }
                    if !g.excluded, cashTotal > 0 {
                        ProgressView(value: max(0, fraction(g.eur, of: cashTotal)))
                    }
                }
            }
        }
    }

    private func fraction(_ part: Decimal, of whole: Decimal) -> Double {
        guard whole > 0 else { return 0 }
        return min(1, max(0, (part / whole).doubleValue))
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
            .chartForegroundStyleScale(["Income": Color.green, "Expense": Color.secondary])
            .chartLegend(.visible)
            .frame(height: 200)
            .padding(.vertical, 4)

            if let current = months.last {
                HStack {
                    metric("Income", current.income, .green)
                    Spacer()
                    metric("Expense", current.expense, .primary)
                }
            }
        }
    }

    private func metric(_ label: String, _ value: Decimal, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(Money.format(value, currency: "EUR"))
                .font(.callout.monospacedDigit()).foregroundStyle(color)
        }
    }
}

private struct TopCategoriesSection: View {
    let categories: [DashboardModel.CategorySlice]

    private var maxTotal: Decimal { categories.map { $0.total }.max() ?? 0 }

    var body: some View {
        Section("Top categories this month") {
            ForEach(categories) { c in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Circle().fill(Color(hex: c.colorHex) ?? .secondary)
                            .frame(width: 10, height: 10)
                        Text(c.name).font(.body).lineLimit(1)
                        Spacer()
                        Text(Money.format(c.total, currency: "EUR"))
                            .font(.body.monospacedDigit())
                    }
                    ProgressView(value: fraction(c.total, of: maxTotal))
                }
            }
        }
    }

    private func fraction(_ part: Decimal, of whole: Decimal) -> Double {
        guard whole > 0 else { return 0 }
        return min(1, max(0, (part / whole).doubleValue))
    }
}

private struct BudgetsSection: View {
    let budgets: [DashboardModel.BudgetBar]

    var body: some View {
        Section("Budgets") {
            ForEach(budgets) { b in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(b.name).font(.body)
                        Text(b.period.rawValue).font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                        Spacer()
                        Text("\(Money.format(b.spent, currency: "EUR")) / \(Money.format(b.amount, currency: "EUR"))")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(b.over ? .red : .primary)
                    }
                    ProgressView(value: min(1, b.pct / 100))
                        .tint(b.over ? .red : .accentColor)
                }
            }
        }
    }
}

private extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

#if DEBUG
#Preview {
    DashboardView()
        .modelContainer(PreviewData.container)
}
#endif
