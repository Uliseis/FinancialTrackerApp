"use client";

import { useState, useTransition } from "react";
import Image from "next/image";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import type { Aspsp } from "@/lib/enablebanking";

export interface ConnectFormProps {
  aspsps: Aspsp[];
  country: string;
}

export function ConnectForm({ aspsps, country }: ConnectFormProps) {
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [activeName, setActiveName] = useState<string | null>(null);

  function start(aspsp: Aspsp) {
    setError(null);
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
        setError(err instanceof Error ? err.message : "unknown");
        setActiveName(null);
      }
    });
  }

  if (aspsps.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>No institutions for {country}</CardTitle>
        </CardHeader>
      </Card>
    );
  }

  return (
    <div>
      {error ? (
        <p className="mb-4 text-sm text-[var(--color-destructive)]">{error}</p>
      ) : null}
      <div className="grid grid-cols-1 gap-3 md:grid-cols-2 lg:grid-cols-3">
        {aspsps.map((inst) => (
          <Card key={`${inst.country}-${inst.name}`} className="flex h-full flex-col">
            <CardContent className="flex flex-1 items-center gap-3 p-4">
              {inst.logo ? (
                <Image
                  src={inst.logo}
                  alt={inst.name}
                  width={40}
                  height={40}
                  className="h-10 w-10 rounded object-contain"
                  unoptimized
                />
              ) : (
                <div className="h-10 w-10 rounded bg-[var(--color-muted)]" />
              )}
              <div className="flex-1">
                <p className="text-sm font-medium leading-tight">{inst.name}</p>
                <p className="text-xs text-[var(--color-muted-foreground)]">
                  {inst.country}
                  {inst.beta ? " · beta" : ""}
                </p>
              </div>
              <Button
                size="sm"
                disabled={pending}
                onClick={() => start(inst)}
              >
                {pending && activeName === inst.name ? "Opening..." : "Connect"}
              </Button>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}
