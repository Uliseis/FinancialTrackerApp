import { randomUUID } from "node:crypto";
import { NextResponse } from "next/server";
import { eq, inArray } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { accounts, transactions } from "@/db/schema";

export const dynamic = "force-dynamic";

const EUR_TOLERANCE = 0.01;

const bodySchema = z.object({
  txIds: z.array(z.string().uuid()).length(2),
});

export async function POST(req: Request) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const body = await req.json().catch(() => null);
  const parsed = bodySchema.safeParse(body);
  if (!parsed.success)
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  const [idA, idB] = parsed.data.txIds;
  if (idA === idB)
    return NextResponse.json({ error: "txIds must be distinct" }, { status: 400 });

  const rows = await db
    .select({
      id: transactions.id,
      direction: transactions.direction,
      amountEur: transactions.amountEur,
      transferGroupId: transactions.transferGroupId,
      sharedExpenseGroupId: transactions.sharedExpenseGroupId,
      routedFromTxId: transactions.routedFromTxId,
      accountId: transactions.accountId,
      spaceId: accounts.spaceId,
      archived: accounts.archived,
    })
    .from(transactions)
    .leftJoin(accounts, eq(accounts.id, transactions.accountId))
    .where(inArray(transactions.id, parsed.data.txIds));

  if (rows.length !== 2)
    return NextResponse.json({ error: "transaction(s) not found" }, { status: 404 });

  const debit = rows.find((r) => r.direction === "debit");
  const credit = rows.find((r) => r.direction === "credit");
  if (!debit || !credit)
    return NextResponse.json(
      { error: "pair must be exactly one debit + one credit" },
      { status: 400 },
    );

  if (debit.archived || credit.archived)
    return NextResponse.json({ error: "one of the accounts is archived" }, { status: 400 });

  if (debit.spaceId !== credit.spaceId)
    return NextResponse.json(
      {
        error:
          "transactions must be in the same space — cross-space pairs would be auto-unflagged on the next repair run",
      },
      { status: 400 },
    );

  if (debit.sharedExpenseGroupId || credit.sharedExpenseGroupId)
    return NextResponse.json(
      { error: "one of the transactions is already in a shared expense group" },
      { status: 409 },
    );

  if (debit.routedFromTxId || credit.routedFromTxId)
    return NextResponse.json(
      { error: "one of the transactions is a routed mirror — un-route it first" },
      { status: 400 },
    );

  if (debit.amountEur == null || credit.amountEur == null)
    return NextResponse.json(
      { error: "amount_eur not yet backfilled on one of the transactions" },
      { status: 400 },
    );

  const debitEur = Math.abs(Number(debit.amountEur));
  const creditEur = Math.abs(Number(credit.amountEur));
  if (Math.abs(debitEur - creditEur) > EUR_TOLERANCE)
    return NextResponse.json(
      {
        error: `amounts differ by more than €${EUR_TOLERANCE.toFixed(2)}: ${debitEur.toFixed(2)} vs ${creditEur.toFixed(2)}`,
      },
      { status: 400 },
    );

  const groupId = debit.transferGroupId ?? credit.transferGroupId ?? randomUUID();

  await db
    .update(transactions)
    .set({ isTransfer: true, transferGroupId: groupId })
    .where(inArray(transactions.id, [debit.id, credit.id]));

  return NextResponse.json({ ok: true, transferGroupId: groupId });
}
