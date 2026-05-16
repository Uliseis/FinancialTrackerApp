import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { accountSpaces, accounts } from "@/db/schema";
import { getDefaultSpaceId } from "@/lib/spaces";

export const dynamic = "force-dynamic";

const patchSchema = z.object({
  name: z.string().min(1).max(120).optional(),
  color: z.string().max(20).nullable().optional(),
  sortOrder: z.number().int().optional(),
});

export async function PATCH(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { id } = await ctx.params;
  const body = await req.json().catch(() => null);
  const parsed = patchSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  await db.update(accountSpaces).set(parsed.data).where(eq(accountSpaces.id, id));
  return NextResponse.json({ ok: true });
}

export async function DELETE(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { id } = await ctx.params;
  const [existing] = await db
    .select({ isDefault: accountSpaces.isDefault })
    .from(accountSpaces)
    .where(eq(accountSpaces.id, id));
  if (!existing) return NextResponse.json({ error: "not found" }, { status: 404 });
  if (existing.isDefault) {
    return NextResponse.json(
      { error: "cannot delete the default space" },
      { status: 400 },
    );
  }
  const defaultId = await getDefaultSpaceId();
  await db
    .update(accounts)
    .set({ spaceId: defaultId })
    .where(eq(accounts.spaceId, id));
  await db.delete(accountSpaces).where(eq(accountSpaces.id, id));
  return NextResponse.json({ ok: true });
}
