"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { MoreHorizontal, RefreshCcwDot, RefreshCw, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

export interface ConnectionRowActionsProps {
  id: string;
  institutionId: string | null;
  institutionName: string | null;
  status: string;
  hasSession?: boolean;
  country?: string | null;
}

export function ConnectionRowActions({
  id,
  institutionId,
  institutionName,
  status,
  hasSession,
  country,
}: ConnectionRowActionsProps) {
  const router = useRouter();
  const [, startTransition] = useTransition();
  const [busy, setBusy] = useState<"sync" | "reauth" | "refresh" | null>(null);

  function sync() {
    setBusy("sync");
    const promise = (async () => {
      const res = await fetch("/api/enablebanking/sync", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ connectionId: id }),
      });
      if (!res.ok) {
        const data = (await res.json().catch(() => ({}))) as { error?: string };
        throw new Error(data.error ?? `HTTP ${res.status}`);
      }
      return res.json();
    })();

    toast.promise(promise, {
      loading: `Syncing ${institutionName ?? "connection"}…`,
      success: "Sync complete",
      error: (err: Error) => `Sync failed: ${err.message}`,
    });

    startTransition(async () => {
      try {
        await promise;
        router.refresh();
      } catch {
        // toast already surfaced the error
      } finally {
        setBusy(null);
      }
    });
  }

  function reauth() {
    if (!institutionId || !country) return;
    setBusy("reauth");
    startTransition(async () => {
      try {
        const res = await fetch("/api/enablebanking/connect", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            aspspName: institutionId,
            aspspCountry: country,
            psuType: "personal",
            connectionId: id,
          }),
        });
        const data = (await res.json()) as { link?: string; error?: string };
        if (data.link) {
          window.location.href = data.link;
          return;
        }
        toast.error(data.error ?? "Could not start re-authorization");
      } catch (err) {
        toast.error(err instanceof Error ? err.message : "Unknown error");
      } finally {
        setBusy(null);
      }
    });
  }

  function refreshStatus() {
    setBusy("refresh");
    const promise = (async () => {
      const res = await fetch(`/api/enablebanking/connection/${id}/refresh`, {
        method: "POST",
      });
      if (!res.ok) {
        const data = (await res.json().catch(() => ({}))) as { error?: string };
        throw new Error(data.error ?? `HTTP ${res.status}`);
      }
      return (await res.json()) as {
        ok: boolean;
        reason?: string;
        sessionStatus?: string;
        status?: string;
        hint?: string;
      };
    })();

    toast.promise(promise, {
      loading: "Refreshing status…",
      success: (data) => {
        if (data.reason === "no_session") return data.hint ?? "Authorize to continue";
        if (data.sessionStatus) return `Session: ${data.sessionStatus} → status ${data.status}`;
        return "Status refreshed";
      },
      error: (err: Error) => `Refresh failed: ${err.message}`,
    });

    startTransition(async () => {
      try {
        await promise;
        router.refresh();
      } catch {
        // surfaced by toast
      } finally {
        setBusy(null);
      }
    });
  }

  const reauthLabel = status === "active" ? "Re-authorize" : "Authorize";
  const canReauth = Boolean(institutionId && country);
  const showRefresh = status === "pending" && hasSession;

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" aria-label="Open actions">
          <MoreHorizontal className="h-4 w-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-48">
        <DropdownMenuLabel>Actions</DropdownMenuLabel>
        <DropdownMenuSeparator />
        {showRefresh ? (
          <DropdownMenuItem onSelect={refreshStatus} disabled={busy === "refresh"}>
            <RefreshCcwDot
              className={`h-4 w-4 ${busy === "refresh" ? "animate-spin" : ""}`}
            />
            {busy === "refresh" ? "Refreshing…" : "Refresh status"}
          </DropdownMenuItem>
        ) : null}
        <DropdownMenuItem onSelect={sync} disabled={busy === "sync"}>
          <RefreshCw className={`h-4 w-4 ${busy === "sync" ? "animate-spin" : ""}`} />
          {busy === "sync" ? "Syncing…" : "Sync now"}
        </DropdownMenuItem>
        {canReauth ? (
          <DropdownMenuItem onSelect={reauth} disabled={busy === "reauth"}>
            <ShieldCheck className="h-4 w-4" />
            {busy === "reauth" ? "Opening…" : reauthLabel}
          </DropdownMenuItem>
        ) : null}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
