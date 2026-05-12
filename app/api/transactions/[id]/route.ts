import { NextResponse } from "next/server";
import { and, eq, or } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { accounts, categories, transactions } from "@/db/schema";
import { backfillTransactionEurAmounts } from "@/lib/fx";
import { applyRulesToTransactions } from "@/lib/categorize";
import { createMirrorTransaction, removeMirrorTransaction } from "@/lib/transfer-routes";

export const dynamic = "force-dynamic";

const patchSchema = z.object({
  categoryId: z.string().uuid().nullable().optional(),
  isTransfer: z.boolean().optional(),
  transferPartnerId: z.string().uuid().nullable().optional(),
  routeToAccountId: z.string().uuid().nullable().optional(),
  bookedAt: z.string().datetime().optional(),
  amount: z
    .number()
    .finite()
    .refine((n) => n !== 0, "amount must be non-zero")
    .optional(),
  currency: z.string().regex(/^[A-Za-z]{3}$/, "currency must be 3 letters").optional(),
  description: z.string().max(500).nullable().optional(),
  counterparty: z.string().max(500).nullable().optional(),
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
    return NextResponse.json(
      { error: "invalid request body", details: parsed.error.flatten() },
      { status: 400 },
    );
  }

  const [current] = await db.select().from(transactions).where(eq(transactions.id, id));
  if (!current) return NextResponse.json({ error: "not found" }, { status: 404 });

  const updates: Record<string, unknown> = {};
  let needsFxBackfill = false;
  let needsRulesReapply = false;

  if ("categoryId" in parsed.data) {
    if (parsed.data.categoryId) {
      const [cat] = await db
        .select({ id: categories.id })
        .from(categories)
        .where(eq(categories.id, parsed.data.categoryId));
      if (!cat) {
        return NextResponse.json({ error: "category not found" }, { status: 400 });
      }
    }
    updates.categoryId = parsed.data.categoryId ?? null;
    updates.categorySource = "manual";
  }

  const criticalEdit =
    parsed.data.bookedAt !== undefined ||
    parsed.data.amount !== undefined ||
    parsed.data.currency !== undefined;
  if (criticalEdit) {
    if (current.routedFromTxId) {
      return NextResponse.json(
        { error: "this row is a mirror — edit the source transaction instead" },
        { status: 409 },
      );
    }
    const [mirror] = await db
      .select({ id: transactions.id })
      .from(transactions)
      .where(eq(transactions.routedFromTxId, current.id));
    if (mirror) {
      return NextResponse.json(
        { error: "un-route this transfer before editing amount, currency or date" },
        { status: 409 },
      );
    }
  }

  if (parsed.data.bookedAt !== undefined) {
    updates.bookedAt = new Date(parsed.data.bookedAt);
    needsFxBackfill = true;
  }
  if (parsed.data.amount !== undefined) {
    updates.amount = parsed.data.amount.toFixed(4);
    updates.direction = parsed.data.amount < 0 ? "debit" : "credit";
    updates.amountEur = null;
    updates.fxRateUsed = null;
    needsFxBackfill = true;
  }
  if (parsed.data.currency !== undefined) {
    updates.currency = parsed.data.currency.toUpperCase();
    updates.amountEur = null;
    updates.fxRateUsed = null;
    needsFxBackfill = true;
  }
  if (parsed.data.description !== undefined) {
    updates.description = parsed.data.description?.trim() || null;
    if (current.categorySource !== "manual") needsRulesReapply = true;
  }
  if (parsed.data.counterparty !== undefined) {
    updates.counterparty = parsed.data.counterparty?.trim() || null;
    if (current.categorySource !== "manual") needsRulesReapply = true;
  }

  if (Object.keys(updates).length > 0) {
    await db.update(transactions).set(updates).where(eq(transactions.id, id));
  }
  const warnings: string[] = [];
  if (needsFxBackfill) {
    try {
      await backfillTransactionEurAmounts({ txIds: [id] });
    } catch (err) {
      warnings.push(`fx: ${err instanceof Error ? err.message : String(err)}`);
    }
  }
  if (needsRulesReapply) {
    try {
      await applyRulesToTransactions([id]);
    } catch (err) {
      warnings.push(`categorize: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  if (parsed.data.routeToAccountId) {
    if (current.routedFromTxId) {
      return NextResponse.json({ error: "this transaction is itself a mirror" }, { status: 409 });
    }
    const targetId = parsed.data.routeToAccountId;
    if (targetId === current.accountId) {
      return NextResponse.json({ error: "target must be a different account" }, { status: 400 });
    }
    const [target] = await db
      .select({ id: accounts.id, archived: accounts.archived, connectionId: accounts.connectionId })
      .from(accounts)
      .where(eq(accounts.id, targetId));
    if (!target) return NextResponse.json({ error: "target account not found" }, { status: 404 });
    if (target.archived) {
      return NextResponse.json({ error: "target account is archived" }, { status: 400 });
    }
    const [refreshed] = await db
      .select()
      .from(transactions)
      .where(eq(transactions.id, id));
    const result = await createMirrorTransaction(refreshed ?? current, targetId);
    if (!result) return NextResponse.json({ error: "could not route" }, { status: 409 });
    return NextResponse.json({
      ok: true,
      transferGroupId: result.transferGroupId,
      mirrorId: result.mirrorId,
      warnings: warnings.length > 0 ? warnings : undefined,
    });
  }

  if (parsed.data.isTransfer === true && parsed.data.transferPartnerId) {
    const [existingMirror] = await db
      .select({ id: transactions.id })
      .from(transactions)
      .where(eq(transactions.routedFromTxId, current.id));
    if (existingMirror || current.routedFromTxId) {
      return NextResponse.json(
        { error: "this transaction is already part of a routed transfer" },
        { status: 409 },
      );
    }
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
    return NextResponse.json({
      ok: true,
      transferGroupId: groupId,
      warnings: warnings.length > 0 ? warnings : undefined,
    });
  }

  if (parsed.data.isTransfer === true) {
    const transferUpdates: Record<string, unknown> = { isTransfer: true };
    if (!current.transferGroupId) transferUpdates.transferGroupId = crypto.randomUUID();
    await db.update(transactions).set(transferUpdates).where(eq(transactions.id, id));
  } else if (parsed.data.isTransfer === false) {
    const [mirror] = await db
      .select({ id: transactions.id })
      .from(transactions)
      .where(
        and(eq(transactions.routedFromTxId, current.id)),
      );
    if (mirror) {
      await removeMirrorTransaction(current.id);
    } else if (current.transferGroupId) {
      await db
        .update(transactions)
        .set({ isTransfer: false, transferGroupId: null })
        .where(eq(transactions.transferGroupId, current.transferGroupId));
    } else {
      await db
        .update(transactions)
        .set({ isTransfer: false, transferGroupId: null })
        .where(eq(transactions.id, id));
    }
  }

  return NextResponse.json({
    ok: true,
    warnings: warnings.length > 0 ? warnings : undefined,
  });
}
