import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { connections } from "@/db/schema";
import { EnableBankingClient, EnableBankingError, sessionAccountsOf } from "@/lib/enablebanking";
import { syncEnableBankingConnection } from "@/lib/sync-enablebanking";

export const dynamic = "force-dynamic";

export async function POST(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { id } = await ctx.params;

  const [conn] = await db.select().from(connections).where(eq(connections.id, id));
  if (!conn) return NextResponse.json({ error: "not found" }, { status: 404 });
  if (conn.connector !== "enablebanking") {
    return NextResponse.json({ error: "not an enablebanking connection" }, { status: 400 });
  }

  if (!conn.sessionId) {
    return NextResponse.json(
      {
        ok: false,
        reason: "no_session",
        hint: "Callback never fired. Use the Authorize action to restart consent.",
      },
      { status: 200 },
    );
  }

  try {
    const client = new EnableBankingClient();
    const ebSession = await client.getSession(conn.sessionId);
    const newStatus = ebSession.status === "AUTHORIZED" ? "active" : "pending";
    const ebAccounts = sessionAccountsOf(ebSession);
    await db
      .update(connections)
      .set({
        status: newStatus,
        metadata: {
          ...(conn.metadata ?? {}),
          sessionStatus: ebSession.status,
          accountUids: ebAccounts.map((a) => a.uid),
        },
        updatedAt: new Date(),
      })
      .where(eq(connections.id, id));

    let synced = false;
    if (ebSession.status === "AUTHORIZED") {
      try {
        await syncEnableBankingConnection(id);
        synced = true;
      } catch {
        // surfaced on the connection row
      }
    }

    return NextResponse.json({
      ok: true,
      sessionStatus: ebSession.status,
      status: newStatus,
      synced,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "unknown";
    const status = err instanceof EnableBankingError ? err.status : 500;
    if (err instanceof EnableBankingError && (err.status === 401 || err.status === 403 || err.status === 404)) {
      await db
        .update(connections)
        .set({
          status: "expired",
          lastError: `Session check failed: ${err.status}`,
          updatedAt: new Date(),
        })
        .where(eq(connections.id, id));
    }
    return NextResponse.json({ error: message }, { status });
  }
}
