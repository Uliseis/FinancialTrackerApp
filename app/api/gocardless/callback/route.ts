import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { connections } from "@/db/schema";
import { GoCardlessClient } from "@/lib/gocardless";
import { syncGocardlessConnection } from "@/lib/sync-gocardless";

export const dynamic = "force-dynamic";

export async function GET(req: Request) {
  const session = await auth();
  if (!session?.user) {
    return NextResponse.redirect(new URL("/login", req.url));
  }

  const url = new URL(req.url);
  const ref = url.searchParams.get("ref");
  const error = url.searchParams.get("error");

  if (error) {
    return NextResponse.redirect(
      new URL(`/connections?error=${encodeURIComponent(error)}`, req.url),
    );
  }
  if (!ref) {
    return NextResponse.redirect(new URL("/connections?error=missing_ref", req.url));
  }

  try {
    const client = new GoCardlessClient();
    const requisition = await client.getRequisition(ref);

    const matches = await db
      .select()
      .from(connections)
      .where(eq(connections.requisitionId, requisition.id));
    const conn = matches[0];
    if (!conn) {
      return NextResponse.redirect(
        new URL("/connections?error=unknown_requisition", req.url),
      );
    }

    await db
      .update(connections)
      .set({
        status: requisition.status === "LN" ? "active" : "pending",
        metadata: {
          ...(conn.metadata ?? {}),
          requisitionStatus: requisition.status,
          accountIds: requisition.accounts ?? [],
        },
        updatedAt: new Date(),
      })
      .where(eq(connections.id, conn.id));

    if (requisition.status === "LN" && (requisition.accounts ?? []).length > 0) {
      // Best-effort initial sync. Errors are recorded on the connection row.
      try {
        await syncGocardlessConnection(conn.id);
      } catch {
        // already persisted on the row
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
