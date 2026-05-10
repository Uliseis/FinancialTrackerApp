"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";

export interface ConnectionRowActionsProps {
  id: string;
  institutionId: string | null;
  status: string;
  country?: string | null;
}

export function ConnectionRowActions({
  id,
  institutionId,
  status,
  country,
}: ConnectionRowActionsProps) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [busy, setBusy] = useState<"sync" | "reauth" | null>(null);

  function sync() {
    setBusy("sync");
    startTransition(async () => {
      try {
        await fetch("/api/enablebanking/sync", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ connectionId: id }),
        });
        router.refresh();
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
        const data = (await res.json()) as { link?: string };
        if (data.link) {
          window.location.href = data.link;
          return;
        }
      } finally {
        setBusy(null);
      }
    });
  }

  const reauthLabel = status === "active" ? "Re-authorize" : "Authorize";
  const canReauth = Boolean(institutionId && country);

  return (
    <div className="flex justify-end gap-2">
      <Button
        size="sm"
        variant="outline"
        onClick={sync}
        disabled={pending}
      >
        {busy === "sync" ? "Syncing…" : "Sync"}
      </Button>
      {canReauth ? (
        <Button size="sm" onClick={reauth} disabled={pending}>
          {busy === "reauth" ? "Opening…" : reauthLabel}
        </Button>
      ) : null}
    </div>
  );
}
