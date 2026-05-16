import { LineChart, PiggyBank, TrendingUp, Wallet } from "lucide-react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { KpiCard } from "@/components/kpi-card";
import { PageHeader } from "@/components/page-header";
import { formatCurrency, formatDate } from "@/lib/utils";
import {
  computeAccountMetrics,
  computePortfolioSeries,
  listInvestmentAccountsInSpace,
  listInvestmentContributionLegs,
  listValuationsForAccounts,
} from "@/lib/investments";
import {
  getDefaultSpaceId,
  listSpaces,
  resolveSpaceId,
} from "@/lib/spaces";
import { SpaceTabs } from "../space-tabs";
import { AllocationChart } from "./allocation-chart";
import { InvestmentsManager, type AccountRow } from "./investments-manager";
import { PortfolioChart } from "./portfolio-chart";

export const dynamic = "force-dynamic";

export default async function InvestmentsPage({
  searchParams,
}: {
  searchParams: Promise<{ space?: string }>;
}) {
  const sp = await searchParams;
  const [spaces, defaultSpaceId, currentSpaceId] = await Promise.all([
    listSpaces(),
    getDefaultSpaceId(),
    resolveSpaceId(sp.space),
  ]);

  const investmentRows = await listInvestmentAccountsInSpace(currentSpaceId, defaultSpaceId);
  const investmentAccountIds = investmentRows.map((r) => r.account.id);

  const [valuations, legs] = await Promise.all([
    listValuationsForAccounts(investmentAccountIds),
    listInvestmentContributionLegs(investmentAccountIds),
  ]);

  const metricsByAccount = computeAccountMetrics(investmentAccountIds, valuations, legs);
  const series = computePortfolioSeries(investmentAccountIds, valuations, legs);

  const valuationsByAccount = new Map<string, typeof valuations>();
  for (const v of valuations) {
    const arr = valuationsByAccount.get(v.accountId) ?? [];
    arr.push(v);
    valuationsByAccount.set(v.accountId, arr);
  }

  const rows: AccountRow[] = investmentRows
    .map(({ account }) => {
      const m = metricsByAccount.get(account.id);
      const history = (valuationsByAccount.get(account.id) ?? [])
        .slice()
        .sort((a, b) => b.asOf.getTime() - a.asOf.getTime())
        .map((v) => ({
          id: v.id,
          asOf: v.asOf.toISOString().slice(0, 10),
          marketValueEur: v.marketValueEur,
          cashValueEur: v.cashValueEur,
          notes: v.notes,
        }));
      return {
        accountId: account.id,
        accountName: account.name,
        institution: account.institution,
        baselineAsOf: m?.baselineAsOf ? m.baselineAsOf.toISOString().slice(0, 10) : null,
        baselineEur: m?.baselineEur ?? null,
        latestAsOf: m?.latestAsOf ? m.latestAsOf.toISOString().slice(0, 10) : null,
        latestEur: m?.latestEur ?? null,
        latestCashEur: m?.latestCashEur ?? null,
        latestPositionsEur: m?.latestPositionsEur ?? null,
        netContributionsSinceBaselineEur: m?.netContributionsSinceBaselineEur ?? 0,
        costBasisEur: m?.costBasisEur ?? null,
        pnlEur: m?.pnlEur ?? null,
        pnlPct: m?.pnlPct ?? null,
        history,
      } satisfies AccountRow;
    })
    .sort((a, b) => a.accountName.localeCompare(b.accountName));

  let portfolioValue = 0;
  let totalCostBasis = 0;
  let totalCash = 0;
  let totalPositions = 0;
  let cashCounted = 0;
  let countedForCost = 0;
  for (const r of rows) {
    if (r.latestEur != null) portfolioValue += r.latestEur;
    if (r.costBasisEur != null) {
      totalCostBasis += r.costBasisEur;
      countedForCost++;
    }
    if (r.latestCashEur != null && r.latestPositionsEur != null) {
      totalCash += r.latestCashEur;
      totalPositions += r.latestPositionsEur;
      cashCounted++;
    }
  }
  const totalPnl = countedForCost > 0 ? portfolioValue - totalCostBasis : null;
  const totalPnlPct =
    totalPnl != null && Math.abs(totalCostBasis) > 1e-6 ? totalPnl / totalCostBasis : null;

  const allocation = rows
    .filter((r) => r.latestEur != null && r.latestEur > 0)
    .map((r) => ({ name: r.accountName, value: r.latestEur as number }));

  const lastUpdated = rows
    .map((r) => r.latestAsOf)
    .filter((d): d is string => !!d)
    .sort((a, b) => a.localeCompare(b))
    .at(-1);

  return (
    <>
      <PageHeader
        title="Investments"
        description="Track portfolio value, capital deployed, and P&L over time."
      />

      <div className="space-y-6 p-6">
        <SpaceTabs
          spaces={spaces}
          currentSpaceId={currentSpaceId}
          defaultSpaceId={defaultSpaceId}
        />

        {investmentRows.length === 0 ? (
          <Card className="border-dashed">
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <PiggyBank className="h-5 w-5" />
                No investment accounts in this space
              </CardTitle>
              <CardDescription>
                Create or move an account into a group with kind &ldquo;Investment&rdquo;.
              </CardDescription>
            </CardHeader>
          </Card>
        ) : (
          <>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <KpiCard
                label="Portfolio value"
                value={formatCurrency(portfolioValue, "EUR")}
                hint={
                  cashCounted > 0
                    ? `${formatCurrency(totalPositions, "EUR")} pos · ${formatCurrency(totalCash, "EUR")} cash`
                    : `across ${rows.length} accounts`
                }
                icon={<Wallet className="h-4 w-4" />}
              />
              <KpiCard
                label="Total invested"
                value={
                  countedForCost > 0 ? formatCurrency(totalCostBasis, "EUR") : "—"
                }
                hint={
                  countedForCost > 0
                    ? "baseline + contributions since"
                    : "set a baseline to start"
                }
                icon={<PiggyBank className="h-4 w-4" />}
              />
              <KpiCard
                label="Total P&L"
                value={totalPnl != null ? formatCurrency(totalPnl, "EUR") : "—"}
                hint={
                  totalPnlPct != null
                    ? `${totalPnl != null && totalPnl >= 0 ? "+" : ""}${(totalPnlPct * 100).toFixed(1)}%`
                    : undefined
                }
                valueClassName={
                  totalPnl == null
                    ? "tabular text-2xl font-semibold tracking-tight text-muted-foreground"
                    : totalPnl >= 0
                    ? "tabular text-2xl font-semibold tracking-tight text-[var(--color-success)]"
                    : "tabular text-2xl font-semibold tracking-tight text-[var(--color-destructive)]"
                }
                icon={<TrendingUp className="h-4 w-4" />}
              />
              <KpiCard
                label="Last updated"
                value={lastUpdated ? formatDate(lastUpdated) : "—"}
                hint={lastUpdated ? undefined : "no valuations yet"}
                icon={<LineChart className="h-4 w-4" />}
              />
            </div>

            <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
              <Card className="lg:col-span-2">
                <CardHeader>
                  <CardTitle>Value over time</CardTitle>
                  <CardDescription>Market value vs cost basis since baseline.</CardDescription>
                </CardHeader>
                <CardContent>
                  <PortfolioChart data={series} />
                </CardContent>
              </Card>
              <Card>
                <CardHeader>
                  <CardTitle>Allocation</CardTitle>
                  <CardDescription>Latest market value by account.</CardDescription>
                </CardHeader>
                <CardContent>
                  <AllocationChart data={allocation} />
                </CardContent>
              </Card>
            </div>

            <InvestmentsManager rows={rows} />
          </>
        )}
      </div>
    </>
  );
}
