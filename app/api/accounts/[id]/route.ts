import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { accounts } from "@/db/schema";
import { repairTransferGroups } from "@/lib/transfers";

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
    currency: z
      .string()
      .regex(/^[A-Z]{3}$/, "currency must be a 3-letter ISO code")
      .optional(),
    pendingApproval: z.boolean().optional(),
    fullSyncRequested: z.boolean().optional(),
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
  const { pendingApproval, fullSyncRequested, ...rest } = parsed.data;
  const updates: Record<string, unknown> = { ...rest };
  if ("balance" in parsed.data) {
    updates.balanceUpdatedAt = parsed.data.balance ? new Date() : null;
  }
  if ("balanceAnchorAt" in parsed.data && parsed.data.balanceAnchorAt) {
    updates.balanceAnchorAt = new Date(parsed.data.balanceAnchorAt);
  }
  const currencyChanged = "currency" in rest;
  if (
    pendingApproval !== undefined ||
    fullSyncRequested !== undefined ||
    currencyChanged
  ) {
    const [existing] = await db
      .select({ metadata: accounts.metadata })
      .from(accounts)
      .where(eq(accounts.id, id))
      .limit(1);
    const prevMeta = (existing?.metadata as Record<string, unknown> | null) ?? {};
    const nextMeta: Record<string, unknown> = { ...prevMeta };
    if (pendingApproval !== undefined) {
      nextMeta.pendingApproval = pendingApproval;
      if (pendingApproval === false) nextMeta.approvedAt = new Date().toISOString();
    }
    if (fullSyncRequested !== undefined) {
      nextMeta.fullSyncRequested = fullSyncRequested;
    }
    if (currencyChanged) {
      nextMeta.currencyOverride = true;
      nextMeta.currencyOverrideAt = new Date().toISOString();
    }
    updates.metadata = nextMeta;
  }
  await db.update(accounts).set(updates).where(eq(accounts.id, id));

  const triggersRepair =
    "spaceId" in parsed.data ||
    "excluded" in parsed.data ||
    "archived" in parsed.data;
  let repair: Awaited<ReturnType<typeof repairTransferGroups>> | null = null;
  if (triggersRepair) {
    repair = await repairTransferGroups({ accountId: id });
  }

  return NextResponse.json({ ok: true, repair });
}

export async function DELETE(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { id } = await ctx.params;
  await db.delete(accounts).where(eq(accounts.id, id));
  return NextResponse.json({ ok: true });
}
