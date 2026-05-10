"use client";

import { useState, useTransition } from "react";
import Image from "next/image";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export interface ConnectFormProps {
  institutions: { id: string; name: string; logo?: string }[];
}

export function ConnectForm({ institutions }: ConnectFormProps) {
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [activeId, setActiveId] = useState<string | null>(null);

  function start(institution: { id: string; name: string }) {
    setError(null);
    setActiveId(institution.id);
    startTransition(async () => {
      try {
        const res = await fetch("/api/gocardless/connect", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            institutionId: institution.id,
            institutionName: institution.name,
          }),
        });
        const data = (await res.json()) as { link?: string; error?: string };
        if (!res.ok || !data.link) {
          throw new Error(data.error ?? `HTTP ${res.status}`);
        }
        window.location.href = data.link;
      } catch (err) {
        setError(err instanceof Error ? err.message : "unknown");
        setActiveId(null);
      }
    });
  }

  if (institutions.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>No institutions for this country</CardTitle>
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
        {institutions.map((inst) => (
          <Card key={inst.id} className="flex h-full flex-col">
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
                <p className="text-xs text-[var(--color-muted-foreground)]">{inst.id}</p>
              </div>
              <Button
                size="sm"
                disabled={pending}
                onClick={() => start(inst)}
              >
                {pending && activeId === inst.id ? "Opening..." : "Connect"}
              </Button>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}
