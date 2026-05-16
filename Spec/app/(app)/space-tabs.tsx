"use client";

import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import type { AccountSpace } from "@/db/schema";
import { cn } from "@/lib/utils";

export function SpaceTabs({
  spaces,
  currentSpaceId,
  defaultSpaceId,
}: {
  spaces: AccountSpace[];
  currentSpaceId: string;
  defaultSpaceId: string;
}) {
  const pathname = usePathname();
  const params = useSearchParams();

  function href(spaceId: string): string {
    const next = new URLSearchParams(params);
    if (spaceId === defaultSpaceId) {
      next.delete("space");
    } else {
      next.set("space", spaceId);
    }
    const qs = next.toString();
    return qs ? `${pathname}?${qs}` : pathname;
  }

  if (spaces.length <= 1) return null;

  return (
    <div className="flex flex-wrap items-center gap-1 rounded-md border border-border bg-card p-1">
      {spaces.map((s) => {
        const active = s.id === currentSpaceId;
        return (
          <Link
            key={s.id}
            href={href(s.id)}
            className={cn(
              "inline-flex items-center gap-2 rounded px-3 py-1.5 text-sm font-medium transition-colors",
              active
                ? "bg-primary text-primary-foreground"
                : "text-muted-foreground hover:bg-accent hover:text-foreground",
            )}
          >
            <span
              className="inline-block h-2 w-2 rounded-full"
              style={{ background: s.color ?? "#64748b" }}
            />
            {s.name}
          </Link>
        );
      })}
    </div>
  );
}
