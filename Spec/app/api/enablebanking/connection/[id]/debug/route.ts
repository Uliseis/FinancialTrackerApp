import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { connections } from "@/db/schema";
import { EnableBankingClient, EnableBankingError } from "@/lib/enablebanking";

export const dynamic = "force-dynamic";

export async function GET(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { id } = await ctx.params;

  const [conn] = await db.select().from(connections).where(eq(connections.id, id));
  if (!conn) return NextResponse.json({ error: "not found" }, { status: 404 });
  if (conn.connector !== "enablebanking") {
    return NextResponse.json({ error: "not an enablebanking connection" }, { status: 400 });
  }
  if (!conn.sessionId) {
    return NextResponse.json({
      connectionId: conn.id,
      status: conn.status,
      metadata: conn.metadata,
      ebSession: null,
      reason: "no session_id stored",
    });
  }

  try {
    const client = new EnableBankingClient();
    const ebSession = await client.getSession(conn.sessionId);
    return NextResponse.json({
      connectionId: conn.id,
      status: conn.status,
      sessionId: conn.sessionId,
      ebSession,
    });
  } catch (err) {
    if (err instanceof EnableBankingError) {
      return NextResponse.json(
        { error: "EnableBanking error", status: err.status, body: err.body },
        { status: 200 },
      );
    }
    const message = err instanceof Error ? err.message : String(err);
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
