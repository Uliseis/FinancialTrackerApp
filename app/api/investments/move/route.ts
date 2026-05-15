import { randomUUID } from "node:crypto";
import { NextResponse } from "next/server";
import { eq, inArray } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { accountGroups, accounts, transactions } from "@/db/schema";
import { backfillTransactionEurAmounts } from "@/lib/fx";

export const dynamic = "force-dynamic";

const bodySchema = z.object({
  fromAccountId: z.string().uuid(),
  toAccountId: z.string().uuid(),
  amount: z
    .string()
    .regex(/^\d+(\.\d{1,2})?$/, "amount must be a positive number"),
  bookedAt: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "date must be YYYY-MM-DD"),
  description: z.string().trim().max(500).optional().nullable(),
});

export async function POST(req: Request) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const body = await req.json().catch(() => null);
  const parsed = bodySchema.safeParse(body);
  if (!parsed.success)
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  if (parsed.data.fromAccountId === parsed.data.toAccountId) {
    return NextResponse.json(
      { error: "from and to must be different accounts" },
      { status: 400 },
    );
  }

  const numericAmount = Number(parsed.data.amount);
  if (numericAmount <= 0) {
    return NextResponse.json({ error: "amount must be positive" }, { status: 400 });
  }

  const involved = await db
    .select({
      id: accounts.id,
      currency: accounts.currency,
      archived: accounts.archived,
      spaceId: accounts.spaceId,
      kind: accountGroups.kind,
    })
    .from(accounts)
    .leftJoin(accountGroups, eq(accounts.groupId, accountGroups.id))
    .where(
      inArray(accounts.id, [parsed.data.fromAccountId, parsed.data.toAccountId]),
    );

  const fromAcct = involved.find((a) => a.id === parsed.data.fromAccountId);
  const toAcct = involved.find((a) => a.id === parsed.data.toAccountId);
  if (!fromAcct || !toAcct)
    return NextResponse.json({ error: "account not found" }, { status: 404 });
  if (fromAcct.archived || toAcct.archived)
    return NextResponse.json({ error: "archived account" }, { status: 400 });
  if (fromAcct.kind !== "investment" || toAcct.kind !== "investment")
    return NextResponse.json(
      { error: "both accounts must be in an investment-kind group" },
      { status: 400 },
    );
  if (fromAcct.spaceId !== toAcct.spaceId)
    return NextResponse.json(
      { error: "both accounts must be in the same space" },
      { status: 400 },
    );
  if (fromAcct.currency !== toAcct.currency)
    return NextResponse.json(
      { error: "cross-currency moves are not supported yet" },
      { status: 400 },
    );

  const currency = fromAcct.currency;
  const bookedAt = new Date(parsed.data.bookedAt + "T00:00:00.000Z");
  const transferGroupId = randomUUID();
  const debitExternalId = `manual:${randomUUID()}`;
  const creditExternalId = `manual:${randomUUID()}`;
  const description = parsed.data.description?.trim() || null;
  const signedAmount = numericAmount.toFixed(4);
  const signedDebit = (-numericAmount).toFixed(4);
  // EUR-to-EUR move: amount_eur can be set inline (rate = 1). For other currencies
  // we leave it null and rely on the FX backfill below; the cost-basis math filters
  // on amount_eur is not null, so until backfill runs the move is invisible.
  const isEur = currency === "EUR";
  const amountEurCredit = isEur ? numericAmount.toFixed(2) : null;
  const amountEurDebit = isEur ? (-numericAmount).toFixed(2) : null;

  const rows = await db
    .insert(transactions)
    .values([
      {
        accountId: parsed.data.fromAccountId,
        externalId: debitExternalId,
        bookedAt,
        amount: signedDebit,
        amountEur: amountEurDebit,
        currency,
        direction: "debit",
        description,
        isTransfer: true,
        transferGroupId,
        raw: { source: "manual:investment-move:v1" },
      },
      {
        accountId: parsed.data.toAccountId,
        externalId: creditExternalId,
        bookedAt,
        amount: signedAmount,
        amountEur: amountEurCredit,
        currency,
        direction: "credit",
        description,
        isTransfer: true,
        transferGroupId,
        raw: { source: "manual:investment-move:v1" },
      },
    ])
    .returning({ id: transactions.id });

  let amountEurMissing = false;
  if (!isEur) {
    try {
      const result = await backfillTransactionEurAmounts({ txIds: rows.map((r) => r.id) });
      amountEurMissing = result.updated < rows.length;
    } catch {
      amountEurMissing = true;
    }
  }

  return NextResponse.json({
    ok: true,
    transferGroupId,
    txIds: rows.map((r) => r.id),
    amountEurMissing,
    message: amountEurMissing
      ? "Move recorded. EUR amount will be filled on the next FX sync; cost basis will catch up automatically."
      : undefined,
  });
}
