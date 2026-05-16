"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Sparkles } from "lucide-react";
import { Button } from "@/components/ui/button";

export interface PendingAccount {
  id: string;
  name: string;
  iban: string | null;
  type: string;
  discoveredAt: string | null;
  connectionId: string | null;
  institutionName: string | null;
}

export function PendingApprovalBanner({
  accounts,
}: {
  accounts: PendingAccount[];
}) {
  const router = useRouter();
  const [, startTransition] = useTransition();
  const [busy, setBusy] = useState<string | null>(null);

  if (accounts.length === 0) return null;

  async function enableAndSync(account: PendingAccount) {
    setBusy(account.id);
    try {
      const patch = await fetch(`/api/accounts/${account.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          archived: false,
          pendingApproval: false,
          fullSyncRequested: true,
        }),
      });
      if (!patch.ok) {
        const data = await patch.json().catch(() => ({}));
        throw new Error(typeof data?.error === "string" ? data.error : "Enable failed");
      }
      if (account.connectionId) {
        const sync = await fetch("/api/enablebanking/sync", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ connectionId: account.connectionId }),
        });
        if (!sync.ok) {
          const data = await sync.json().catch(() => ({}));
          throw new Error(typeof data?.error === "string" ? data.error : "Sync failed");
        }
      }
      toast.success(`${account.name} enabled and synced`);
      startTransition(() => router.refresh());
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setBusy(null);
    }
  }

  async function dismiss(account: PendingAccount) {
    setBusy(account.id);
    try {
      const res = await fetch(`/api/accounts/${account.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ pendingApproval: false }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(typeof data?.error === "string" ? data.error : "Failed");
      }
      toast.success(`${account.name} dismissed`);
      startTransition(() => router.refresh());
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setBusy(null);
    }
  }

  const byConnection = new Map<string, PendingAccount[]>();
  for (const a of accounts) {
    const key = a.institutionName ?? a.connectionId ?? "Unknown";
    if (!byConnection.has(key)) byConnection.set(key, []);
    byConnection.get(key)!.push(a);
  }

  return (
    <div className="rounded-lg border border-[var(--color-warning)]/40 bg-[var(--color-warning)]/10 p-4">
      <div className="flex items-start gap-3">
        <Sparkles className="mt-0.5 h-4 w-4 text-[var(--color-warning)]" />
        <div className="flex-1 space-y-3">
          <div>
            <p className="text-sm font-medium">
              {accounts.length} new account{accounts.length === 1 ? "" : "s"} discovered
            </p>
            <p className="text-xs text-[var(--color-muted-foreground)]">
              Sync hasn&apos;t imported anything from these. Enable each one you want to
              track, or dismiss to ignore.
            </p>
          </div>
          <div className="space-y-3">
            {Array.from(byConnection.entries()).map(([institution, list]) => (
              <div key={institution} className="space-y-1">
                <p className="text-xs font-medium uppercase tracking-wide text-[var(--color-muted-foreground)]">
                  {institution}
                </p>
                <ul className="divide-y divide-[var(--color-border)] rounded-md border border-[var(--color-border)] bg-[var(--color-background)]">
                  {list.map((a) => (
                    <li key={a.id} className="flex items-center gap-3 px-3 py-2 text-sm">
                      <div className="min-w-0 flex-1">
                        <p className="truncate font-medium">{a.name}</p>
                        <p className="truncate text-xs text-[var(--color-muted-foreground)]">
                          {a.type}
                          {a.iban ? ` · ${a.iban.slice(-6)}` : null}
                          {a.discoveredAt
                            ? ` · discovered ${new Date(a.discoveredAt).toLocaleDateString("en-GB")}`
                            : null}
                        </p>
                      </div>
                      <Button
                        size="sm"
                        onClick={() => enableAndSync(a)}
                        disabled={busy === a.id}
                      >
                        {busy === a.id ? "Working…" : "Enable & sync"}
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => dismiss(a)}
                        disabled={busy === a.id}
                      >
                        Dismiss
                      </Button>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
