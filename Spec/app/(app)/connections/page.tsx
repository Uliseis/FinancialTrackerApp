import Link from "next/link";
import { db } from "@/lib/db";
import { accounts, connections } from "@/db/schema";
import { and, desc, eq, sql } from "drizzle-orm";
import { AlertCircle, CheckCircle2, HelpCircle, Plug } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { PageHeader } from "@/components/page-header";
import { formatDate } from "@/lib/utils";
import { ConnectionRowActions } from "./row-actions";
import { PendingApprovalBanner, type PendingAccount } from "./pending-approval-banner";

export const dynamic = "force-dynamic";

type StatusVariant =
  | "default"
  | "secondary"
  | "outline"
  | "destructive"
  | "success"
  | "warning";

function statusVariant(status: string): StatusVariant {
  switch (status) {
    case "active":
      return "success";
    case "pending":
      return "warning";
    case "expired":
    case "error":
    case "revoked":
      return "destructive";
    default:
      return "outline";
  }
}

function expiryHint(expiresAt: Date | null): { label: string; warn: boolean } | null {
  if (!expiresAt) return null;
  const ms = expiresAt.getTime() - Date.now();
  const days = Math.round(ms / (1000 * 60 * 60 * 24));
  if (days < 0) return { label: `Expired ${Math.abs(days)}d ago`, warn: true };
  if (days <= 14) return { label: `Re-auth in ${days}d`, warn: true };
  return { label: `${days}d left`, warn: false };
}

function pendingDiagnostic(
  hasSession: boolean,
  sessionStatus: string | undefined,
): { title: string; description: string } {
  if (!hasSession) {
    return {
      title: "Callback never fired",
      description:
        "The bank didn't redirect back to us. Most likely the user closed the tab before SCA completed, or ENABLEBANKING_REDIRECT_URL doesn't match the URL registered with Enable Banking. Click Authorize to restart consent.",
    };
  }
  if (sessionStatus === "PENDING_AUTHORIZATION") {
    return {
      title: "Awaiting bank authorization",
      description:
        "Enable Banking has a session but the bank hasn't confirmed SCA yet. Click Refresh status; if it stays in PENDING_AUTHORIZATION, the user has to finish authorizing in the bank app.",
    };
  }
  if (sessionStatus) {
    return {
      title: `Session status: ${sessionStatus}`,
      description: "Use Refresh status to re-check, or Re-authorize to restart consent.",
    };
  }
  return {
    title: "Pending — unknown reason",
    description: "Try Refresh status, or Re-authorize to restart consent.",
  };
}

