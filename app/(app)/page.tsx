import Link from "next/link";
import {
  ArrowUpRight,
  Link2,
  ReceiptText,
  Wallet,
  RefreshCw,
  Plug,
} from "lucide-react";
import { count, desc, eq, max } from "drizzle-orm";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { PageHeader } from "@/components/page-header";
import { db } from "@/lib/db";
import { accounts, connections, transactions } from "@/db/schema";
import { formatCurrency, formatDate } from "@/lib/utils";

export const dynamic = "force-dynamic";

function statusBadge(status: string) {
  switch (status) {
    case "active":
      return <Badge variant="success">{status}</Badge>;
    case "pending":
      return <Badge variant="warning">{status}</Badge>;
    case "expired":
    case "error":
    case "revoked":
      return <Badge variant="destructive">{status}</Badge>;
    default:
      return <Badge variant="outline">{status}</Badge>;
  }
}

function relativeTime(d: Date | null) {
  if (!d) return "Never";
  const seconds = Math.round((Date.now() - d.getTime()) / 1000);
  if (seconds < 60) return "Just now";
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.round(hours / 24);
  if (days < 30) return `${days}d ago`;
  return formatDate(d);
}

export default async function DashboardPage() {
  const [
    [connStats],
    [activeConn],
    [accountStats],
    [txCount],
    [lastSync],
    recentTx,
    recentConnections,
  ] = await Promise.all([
    db.select({ total: count() }).from(connections),
    db.select({ total: count() }).from(connections).where(eq(connections.status, "active")),
    db.select({ total: count() }).from(accounts),
    db.select({ total: count() }).from(transactions),
    db.select({ at: max(connections.lastSyncAt) }).from(connections),
    db
      .select({
        id: transactions.id,
        bookedAt: transactions.bookedAt,
        amount: transactions.amount,
        currency: transactions.currency,
        direction: transactions.direction,
        description: transactions.description,
        counterparty: transactions.counterparty,
        accountName: accounts.name,
      })
      .from(transactions)
      .leftJoin(accounts, eq(transactions.accountId, accounts.id))
      .orderBy(desc(transactions.bookedAt))
      .limit(6),
    db
      .select()
      .from(connections)
      .orderBy(desc(connections.createdAt))
      .limit(5),
  ]);

  const empty = connStats.total === 0;

  return (
    <>
      <PageHeader
        title="Dashboard"
        description="Snapshot of your linked accounts and recent activity."
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
                No connections yet
              </CardTitle>
              <CardDescription>
                Link your first bank to start syncing balances and transactions.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <Button asChild>
                <Link href="/connect">
                  Connect a bank
                  <ArrowUpRight className="h-4 w-4" />
                </Link>
              </Button>
            </CardContent>
          </Card>
        ) : null}

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <KpiCard
            label="Active connections"
            value={`${activeConn.total}`}
            hint={`of ${connStats.total} total`}
            icon={<Link2 className="h-4 w-4" />}
          />
          <KpiCard
            label="Accounts"
            value={`${accountStats.total}`}
            hint="across all banks"
            icon={<Wallet className="h-4 w-4" />}
          />
          <KpiCard
            label="Transactions"
            value={`${txCount.total}`}
            hint="rows synced"
            icon={<ReceiptText className="h-4 w-4" />}
          />
          <KpiCard
            label="Last sync"
            value={relativeTime(lastSync.at)}
            hint={lastSync.at ? formatDate(lastSync.at) : "no sync yet"}
            icon={<RefreshCw className="h-4 w-4" />}
          />
        </div>

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <Card className="lg:col-span-2">
            <CardHeader className="flex flex-row items-center justify-between">
              <div>
                <CardTitle>Recent transactions</CardTitle>
                <CardDescription>Latest movements across your accounts.</CardDescription>
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
                <p className="py-6 text-center text-sm text-[var(--color-muted-foreground)]">
                  Nothing yet — transactions will appear after the first sync.
                </p>
              ) : (
                <ul className="divide-y divide-[var(--color-border)]">
                  {recentTx.map((tx) => {
                    const positive = tx.direction === "credit";
                    return (
                      <li key={tx.id} className="flex items-center gap-4 py-3">
                        <div className="min-w-0 flex-1">
                          <p className="truncate text-sm font-medium">
                            {tx.counterparty || tx.description || "—"}
                          </p>
                          <p className="truncate text-xs text-[var(--color-muted-foreground)]">
                            {formatDate(tx.bookedAt)} · {tx.accountName ?? "—"}
                          </p>
                        </div>
                        <div
                          className={`tabular text-sm font-medium ${
                            positive
                              ? "text-[var(--color-success)]"
                              : "text-[var(--color-foreground)]"
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
                <CardDescription>Latest links and their status.</CardDescription>
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
                <p className="py-6 text-center text-sm text-[var(--color-muted-foreground)]">
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
                        <p className="truncate text-xs text-[var(--color-muted-foreground)]">
                          {c.lastSyncAt ? `Synced ${relativeTime(c.lastSyncAt)}` : "Never synced"}
                        </p>
                      </div>
                      {statusBadge(c.status)}
                    </li>
                  ))}
                </ul>
              )}
            </CardContent>
          </Card>
        </div>

        <Separator />
        <p className="text-xs text-[var(--color-muted-foreground)]">
          Charts and category breakdowns will appear here once dashboard v1 lands.
        </p>
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
        <CardTitle className="text-sm font-medium text-[var(--color-muted-foreground)]">
          {label}
        </CardTitle>
        <div className="text-[var(--color-muted-foreground)]">{icon}</div>
      </CardHeader>
      <CardContent>
        <p className="tabular text-2xl font-semibold tracking-tight">{value}</p>
        {hint ? (
          <p className="mt-1 text-xs text-[var(--color-muted-foreground)]">{hint}</p>
        ) : null}
      </CardContent>
    </Card>
  );
}
