import Link from "next/link";
import { LogIn, Wallet } from "lucide-react";
import { signIn, auth } from "@/lib/auth";
import { redirect } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const session = await auth();
  if (session?.user) redirect("/");
  const { error } = await searchParams;

  return (
    <main className="relative flex min-h-screen items-center justify-center overflow-hidden p-6">
      <div
        className="pointer-events-none absolute inset-0 -z-10 opacity-60"
        style={{
          backgroundImage:
            "radial-gradient(80% 60% at 50% -10%, oklch(0.27 0 0 / 0.6), transparent 60%), radial-gradient(40% 40% at 80% 100%, oklch(0.27 0.05 240 / 0.25), transparent 60%)",
        }}
      />

      <div className="w-full max-w-sm space-y-6">
        <div className="flex items-center gap-2 text-[var(--color-foreground)]">
          <span className="flex h-9 w-9 items-center justify-center rounded-md bg-[var(--color-sidebar-accent)]">
            <Wallet className="h-5 w-5" />
          </span>
          <span className="text-base font-semibold tracking-tight">Financial Tracker</span>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Welcome back</CardTitle>
            <CardDescription>Sign in with the allowed GitHub account.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <form
              action={async () => {
                "use server";
                await signIn("github", { redirectTo: "/" });
              }}
            >
              <Button type="submit" className="w-full">
                <LogIn className="h-4 w-4" />
                Continue with GitHub
              </Button>
            </form>
            {error ? (
              <div className="rounded-md border border-[var(--color-destructive)]/40 bg-[var(--color-destructive)]/10 px-3 py-2 text-sm text-[var(--color-destructive)]">
                Sign-in failed. Only the configured email is allowed.
              </div>
            ) : null}
          </CardContent>
        </Card>

        <p className="text-center text-xs text-[var(--color-muted-foreground)]">
          <Link href="/privacy" className="hover:underline">
            Privacy
          </Link>
          <span className="mx-2">·</span>
          <Link href="/terms" className="hover:underline">
            Terms
          </Link>
        </p>
      </div>
    </main>
  );
}