export default async function ConnectionsPage({
  searchParams,
}: {
  searchParams: Promise<{ connected?: string; error?: string }>;
}) {
  const { connected, error } = await searchParams;
  const rows = await db
    .select()
    .from(connections)
    .orderBy(desc(connections.createdAt));

  const pendingRows = await db
    .select({
      id: accounts.id,
      name: accounts.name,
      iban: accounts.iban,
      type: accounts.type,
      metadata: accounts.metadata,
      connectionId: accounts.connectionId,
      institutionName: connections.institutionName,
    })
    .from(accounts)
    .leftJoin(connections, eq(connections.id, accounts.connectionId))
    .where(
      and(
        eq(accounts.archived, true),
        sql`${accounts.metadata}->>'pendingApproval' = 'true'`,
      ),
    );

  const pendingAccounts: PendingAccount[] = pendingRows.map((r) => {
    const meta = (r.metadata as Record<string, unknown> | null) ?? {};
    return {
      id: r.id,
      name: r.name,
      iban: r.iban,
      type: r.type,
      discoveredAt:
        typeof meta.discoveredAt === "string" ? meta.discoveredAt : null,
      connectionId: r.connectionId,
      institutionName: r.institutionName,
    };
  });

  return (
    <>
      <PageHeader
        title="Connections"
        description="Banks, brokers, and crypto links — and consent expiry."
        actions={
          <Button asChild size="sm">
            <Link href="/connect">
              <Plug className="h-4 w-4" />
              Connect
            </Link>
          </Button>
        }
      />

      <div className="space-y-4 p-6">
        {connected ? (
          <Callout
            tone="success"
            icon={<CheckCircle2 className="h-4 w-4" />}
            title="Connected"
            description="Initial sync running in the background."
          />
        ) : null}
        {error ? (
          <Callout
            tone="destructive"
            icon={<AlertCircle className="h-4 w-4" />}
            title="Connection error"
            description={error}
          />
        ) : null}

        <PendingApprovalBanner accounts={pendingAccounts} />

        {rows.length === 0 ? (
          <div className="rounded-lg border border-dashed border-[var(--color-border)] p-10 text-center">
            <p className="text-sm font-medium">No connections yet</p>
            <p className="mt-1 text-sm text-[var(--color-muted-foreground)]">
              <Link href="/connect" className="underline">
                Connect a bank
              </Link>{" "}
              to start syncing.
            </p>
          </div>
        ) : (
          <div className="rounded-lg border border-[var(--color-border)]">
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead>Institution</TableHead>
                  <TableHead>Connector</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Expiry</TableHead>
                  <TableHead>Last sync</TableHead>
                  <TableHead className="w-[60px] text-right" aria-label="Actions" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((c) => {
                  const hint = expiryHint(c.expiresAt);
                  const metadata = (c.metadata as Record<string, unknown> | null) ?? {};
                  const country = (metadata.country as string | undefined) ?? null;
                  const sessionStatus = metadata.sessionStatus as string | undefined;
                  const diag =
                    c.status === "pending"
                      ? pendingDiagnostic(Boolean(c.sessionId), sessionStatus)
                      : null;
                  return (
                    <TableRow key={c.id}>
                      <TableCell>
                        <p className="font-medium">
                          {c.institutionName ?? c.institutionId ?? "—"}
                        </p>
                        <p className="text-xs text-[var(--color-muted-foreground)]">
                          {c.institutionId}
                        </p>
                      </TableCell>
                      <TableCell className="capitalize text-sm">{c.connector}</TableCell>
                      <TableCell>
                        <Badge variant={statusVariant(c.status)}>{c.status}</Badge>
                        {diag ? (
                          <details className="mt-2 max-w-xs">
                            <summary className="flex cursor-pointer items-center gap-1 text-xs text-[var(--color-muted-foreground)] hover:text-foreground">
                              <HelpCircle className="h-3 w-3" />
                              {diag.title}
                            </summary>
                            <p className="mt-1 text-[11px] text-[var(--color-muted-foreground)]">
                              {diag.description}
                            </p>
                          </details>
                        ) : null}
                      </TableCell>
                      <TableCell>
                        {c.expiresAt ? (
                          <div>
                            <p className="tabular text-sm">{formatDate(c.expiresAt)}</p>
                            {hint ? (
                              <p
                                className={
                                  hint.warn
                                    ? "text-xs text-[var(--color-destructive)]"
                                    : "text-xs text-[var(--color-muted-foreground)]"
                                }
                              >
                                {hint.label}
                              </p>
                            ) : null}
                          </div>
                        ) : (
                          <span className="text-sm text-[var(--color-muted-foreground)]">—</span>
                        )}
                      </TableCell>
                      <TableCell>
                        <p className="tabular text-sm">
                          {c.lastSyncAt ? formatDate(c.lastSyncAt) : "Never"}
                        </p>
                        {c.lastError ? (
                          <p className="max-w-xs truncate text-xs text-[var(--color-destructive)]">
                            {c.lastError}
                          </p>
                        ) : null}
                      </TableCell>
                      <TableCell className="text-right">
                        <ConnectionRowActions
                          id={c.id}
                          institutionId={c.institutionId ?? null}
                          institutionName={c.institutionName ?? null}
                          status={c.status}
                          hasSession={Boolean(c.sessionId)}
                          country={country}
                        />
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </div>
        )}
      </div>
    </>
  );
}

function Callout({
  tone,
  icon,
  title,
  description,
}: {
  tone: "success" | "destructive";
  icon: React.ReactNode;
  title: string;
  description: string;
}) {
  const color =
    tone === "success"
      ? "border-[var(--color-success)]/40 bg-[var(--color-success)]/10 text-[var(--color-success)]"
      : "border-[var(--color-destructive)]/40 bg-[var(--color-destructive)]/10 text-[var(--color-destructive)]";
  return (
    <div className={`flex items-start gap-3 rounded-lg border px-4 py-3 ${color}`}>
      <span className="mt-0.5">{icon}</span>
      <div>
        <p className="text-sm font-medium">{title}</p>
        <p className="text-sm opacity-90">{description}</p>
      </div>
    </div>
  );
}
