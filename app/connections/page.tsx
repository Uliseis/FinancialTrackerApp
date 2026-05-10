import Link from "next/link";
import { db } from "@/lib/db";
import { connections } from "@/db/schema";
import { desc } from "drizzle-orm";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
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
import { formatDate } from "@/lib/utils";
import { ConnectionRowActions } from "./row-actions";

export const dynamic = "force-dynamic";

function statusVariant(status: string): "default" | "secondary" | "outline" | "destructive" | "success" | "warning" {
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
    <main className="container py-10">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">Connections</h1>
          <p className="text-sm text-[var(--color-muted-foreground)]">
            Banks, brokers, and crypto links — and consent expiry.
          </p>
        </div>
        <div className="flex gap-2">
          <Button asChild variant="outline">
            <Link href="/">Back</Link>
          </Button>
          <Button asChild>
            <Link href="/connect">+ Connect</Link>
          </Button>
        </div>
      </div>

      {connected ? (
        <p className="mb-4 text-sm text-emerald-600">
          Connected. Initial sync running in the background.
        </p>
      ) : null}
      {error ? (
        <p className="mb-4 text-sm text-[var(--color-destructive)]">
          Error: {error}
        </p>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle>All connections</CardTitle>
        </CardHeader>
        <CardContent>
          {rows.length === 0 ? (
            <p className="text-sm text-[var(--color-muted-foreground)]">
              No connections yet. <Link href="/connect" className="underline">Connect a bank</Link>.
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Institution</TableHead>
                  <TableHead>Connector</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Expiry</TableHead>
                  <TableHead>Last sync</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((c) => {
                  const hint = expiryHint(c.expiresAt);
                  return (
                    <TableRow key={c.id}>
                      <TableCell>
                        <p className="font-medium">{c.institutionName ?? c.institutionId ?? "—"}</p>
                        <p className="text-xs text-[var(--color-muted-foreground)]">
                          {c.institutionId}
                        </p>
                      </TableCell>
                      <TableCell className="capitalize">{c.connector}</TableCell>
                      <TableCell>
                        <Badge variant={statusVariant(c.status)}>{c.status}</Badge>
                      </TableCell>
                      <TableCell>
                        {c.expiresAt ? (
                          <div>
                            <p className="text-sm">{formatDate(c.expiresAt)}</p>
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
                          "—"
                        )}
                      </TableCell>
                      <TableCell>
                        {c.lastSyncAt ? formatDate(c.lastSyncAt) : "Never"}
                        {c.lastError ? (
                          <p className="text-xs text-[var(--color-destructive)] max-w-xs truncate">
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
                        />
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </main>
  );
}
