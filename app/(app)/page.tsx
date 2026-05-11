import Link from "next/link";
import {
  ArrowDownLeft,
  ArrowUpRight,
  Plug,
  ReceiptText,
  TrendingDown,
  TrendingUp,
  Wallet,
} from "lucide-react";
import { and, asc, desc, eq, gte, lt, sql } from "drizzle-orm";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Progress } from "@/components/ui/progress";
import { PageHeader } from "@/components/page-header";
import { db } from "@/lib/db";
import {
  accountGroups,
  accounts,
  categories,
  connections,
  transactions,
} from "@/db/schema";
import { activeBudgetsProgress } from "@/lib/budgets";
import { getRate } from "@/lib/fx";
import { formatCurrency, formatDate } from "@/lib/utils";

export const dynamic = "force-dynamic";

function monthStart(d: Date, offset = 0): Date {
  const out = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + offset, 1));
  return out;
}

function monthLabel(d: Date): string {
  return new Intl.DateTimeFormat("en-GB", {
    month: "short",
    year: "numeric",
    timeZone: "UTC",
  }).format(d);
}

async function netWorthByGroup() {
  const acctRows = await db
    .select()
    .from(accounts);
  const groupRows = await db
    .select()
    .from(accountGroups)
    .orderBy(asc(accountGroups.sortOrder));

  const rateCache = new Map<string, number>();
  async function rateFor(ccy: string): Promise<number> {
    const key = ccy.toUpperCase();
    if (rateCache.has(key)) return rateCache.get(key)!;
    const r = await getRate(new Date(), key);
    rateCache.set(key, r ?? 1);
    return r ?? 1;
  }

  const groupMap = new Map<string | null, { name: string; color: string | null; eur: number; count: number }>();
  for (const g of groupRows) {
    groupMap.set(g.id, { name: g.name, color: g.color, eur: 0, count: 0 });
  }
  groupMap.set(null, { name: "Ungrouped", color: null, eur: 0, count: 0 });

  for (const a of acctRows) {
    if (a.archived) continue;
    const rate = await rateFor(a.currency);
    const balanceEur = a.balance ? Number(a.balance) / rate : 0;
    const key = a.groupId ?? null;
    const bucket = groupMap.get(key);
    if (!bucket) continue;
    bucket.eur += balanceEur;
    bucket.count += 1;
  }

  const groups = groupRows.map((g) => ({ id: g.id, ...groupMap.get(g.id)! }));
  const ungrouped = groupMap.get(null)!;
  if (ungrouped.count > 0) {
    groups.push({ id: null as unknown as string, ...ungrouped });
  }
  const total = Array.from(groupMap.values()).reduce((s, g) => s + g.eur, 0);
  return { groups, total };
}

async function monthlyCashFlow(months: number) {
  const now = new Date();
  const results: Array<{ label: string; income: number; expense: number }> = [];
  for (let i = months - 1; i >= 0; i--) {
    const start = monthStart(now, -i);
    const end = monthStart(now, -i + 1);
    const [{ income, expense }] = await db
      .select({
        income: sql<string>`coalesce(sum(case when ${transactions.direction} = 'credit' then ${transactions.amountEur} else 0 end), 0)`,
        expense: sql<string>`coalesce(sum(case when ${transactions.direction} = 'debit' then ${transactions.amountEur} else 0 end), 0)`,
      })
      .from(transactions)
      .where(
        and(
          eq(transactions.isTransfer, false),
          gte(transactions.bookedAt, start),
          lt(transactions.bookedAt, end),
        ),
      );
    results.push({
      label: monthLabel(start),
      income: Number(income),
      expense: Math.abs(Number(expense)),
    });
  }
  return results;
}

async function topCategoriesThisMonth() {
  const now = new Date();
  const start = monthStart(now);
  const end = monthStart(now, 1);
  const rows = await db
    .select({
      categoryId: transactions.categoryId,
      total: sql<string>`coalesce(sum(${transactions.amountEur}), 0)`,
    })
    .from(transactions)
    .where(
      and(
        eq(transactions.isTransfer, false),
        eq(transactions.direction, "debit"),
        gte(transactions.bookedAt, start),
        lt(transactions.bookedAt, end),
      ),
    )
    .groupBy(transactions.categoryId);

  const cats = await db.select().from(categories);
  const catById = new Map(cats.map((c) => [c.id, c]));

  const enriched = rows.map((r) => {
    const cat = r.categoryId ? catById.get(r.categoryId) : null;
    return {
      categoryId: r.categoryId,
      name: cat?.name ?? "Uncategorized",
      color: cat?.color ?? "#64748b",
      total: Math.abs(Number(r.total)),
    };
  });
  enriched.sort((a, b) => b.total - a.total);
  return enriched.slice(0, 5);
}

