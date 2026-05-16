import { randomUUID } from "node:crypto";
import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { accounts, categories, transactions } from "@/db/schema";
import { backfillTransactionEurAmounts } from "@/lib/fx";

export const dynamic = "force-dynamic";

const bodySchema = z.object({
  bookedAt: z.string().datetime(),
  amount: z.number().finite().positive("interest amount must be positive"),
  categoryId: z.string().uuid().nullish(),
  note: z.string().max(500).nullish(),
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
    return NextResponse.json(
      { error: "invalid request body", details: parsed.error.flatten() },
      { status: 400 },
    );
  }

  const [account] = await db.select().from(accounts).where(eq(accounts.id, id));
  if (!account) {
    return NextResponse.json({ error: "account not found" }, { status: 404 });
  }
  if (account.archived) {
    return NextResponse.json({ error: "account is archived" }, { status: 400 });
  }

  let categoryId = parsed.data.categoryId ?? null;
  if (categoryId) {
    const [cat] = await db
      .select({ id: categories.id })
      .from(categories)
      .where(eq(categories.id, categoryId));
    if (!cat) {
      return NextResponse.json({ error: "category not found" }, { status: 400 });
    }
  }

  const amount = parsed.data.amount;
  const externalId = `manual-interest:${randomUUID()}`;
  const description = parsed.data.note?.trim() || "Interest";

  const [row] = await db
    .insert(transactions)
    .values({
      accountId: id,
      externalId,
      bookedAt: new Date(parsed.data.bookedAt),
      amount: amount.toFixed(4),
      currency: account.currency,
      direction: "credit",
      description,
      counterparty: account.institution,
      categoryId,
      categorySource: categoryId ? "manual" : null,
      raw: { source: "manual-interest:v1" },
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

  return NextResponse.json({
    ok: true,
    txId: row.id,
    warnings: warnings.length > 0 ? warnings : undefined,
  });
}
