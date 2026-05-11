import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db";
import { sharedExpenseGroups } from "@/db/schema";
import { deleteSharedExpenseGroup, netForGroup } from "@/lib/shared-expenses";
import { errorResponse, requireUser } from "@/lib/api-helpers";

export const dynamic = "force-dynamic";

const patchSchema = z.object({
  label: z.string().min(1).max(120).optional(),
});

export async function GET(_req: Request, ctx: { params: Promise<{ groupId: string }> }) {
  const unauthorized = await requireUser();
  if (unauthorized) return unauthorized;
  const { groupId } = await ctx.params;
  const [group] = await db
    .select()
    .from(sharedExpenseGroups)
    .where(eq(sharedExpenseGroups.id, groupId));
  if (!group) return NextResponse.json({ error: "not found" }, { status: 404 });
  const net = await netForGroup(groupId);
  return NextResponse.json({ group, net });
}

export async function PATCH(req: Request, ctx: { params: Promise<{ groupId: string }> }) {
  const unauthorized = await requireUser();
  if (unauthorized) return unauthorized;
  const { groupId } = await ctx.params;
  const body = await req.json().catch(() => null);
  const parsed = patchSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  if (!parsed.data.label) return NextResponse.json({ ok: true });
  const [updated] = await db
    .update(sharedExpenseGroups)
    .set({ label: parsed.data.label, updatedAt: new Date() })
    .where(eq(sharedExpenseGroups.id, groupId))
    .returning();
  if (!updated) return NextResponse.json({ error: "not found" }, { status: 404 });
  return NextResponse.json({ group: updated });
}

export async function DELETE(_req: Request, ctx: { params: Promise<{ groupId: string }> }) {
  const unauthorized = await requireUser();
  if (unauthorized) return unauthorized;
  const { groupId } = await ctx.params;
  try {
    await deleteSharedExpenseGroup(groupId);
    return NextResponse.json({ ok: true });
  } catch (e) {
    return errorResponse(e);
  }
}
