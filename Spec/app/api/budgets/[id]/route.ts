import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { budgets } from "@/db/schema";

export const dynamic = "force-dynamic";

const patchSchema = z.object({
  categoryId: z.string().uuid().optional(),
  amountEur: z.string().regex(/^-?\d+(\.\d{1,2})?$/).optional(),
  period: z.enum(["week", "month", "year"]).optional(),
  startsOn: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  active: z.boolean().optional(),
});

export async function PATCH(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { id } = await ctx.params;
  const body = await req.json().catch(() => null);
  const parsed = patchSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  await db
    .update(budgets)
    .set({ ...parsed.data, updatedAt: new Date() })
    .where(eq(budgets.id, id));
  return NextResponse.json({ ok: true });
}

export async function DELETE(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { id } = await ctx.params;
  await db.delete(budgets).where(eq(budgets.id, id));
  return NextResponse.json({ ok: true });
}
