import Link from "next/link";
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
    <main className="flex min-h-screen items-center justify-center p-6">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle>Financial Tracker</CardTitle>
          <CardDescription>Sign in to continue.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <form
            action={async () => {
              "use server";
              await signIn("github", { redirectTo: "/" });
            }}
          >
            <Button type="submit" className="w-full">
              Continue with GitHub
            </Button>
          </form>
          {error ? (
            <p className="text-sm text-[var(--color-destructive)]">
              Sign-in failed. Only the configured email is allowed.
            </p>
          ) : null}
          <p className="pt-2 text-xs text-[var(--color-muted-foreground)]">
            <Link href="/privacy" className="underline">Privacy</Link>
            <span className="mx-2">·</span>
            <Link href="/terms" className="underline">Terms</Link>
          </p>
        </CardContent>
      </Card>
    </main>
  );
}
