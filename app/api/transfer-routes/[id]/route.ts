import { NextResponse } from "next/server";
import { eq, sql } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { transactions, transferRoutes } from "@/db/schema";
import { RULE_FIELDS, RULE_MATCH_TYPES } from "@/lib/rules";

export const dynamic = "force-dynamic";

const patchSchema = z.object({
  pattern: z.string().min(1).max(500).optional(),
  targetAccountId: z.string().uuid().optional(),
  sourceAccountId: z.string().uuid().nullable().optional(),
  field: z.enum(RULE_FIELDS).optional(),
  matchType: z.enum(RULE_MATCH_TYPES).optional(),
  direction: z.enum(["debit", "credit"]).nullable().optional(),
  priority: z.number().int().optional(),
  enabled: z.boolean().optional(),
});

export async function PATCH(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { id } = await ctx.params;
  const body = await req.json().catch(() => null);
  const parsed = patchSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  const [existing] = await db.select().from(transferRoutes).where(eq(transferRoutes.id, id));
  if (!existing) return NextResponse.json({ error: "not found" }, { status: 404 });

  const nextTarget = parsed.data.targetAccountId ?? existing.targetAccountId;
  const nextSource =
    "sourceAccountId" in parsed.data ? parsed.data.sourceAccountId ?? null : existing.sourceAccountId;
  if (nextSource && nextSource === nextTarget) {
    return NextResponse.json(
      { error: "sourceAccountId and targetAccountId must differ" },
      { status: 400 },
    );
  }

  const targetChanged =
    parsed.data.targetAccountId && parsed.data.targetAccountId !== existing.targetAccountId;

  await db
    .update(transferRoutes)
    .set({ ...parsed.data, updatedAt: new Date() })
    .where(eq(transferRoutes.id, id));

  if (targetChanged) {
    await db
      .delete(transactions)
      .where(sql`${transactions.raw}->>'routeId' = ${id}`);
  }

  return NextResponse.json({ ok: true, targetChanged: !!targetChanged });
}

export async function DELETE(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { id } = await ctx.params;
  await db.delete(transferRoutes).where(eq(transferRoutes.id, id));
  return NextResponse.json({ ok: true });
}