export default async function DashboardPage() {
  const [
    [connStats],
    [activeConn],
    [accountStats],
    netWorth,
    cashFlow,
    topCats,
    budgetProgress,
    recentTx,
    recentConnections,
  ] = await Promise.all([
    db.select({ total: sql<number>`count(*)` }).from(connections),
    db
      .select({ total: sql<number>`count(*)` })
      .from(connections)
      .where(eq(connections.status, "active")),
    db.select({ total: sql<number>`count(*)` }).from(accounts),
    netWorthByGroup(),
    monthlyCashFlow(4),
    topCategoriesThisMonth(),
    activeBudgetsProgress(),
    db
      .select({
        id: transactions.id,
        bookedAt: transactions.bookedAt,
        amount: transactions.amount,
        currency: transactions.currency,
        amountEur: transactions.amountEur,
        direction: transactions.direction,
        description: transactions.description,
        counterparty: transactions.counterparty,
        accountName: accounts.name,
        isTransfer: transactions.isTransfer,
      })
      .from(transactions)
      .leftJoin(accounts, eq(transactions.accountId, accounts.id))
      .where(eq(transactions.isTransfer, false))
      .orderBy(desc(transactions.bookedAt))
      .limit(6),
    db
      .select()
      .from(connections)
      .orderBy(desc(connections.createdAt))
      .limit(5),
  ]);

  const empty = Number(connStats.total) === 0 && Number(accountStats.total) === 0;
  const current = cashFlow[cashFlow.length - 1];
  const prev = cashFlow[cashFlow.length - 2];
  const incomeDelta = current && prev ? current.income - prev.income : 0;
  const expenseDelta = current && prev ? current.expense - prev.expense : 0;
  const cats = await db.select().from(categories);
  const catNameById = new Map(cats.map((c) => [c.id, c.name]));

  return (
    <>
      <PageHeader
        title="Dashboard"
        description="Net worth, cash flow, budgets, and recent activity."
        actions={
          <Button asChild size="sm">
            <Link href="/connect">
              <Plug className="h-4 w-4" />
              Connect
            </Link>
          </Button>
        }
      />

      <div className="space-y-6 p-6">
        {empty ? (
          <Card className="border-dashed">
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Plug className="h-5 w-5" />
                No data yet
              </CardTitle>
              <CardDescription>
                Connect a bank or add a manual account to start tracking.
              </CardDescription>
            </CardHeader>
            <CardContent className="flex gap-2">
              <Button asChild>
                <Link href="/connect">Connect a bank</Link>
              </Button>
              <Button asChild variant="outline">
                <Link href="/accounts">Add manual account</Link>
              </Button>
            </CardContent>
          </Card>
        ) : null}

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <KpiCard
            label="Net worth"
            value={formatCurrency(netWorth.total, "EUR")}
            hint={`across ${Number(accountStats.total)} accounts`}
            icon={<Wallet className="h-4 w-4" />}
          />
          <KpiCard
            label="This month income"
            value={current ? formatCurrency(current.income, "EUR") : "—"}
            hint={
              prev
                ? `${incomeDelta >= 0 ? "+" : ""}${formatCurrency(incomeDelta, "EUR")} vs prev`
                : undefined
            }
            icon={<ArrowDownLeft className="h-4 w-4" />}
          />
          <KpiCard
            label="This month expense"
            value={current ? formatCurrency(current.expense, "EUR") : "—"}
            hint={
              prev
                ? `${expenseDelta >= 0 ? "+" : ""}${formatCurrency(expenseDelta, "EUR")} vs prev`
                : undefined
            }
            icon={<ArrowUpRight className="h-4 w-4" />}
          />
          <KpiCard
            label="Active connections"
            value={`${Number(activeConn.total)}`}
            hint={`of ${Number(connStats.total)} total`}
            icon={<Plug className="h-4 w-4" />}
          />
        </div>

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <Card className="lg:col-span-2">
            <CardHeader className="flex flex-row items-center justify-between">
              <div>
                <CardTitle>Net worth by group</CardTitle>
                <CardDescription>Balances converted to EUR.</CardDescription>
              </div>
              <Button asChild size="sm" variant="ghost">
                <Link href="/accounts">
                  Manage
                  <ArrowUpRight className="h-4 w-4" />
                </Link>
              </Button>
            </CardHeader>
            <CardContent>
              {netWorth.groups.length === 0 ? (
                <p className="py-6 text-center text-sm text-muted-foreground">
                  No accounts yet.
                </p>
              ) : (
                <ul className="space-y-3">
                  {netWorth.groups
                    .filter((g) => g.count > 0)
                    .map((g) => {
                      const pct = netWorth.total > 0 ? (g.eur / netWorth.total) * 100 : 0;
                      return (
                        <li key={g.id ?? "ungrouped"} className="space-y-1">
                          <div className="flex items-center justify-between text-sm">
                            <span className="flex items-center gap-2">
                              <span
                                className="inline-block h-2.5 w-2.5 rounded-full"
                                style={{ background: g.color ?? "#64748b" }}
                              />
                              <span className="font-medium">{g.name}</span>
                              <span className="text-xs text-muted-foreground">
                                {g.count} {g.count === 1 ? "account" : "accounts"}
                              </span>
                            </span>
                            <span className="tabular font-medium">
                              {formatCurrency(g.eur, "EUR")}
                            </span>
                          </div>
                          <Progress value={Math.max(0, pct)} />
                        </li>
                      );
                    })}
                </ul>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Top categories</CardTitle>
              <CardDescription>This month, transfers excluded.</CardDescription>
            </CardHeader>
            <CardContent>
              {topCats.length === 0 ? (
                <p className="py-6 text-center text-sm text-muted-foreground">
                  No spend yet this month.
                </p>
              ) : (
                <ul className="space-y-3">
                  {topCats.map((c, idx) => {
                    const max = topCats[0].total;
                    const pct = max > 0 ? (c.total / max) * 100 : 0;
                    return (
                      <li key={c.categoryId ?? `none-${idx}`} className="space-y-1">
                        <div className="flex items-center justify-between text-sm">
                          <span className="flex items-center gap-2">
                            <span
                              className="inline-block h-2.5 w-2.5 rounded-full"
                              style={{ background: c.color }}
                            />
                            <span className="truncate font-medium">{c.name}</span>
                          </span>
                          <span className="tabular text-sm">
                            {formatCurrency(c.total, "EUR")}
                          </span>
                        </div>
                        <Progress value={pct} />
                      </li>
                    );
                  })}
                </ul>
              )}
            </CardContent>
          </Card>
        </div>

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <Card className="lg:col-span-2">
            <CardHeader className="flex flex-row items-center justify-between">
              <div>
                <CardTitle>Budgets</CardTitle>
                <CardDescription>Current period, worst utilization first.</CardDescription>
              </div>
              <Button asChild size="sm" variant="ghost">
                <Link href="/budgets">
                  Manage
                  <ArrowUpRight className="h-4 w-4" />
                </Link>
              </Button>
            </CardHeader>
            <CardContent>
              {budgetProgress.length === 0 ? (
                <p className="py-6 text-center text-sm text-muted-foreground">
                  No budgets yet.{" "}
                  <Link href="/budgets" className="underline">
                    Add one
                  </Link>{" "}
                  to track spending.
                </p>
              ) : (
                <ul className="space-y-3">
                  {budgetProgress
                    .map((p) => {
                      const amt = Number(p.budget.amountEur);
                      return {
                        ...p,
                        amt,
                        pct: amt > 0 ? (p.spentEur / amt) * 100 : 0,
                        name: catNameById.get(p.budget.categoryId) ?? "—",
                      };
                    })
                    .sort((a, b) => b.pct - a.pct)
                    .slice(0, 5)
                    .map((p) => (
                      <li key={p.budget.id} className="space-y-1">
                        <div className="flex items-center justify-between text-sm">
                          <span className="flex items-center gap-2">
                            <span className="font-medium">{p.name}</span>
                            <Badge variant="outline" className="text-[10px] uppercase">
                              {p.budget.period}
                            </Badge>
                          </span>
                          <span
                            className={`tabular text-sm ${
                              p.spentEur > p.amt ? "text-destructive" : ""
                            }`}
                          >
                            {formatCurrency(p.spentEur, "EUR")} /{" "}
                            {formatCurrency(p.amt, "EUR")}
                          </span>
                        </div>
                        <Progress
                          value={Math.min(100, p.pct)}
                          className={
                            p.spentEur > p.amt
                              ? "[&>[data-slot=progress-indicator]]:bg-destructive"
                              : ""
                          }
                        />
                      </li>
                    ))}
                </ul>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Cash flow</CardTitle>
              <CardDescription>Last {cashFlow.length} months.</CardDescription>
            </CardHeader>
            <CardContent>
              <ul className="space-y-2">
                {cashFlow.map((m) => (
                  <li
                    key={m.label}
                    className="flex items-center justify-between text-sm"
                  >
                    <span className="font-medium">{m.label}</span>
                    <span className="flex items-center gap-3 text-xs">
                      <span className="tabular flex items-center gap-1 text-[var(--color-success)]">
                        <TrendingUp className="h-3 w-3" />
                        {formatCurrency(m.income, "EUR")}
                      </span>
                      <span className="tabular flex items-center gap-1 text-muted-foreground">
                        <TrendingDown className="h-3 w-3" />
                        {formatCurrency(m.expense, "EUR")}
                      </span>
                    </span>
                  </li>
                ))}
              </ul>
            </CardContent>
          </Card>
        </div>

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <Card className="lg:col-span-2">
            <CardHeader className="flex flex-row items-center justify-between">
              <div>
                <CardTitle>Recent transactions</CardTitle>
                <CardDescription>Transfers excluded.</CardDescription>
              </div>
              <Button asChild size="sm" variant="ghost">
                <Link href="/transactions">
                  View all
                  <ArrowUpRight className="h-4 w-4" />
                </Link>
              </Button>
            </CardHeader>
            <CardContent>
              {recentTx.length === 0 ? (
                <p className="py-6 text-center text-sm text-muted-foreground">
                  <ReceiptText className="mx-auto mb-2 h-5 w-5" />
                  Nothing yet — transactions appear after the first sync.
                </p>
              ) : (
                <ul className="divide-y divide-border">
                  {recentTx.map((tx) => {
                    const positive = tx.direction === "credit";
                    return (
                      <li key={tx.id} className="flex items-center gap-4 py-3">
                        <div className="min-w-0 flex-1">
                          <p className="truncate text-sm font-medium">
                            {tx.counterparty || tx.description || "—"}
                          </p>
                          <p className="truncate text-xs text-muted-foreground">
                            {formatDate(tx.bookedAt)} · {tx.accountName ?? "—"}
                          </p>
                        </div>
                        <div
                          className={`tabular text-sm font-medium ${
                            positive
                              ? "text-[var(--color-success)]"
                              : "text-foreground"
                          }`}
                        >
                          {positive ? "+" : ""}
                          {formatCurrency(parseFloat(tx.amount), tx.currency)}
                        </div>
                      </li>
                    );
                  })}
                </ul>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="flex flex-row items-center justify-between">
              <div>
                <CardTitle>Connections</CardTitle>
                <CardDescription>Recent link status.</CardDescription>
              </div>
              <Button asChild size="sm" variant="ghost">
                <Link href="/connections">
                  Manage
                  <ArrowUpRight className="h-4 w-4" />
                </Link>
              </Button>
            </CardHeader>
            <CardContent>
              {recentConnections.length === 0 ? (
                <p className="py-6 text-center text-sm text-muted-foreground">
                  No connections yet.
                </p>
              ) : (
                <ul className="space-y-3">
                  {recentConnections.map((c) => (
                    <li key={c.id} className="flex items-center gap-3">
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm font-medium">
                          {c.institutionName ?? c.institutionId ?? "—"}
                        </p>
                        <p className="truncate text-xs text-muted-foreground">
                          {c.lastSyncAt
                            ? `Synced ${formatDate(c.lastSyncAt)}`
                            : "Never synced"}
                        </p>
                      </div>
                      <Badge
                        variant={
                          c.status === "active"
                            ? "success"
                            : c.status === "pending"
                              ? "warning"
                              : "destructive"
                        }
                      >
                        {c.status}
                      </Badge>
                    </li>
                  ))}
                </ul>
              )}
            </CardContent>
          </Card>
        </div>
      </div>
    </>
  );
}

function KpiCard({
  label,
  value,
  hint,
  icon,
}: {
  label: string;
  value: string;
  hint?: string;
  icon: React.ReactNode;
}) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">
          {label}
        </CardTitle>
        <div className="text-muted-foreground">{icon}</div>
      </CardHeader>
      <CardContent>
        <p className="tabular text-2xl font-semibold tracking-tight">{value}</p>
        {hint ? <p className="mt-1 text-xs text-muted-foreground">{hint}</p> : null}
      </CardContent>
    </Card>
  );
}

