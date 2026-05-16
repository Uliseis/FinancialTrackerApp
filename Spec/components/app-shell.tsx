import Link from "next/link";
import { Wallet } from "lucide-react";
import { Separator } from "@/components/ui/separator";
import { SidebarNav } from "@/components/sidebar-nav";
import { UserMenu } from "@/components/user-menu";

export interface AppShellProps {
  email: string;
  signOutAction: () => Promise<void>;
  children: React.ReactNode;
}

export function AppShell({ email, signOutAction, children }: AppShellProps) {
  return (
    <div className="flex min-h-screen">
      <aside className="hidden w-64 shrink-0 flex-col border-r border-[var(--color-sidebar-border)] bg-[var(--color-sidebar)] md:flex">
        <div className="flex h-16 items-center gap-2 px-5">
          <Link
            href="/"
            className="flex items-center gap-2 text-[var(--color-sidebar-foreground)]"
          >
            <span className="flex h-8 w-8 items-center justify-center rounded-md bg-[var(--color-sidebar-accent)]">
              <Wallet className="h-4 w-4" />
            </span>
            <span className="text-sm font-semibold tracking-tight">
              Financial Tracker
            </span>
          </Link>
        </div>
        <Separator className="bg-[var(--color-sidebar-border)]" />
        <div className="flex-1 overflow-y-auto py-3">
          <SidebarNav />
        </div>
        <Separator className="bg-[var(--color-sidebar-border)]" />
        <div className="p-2">
          <UserMenu email={email} signOutAction={signOutAction} />
        </div>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex h-16 items-center gap-3 border-b border-[var(--color-border)] bg-[var(--color-background)]/70 px-4 backdrop-blur md:hidden">
          <Link href="/" className="flex items-center gap-2 font-semibold">
            <span className="flex h-7 w-7 items-center justify-center rounded-md bg-[var(--color-sidebar-accent)]">
              <Wallet className="h-4 w-4" />
            </span>
            Financial Tracker
          </Link>
        </header>
        <main className="flex-1">{children}</main>
      </div>
    </div>
  );
}
