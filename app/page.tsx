import Link from "next/link";
import { auth, signOut } from "@/lib/auth";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { db } from "@/lib/db";
import { connections, transactions } from "@/db/schema";
import { count, eq } from "drizzle-orm";

export const dynamic = "force-dynamic";

export default async function Home() {
  const session = await auth();

  const [connStats] = await db
    .select({ total: count() })
    .from(connections);
  const [activeConn] = await db
    .select({ total: count() })
    .from(connections)
    .where(eq(connections.status, "active"));
  const [txCount] = await db
    .select({ total: count() })
    .from(transactions);

  return (
    <main className="container py-12">
      <header className="mb-10 flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-semibold tracking-tight">Financial Tracker</h1>
          <p className="text-sm text-[var(--color-muted-foreground)]">
            Signed in as {session?.user?.email}
          </p>
        </div>
        <form
          action={async () => {
            "use server";
            await signOut({ redirectTo: "/login" });
          }}
        >
          <Button variant="outline" type="submit">Sign out</Button>
        </form>
      </header>

      <div className="mb-8 grid grid-cols-1 gap-4 md:grid-cols-3">
        <Card>
          <CardHeader>
            <CardTitle>Active connections</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-3xl font-semibold">{activeConn.total}</p>
            <p className="text-sm text-[var(--color-muted-foreground)]">
              of {connStats.total} total
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Transactions</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-3xl font-semibold">{txCount.total}</p>
            <p className="text-sm text-[var(--color-muted-foreground)]">synced rows</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Next steps</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            <Button asChild className="w-full">
              <Link href="/connect">Connect a bank</Link>
            </Button>
            <Button asChild className="w-full" variant="outline">
              <Link href="/connections">Manage connections</Link>
            </Button>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Browse</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-3">
          <Button asChild variant="outline">
            <Link href="/transactions">Transactions</Link>
          </Button>
          <Button asChild variant="outline">
            <Link href="/connections">Connections</Link>
          </Button>
          <Button asChild variant="outline">
            <Link href="/connect">Connect</Link>
          </Button>
        </CardContent>
      </Card>
    </main>
  );
}
