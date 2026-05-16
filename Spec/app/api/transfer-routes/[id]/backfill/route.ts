import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { transferRoutes } from "@/db/schema";
import { applyTransferRoutes } from "@/lib/transfer-routes";

export const dynamic = "force-dynamic";

export async function POST(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { id } = await ctx.params;
  const [row] = await db.select().from(transferRoutes).where(eq(transferRoutes.id, id));
  if (!row) return NextResponse.json({ error: "not found" }, { status: 404 });
  const result = await applyTransferRoutes({ routeId: id, sinceDays: 730 });
  return NextResponse.json({ ok: true, ...result });
}
