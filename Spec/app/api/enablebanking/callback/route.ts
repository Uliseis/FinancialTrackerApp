import { NextResponse } from "next/server";
import { and, eq, sql } from "drizzle-orm";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { connections } from "@/db/schema";
import { EnableBankingClient, sessionAccountsOf } from "@/lib/enablebanking";
import { syncEnableBankingConnection } from "@/lib/sync-enablebanking";

export const dynamic = "force-dynamic";

export async function GET(req: Request) {
  const session = await auth();
  if (!session?.user) {
    return NextResponse.redirect(new URL("/login", req.url));
  }

  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  const error = url.searchParams.get("error");

  if (error) {
    return NextResponse.redirect(
      new URL(`/connections?error=${encodeURIComponent(error)}`, req.url),
    );
  }
  if (!code) {
    return NextResponse.redirect(new URL("/connections?error=missing_code", req.url));
  }
  if (!state) {
    return NextResponse.redirect(new URL("/connections?error=missing_state", req.url));
  }

  try {
    const matches = await db
      .select()
      .from(connections)
      .where(
        and(
          eq(connections.connector, "enablebanking"),
          sql`${connections.metadata}->>'state' = ${state}`,
        ),
      );
    const conn = matches[0];
    if (!conn) {
      return NextResponse.redirect(new URL("/connections?error=unknown_state", req.url));
    }

    const client = new EnableBankingClient();
    const ebSession = await client.createSession(code);

    const expiresAt = ebSession.access?.valid_until
      ? new Date(ebSession.access.valid_until)
      : conn.expiresAt;

    const ebAccounts = sessionAccountsOf(ebSession);
    await db
      .update(connections)
      .set({
        sessionId: ebSession.session_id,
        status: ebSession.status === "AUTHORIZED" ? "active" : "pending",
        expiresAt: expiresAt ?? undefined,
        metadata: {
          ...(conn.metadata ?? {}),
          sessionStatus: ebSession.status,
          accountUids: ebAccounts.map((a) => a.uid),
          aspsp: ebSession.aspsp,
          authorized: ebSession.authorized,
        },
        updatedAt: new Date(),
      })
      .where(eq(connections.id, conn.id));

    if (ebSession.status === "AUTHORIZED" && ebAccounts.length > 0) {
      try {
        await syncEnableBankingConnection(conn.id);
      } catch {
        // already persisted on the connection row
      }
    }

    return NextResponse.redirect(new URL("/connections?connected=1", req.url));
  } catch (err) {
    const message = err instanceof Error ? err.message : "unknown";
    return NextResponse.redirect(
      new URL(`/connections?error=${encodeURIComponent(message)}`, req.url),
    );
  }
}
