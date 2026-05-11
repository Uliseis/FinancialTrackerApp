import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { accounts } from "@/db/schema";

export const dynamic = "force-dynamic";

const numericString = z
  .string()
  .regex(/^-?\d+(\.\d+)?$/, "must be numeric");

const patchSchema = z
  .object({
    groupId: z.string().uuid().nullable().optional(),
    spaceId: z.string().uuid().nullable().optional(),
    name: z.string().min(1).max(120).optional(),
    archived: z.boolean().optional(),
    excluded: z.boolean().optional(),
    balance: z.union([numericString, z.null()]).optional(),
    balanceAnchor: z.union([numericString, z.null()]).optional(),
    balanceAnchorAt: z.union([z.string().datetime(), z.null()]).optional(),
  })
  .refine(
    (d) => {
      const hasAnchor = "balanceAnchor" in d;
      const hasAt = "balanceAnchorAt" in d;
      if (!hasAnchor && !hasAt) return true;
      const aNull = d.balanceAnchor == null;
      const tNull = d.balanceAnchorAt == null;
      return aNull === tNull;
    },
    { message: "balanceAnchor and balanceAnchorAt must be set/cleared together" },
  );

export async function PATCH(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { id } = await ctx.params;
  const body = await req.json().catch(() => null);
  const parsed = patchSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  const updates: Record<string, unknown> = { ...parsed.data };
  if ("balance" in parsed.data) {
    updates.balanceUpdatedAt = parsed.data.balance ? new Date() : null;
  }
  if ("balanceAnchorAt" in parsed.data && parsed.data.balanceAnchorAt) {
    updates.balanceAnchorAt = new Date(parsed.data.balanceAnchorAt);
  }
  await db.update(accounts).set(updates).where(eq(accounts.id, id));
  return NextResponse.json({ ok: true });
}

export async function DELETE(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { id } = await ctx.params;
  await db.delete(accounts).where(eq(accounts.id, id));
  return NextResponse.json({ ok: true });
}
