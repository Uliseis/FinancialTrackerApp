import { NextResponse } from "next/server";
import { eq, or } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { transactions } from "@/db/schema";

export const dynamic = "force-dynamic";

const patchSchema = z.object({
  categoryId: z.string().uuid().nullable().optional(),
  isTransfer: z.boolean().optional(),
  transferPartnerId: z.string().uuid().nullable().optional(),
});

export async function PATCH(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const session = await auth();
  if (!session?.user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const { id } = await ctx.params;
  const body = await req.json().catch(() => null);
  const parsed = patchSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }

  const [current] = await db.select().from(transactions).where(eq(transactions.id, id));
  if (!current) return NextResponse.json({ error: "not found" }, { status: 404 });

  const updates: Record<string, unknown> = {};
  if ("categoryId" in parsed.data) {
    updates.categoryId = parsed.data.categoryId ?? null;
    updates.categorySource = "manual";
  }

  if (parsed.data.isTransfer === true && parsed.data.transferPartnerId) {
    const [partner] = await db
      .select()
      .from(transactions)
      .where(eq(transactions.id, parsed.data.transferPartnerId));
    if (!partner) return NextResponse.json({ error: "partner not found" }, { status: 400 });
    if (partner.accountId === current.accountId) {
      return NextResponse.json({ error: "partner must be on a different account" }, { status: 400 });
    }
    if (partner.direction === current.direction) {
      return NextResponse.json(
        { error: "partner must have opposite direction" },
        { status: 400 },
      );
    }
    const groupId = current.transferGroupId ?? partner.transferGroupId ?? crypto.randomUUID();
    await db
      .update(transactions)
      .set({ isTransfer: true, transferGroupId: groupId })
      .where(
        or(eq(transactions.id, current.id), eq(transactions.id, partner.id)),
      );
    return NextResponse.json({ ok: true, transferGroupId: groupId });
  }

  if (parsed.data.isTransfer === true) {
    updates.isTransfer = true;
    if (!current.transferGroupId) updates.transferGroupId = crypto.randomUUID();
  } else if (parsed.data.isTransfer === false) {
    if (current.transferGroupId) {
      await db
        .update(transactions)
        .set({ isTransfer: false, transferGroupId: null })
        .where(eq(transactions.transferGroupId, current.transferGroupId));
    } else {
      updates.isTransfer = false;
      updates.transferGroupId = null;
    }
  }

  if (Object.keys(updates).length > 0) {
    await db.update(transactions).set(updates).where(eq(transactions.id, id));
  }

  return NextResponse.json({ ok: true });
}
