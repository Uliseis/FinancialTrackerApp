import { randomUUID } from "node:crypto";
import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { accounts, transactions } from "@/db/schema";
import { backfillTransactionEurAmounts } from "@/lib/fx";
import { applyRulesToTransactions } from "@/lib/categorize";

export const dynamic = "force-dynamic";

const bodySchema = z.object({
  bookedAt: z.string().datetime(),
  amount: z.number().finite().refine((n) => n !== 0, "amount must be non-zero"),
  currency: z.string().min(3).max(3),
  description: z.string().max(500).nullish(),
  counterparty: z.string().max(500).nullish(),
  categoryId: z.string().uuid().nullish(),
});

export async function POST(
  req: Request,
  ctx: { params: Promise<{ id: string }> },
) {
  const session = await auth();
  if (!session?.user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const { id } = await ctx.params;
  const body = await req.json().catch(() => null);
  const parsed = bodySchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }

  const [account] = await db.select().from(accounts).where(eq(accounts.id, id));
  if (!account) {
    return NextResponse.json({ error: "account not found" }, { status: 404 });
  }
  if (account.connectionId != null) {
    return NextResponse.json(
      { error: "not a manual account" },
      { status: 400 },
    );
  }
  if (account.archived) {
    return NextResponse.json({ error: "account is archived" }, { status: 400 });
  }

  const amount = parsed.data.amount;
  const direction: "debit" | "credit" = amount < 0 ? "debit" : "credit";
  const externalId = `manual:${randomUUID()}`;

  const [row] = await db
    .insert(transactions)
    .values({
      accountId: id,
      externalId,
      bookedAt: new Date(parsed.data.bookedAt),
      amount: amount.toFixed(4),
      currency: parsed.data.currency.toUpperCase(),
      direction,
      description: parsed.data.description?.trim() || null,
      counterparty: parsed.data.counterparty?.trim() || null,
      categoryId: parsed.data.categoryId ?? null,
      categorySource: parsed.data.categoryId ? "manual" : null,
      raw: { source: "manual:v1" },
    })
    .onConflictDoNothing({
      target: [transactions.accountId, transactions.externalId],
    })
    .returning({ id: transactions.id });

  if (!row) {
    return NextResponse.json({ ok: true, txId: null, deduped: true });
  }

  const warnings: string[] = [];
  try {
    await backfillTransactionEurAmounts({ txIds: [row.id] });
  } catch (err) {
    warnings.push(`fx: ${err instanceof Error ? err.message : String(err)}`);
  }
  try {
    await applyRulesToTransactions([row.id]);
  } catch (err) {
    warnings.push(
      `categorize: ${err instanceof Error ? err.message : String(err)}`,
    );
  }

  return NextResponse.json({
    ok: true,
    txId: row.id,
    warnings: warnings.length > 0 ? warnings : undefined,
  });
}
