"use client";

import { useMemo, useState, useTransition } from "react";
import Image from "next/image";
import { Loader2, Search, Sparkles } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import type { Aspsp } from "@/lib/enablebanking";

export interface ConnectFormProps {
  aspsps: Aspsp[];
  country: string;
}

export function ConnectForm({ aspsps, country }: ConnectFormProps) {
  const [pending, startTransition] = useTransition();
  const [activeName, setActiveName] = useState<string | null>(null);
  const [query, setQuery] = useState("");

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return aspsps;
    return aspsps.filter((a) => a.name.toLowerCase().includes(q));
  }, [aspsps, query]);

  function start(aspsp: Aspsp) {
    setActiveName(aspsp.name);
    startTransition(async () => {
      try {
        const res = await fetch("/api/enablebanking/connect", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            aspspName: aspsp.name,
            aspspCountry: aspsp.country,
            psuType: "personal",
          }),
        });
        const data = (await res.json()) as { link?: string; error?: string };
        if (!res.ok || !data.link) {
          throw new Error(data.error ?? `HTTP ${res.status}`);
        }
        window.location.href = data.link;
      } catch (err) {
        toast.error(err instanceof Error ? err.message : "Could not start connection");
        setActiveName(null);
      }
    });
  }

  if (aspsps.length === 0) {
    return (
      <div className="rounded-lg border border-dashed border-[var(--color-border)] p-10 text-center">
        <p className="text-sm font-medium">No institutions for {country}</p>
        <p className="mt-1 text-sm text-[var(--color-muted-foreground)]">
          Try a different country.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        <div className="relative w-full max-w-sm">
          <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-[var(--color-muted-foreground)]" />
          <Input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search institutions…"
            className="pl-8"
          />
        </div>
        <p className="text-xs text-[var(--color-muted-foreground)]">
          {filtered.length} of {aspsps.length}
        </p>
      </div>

      {filtered.length === 0 ? (
        <div className="rounded-lg border border-dashed border-[var(--color-border)] p-10 text-center text-sm text-[var(--color-muted-foreground)]">
          No matches. Try another search.
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-3 md:grid-cols-2 lg:grid-cols-3">
          {filtered.map((inst) => {
            const isActive = pending && activeName === inst.name;
            return (
              <Card
                key={`${inst.country}-${inst.name}`}
                className="group flex items-center gap-3 p-4 transition-colors hover:border-[var(--color-ring)]"
              >
                {inst.logo ? (
                  <Image
                    src={inst.logo}
                    alt={inst.name}
                    width={40}
                    height={40}
                    className="h-10 w-10 shrink-0 rounded object-contain"
                    unoptimized
                  />
                ) : (
                  <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded bg-[var(--color-muted)] text-[var(--color-muted-foreground)]">
                    <Sparkles className="h-4 w-4" />
                  </div>
                )}
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-medium leading-tight">
                    {inst.name}
                  </p>
                  <div className="mt-0.5 flex items-center gap-1.5">
                    <span className="text-xs text-[var(--color-muted-foreground)]">
                      {inst.country}
                    </span>
                    {inst.beta ? (
                      <Badge variant="outline" className="px-1.5 py-0 text-[10px]">
                        beta
                      </Badge>
                    ) : null}
                  </div>
                </div>
                <Button size="sm" disabled={pending} onClick={() => start(inst)}>
                  {isActive ? (
                    <>
                      <Loader2 className="h-3.5 w-3.5 animate-spin" />
                      Opening
                    </>
                  ) : (
                    "Connect"
                  )}
                </Button>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}
