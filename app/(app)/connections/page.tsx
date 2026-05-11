import Link from "next/link";
import { db } from "@/lib/db";
import { connections } from "@/db/schema";
import { desc } from "drizzle-orm";
import { AlertCircle, CheckCircle2, Plug } from "lucide-react";
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
                          country={
                            (c.metadata as { country?: string } | null)?.country ?? null
                          }
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
