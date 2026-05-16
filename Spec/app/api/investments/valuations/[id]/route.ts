import { NextResponse } from "next/server";
import { eq, sql } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { portfolioValuations } from "@/db/schema";

export const dynamic = "force-dynamic";

const patchSchema = z.object({
  asOf: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional(),
  marketValueEur: z
    .string()
    .regex(/^\d+(\.\d{1,2})?$/)
    .optional(),
  cashValueEur: z
    .string()
    .regex(/^\d+(\.\d{1,2})?$/)
    .optional()
    .nullable(),
  notes: z.string().trim().max(500).optional().nullable(),
});

export async function PATCH(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { id } = await ctx.params;
  const body = await req.json().catch(() => null);
  const parsed = patchSchema.safeParse(body);
  if (!parsed.success)
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  const updates: Record<string, unknown> = { updatedAt: sql`now()` };
  if (parsed.data.asOf) updates.asOf = new Date(parsed.data.asOf + "T00:00:00.000Z");
  if (parsed.data.marketValueEur) updates.marketValueEur = parsed.data.marketValueEur;
  if (parsed.data.cashValueEur !== undefined) updates.cashValueEur = parsed.data.cashValueEur;
  if (parsed.data.notes !== undefined)
    updates.notes = parsed.data.notes?.trim() ? parsed.data.notes.trim() : null;

  // If either side of the cash <= market_value invariant is being touched,
  // resolve the post-PATCH state by reading what we're not overwriting from the row.
  if (parsed.data.marketValueEur !== undefined || parsed.data.cashValueEur !== undefined) {
    const [existing] = await db
      .select({
        marketValueEur: portfolioValuations.marketValueEur,
        cashValueEur: portfolioValuations.cashValueEur,
      })
      .from(portfolioValuations)
      .where(eq(portfolioValuations.id, id))
      .limit(1);
    if (!existing) return NextResponse.json({ error: "not found" }, { status: 404 });
    const nextMarket =
      parsed.data.marketValueEur !== undefined
        ? Number(parsed.data.marketValueEur)
        : Number(existing.marketValueEur);
    const nextCashRaw =
      parsed.data.cashValueEur !== undefined ? parsed.data.cashValueEur : existing.cashValueEur;
    const nextCash = nextCashRaw != null ? Number(nextCashRaw) : null;
    if (nextCash != null && nextCash > nextMarket) {
      return NextResponse.json(
        { error: "cash portion cannot exceed total market value" },
        { status: 400 },
      );
    }
  }

  try {
    await db.update(portfolioValuations).set(updates).where(eq(portfolioValuations.id, id));
  } catch (err) {
    const code = (err as { code?: string } | null)?.code;
    if (code === "23505") {
      return NextResponse.json(
        { error: "a valuation already exists for this account on that date" },
        { status: 409 },
      );
    }
    throw err;
  }
  return NextResponse.json({ ok: true });
}

export async function DELETE(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { id } = await ctx.params;
  await db.delete(portfolioValuations).where(eq(portfolioValuations.id, id));
  return NextResponse.json({ ok: true });
}
