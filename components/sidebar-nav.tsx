"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  LayoutDashboard,
  Link2,
  Receipt,
  Plug,
} from "lucide-react";
import { cn } from "@/lib/utils";

const items = [
  { href: "/", label: "Dashboard", icon: LayoutDashboard },
  { href: "/connections", label: "Connections", icon: Link2 },
  { href: "/transactions", label: "Transactions", icon: Receipt },
  { href: "/connect", label: "Connect", icon: Plug },
];

export function SidebarNav() {
  const pathname = usePathname();

  return (
    <nav className="flex flex-col gap-0.5 px-2">
      {items.map(({ href, label, icon: Icon }) => {
        const active = href === "/" ? pathname === "/" : pathname.startsWith(href);
        return (
          <Link
            key={href}
            href={href}
            className={cn(
              "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
              active
                ? "bg-[var(--color-sidebar-accent)] text-[var(--color-sidebar-accent-foreground)]"
                : "text-[var(--color-sidebar-muted)] hover:bg-[var(--color-sidebar-accent)]/60 hover:text-[var(--color-sidebar-foreground)]",
            )}
          >
            <Icon className="h-4 w-4 shrink-0" />
            {label}
          </Link>
        );
      })}
    </nav>
  );
}
