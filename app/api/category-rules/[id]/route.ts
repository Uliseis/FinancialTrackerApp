import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { categoryRules } from "@/db/schema";

export const dynamic = "force-dynamic";

const patchSchema = z.object({
  pattern: z.string().min(1).max(500).optional(),
  categoryId: z.string().uuid().optional(),
  field: z.enum(["description", "counterparty"]).optional(),
  matchType: z.enum(["contains", "equals", "startsWith", "endsWith", "regex"]).optional(),
  priority: z.number().int().optional(),
});

export async function PATCH(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { id } = await ctx.params;
  const body = await req.json().catch(() => null);
  const parsed = patchSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  await db.update(categoryRules).set(parsed.data).where(eq(categoryRules.id, id));
  return NextResponse.json({ ok: true });
}

export async function DELETE(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { id } = await ctx.params;
  await db.delete(categoryRules).where(eq(categoryRules.id, id));
  return NextResponse.json({ ok: true });
}
