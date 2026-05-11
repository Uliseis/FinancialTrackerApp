import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { sharedExpenseGroups } from "@/db/schema";
import {
  SharedExpenseError,
  deleteSharedExpenseGroup,
  netForGroup,
} from "@/lib/shared-expenses";

export const dynamic = "force-dynamic";

const patchSchema = z.object({
  label: z.string().min(1).max(120).optional(),
});

export async function GET(_req: Request, ctx: { params: Promise<{ groupId: string }> }) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
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
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
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
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { groupId } = await ctx.params;
  try {
    await deleteSharedExpenseGroup(groupId);
    return NextResponse.json({ ok: true });
  } catch (e) {
    if (e instanceof SharedExpenseError) {
      return NextResponse.json({ error: e.message }, { status: e.status });
    }
    const msg = e instanceof Error ? e.message : "error";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
