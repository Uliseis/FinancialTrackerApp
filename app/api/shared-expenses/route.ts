import { NextResponse } from "next/server";
import { desc, eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db";
import { sharedExpenseGroups, transactions } from "@/db/schema";
import {
  createSharedExpenseGroup,
  findCandidateReimbursements,
  netForGroup,
} from "@/lib/shared-expenses";
import { errorResponse, requireUser } from "@/lib/api-helpers";

export const dynamic = "force-dynamic";

const createSchema = z.object({
  label: z.string().min(1).max(120),
  primaryTxId: z.string().uuid(),
  reimbursementTxIds: z.array(z.string().uuid()).min(1).max(20),
});

export async function GET(req: Request) {
  const unauthorized = await requireUser();
  if (unauthorized) return unauthorized;

  const url = new URL(req.url);
  const txId = url.searchParams.get("txId");
  const candidatesFor = url.searchParams.get("candidatesFor");
  const q = url.searchParams.get("q") ?? "";

  if (candidatesFor) {
    try {
      const rows = await findCandidateReimbursements(candidatesFor, q);
      return NextResponse.json({ candidates: rows });
    } catch (e) {
      return errorResponse(e);
    }
  }

  if (txId) {
    const [tx] = await db
      .select({ sharedExpenseGroupId: transactions.sharedExpenseGroupId })
      .from(transactions)
      .where(eq(transactions.id, txId));
    if (!tx?.sharedExpenseGroupId) return NextResponse.json({ group: null });
    const [group] = await db
      .select()
      .from(sharedExpenseGroups)
      .where(eq(sharedExpenseGroups.id, tx.sharedExpenseGroupId));
    if (!group) return NextResponse.json({ group: null });
    const net = await netForGroup(group.id);
    return NextResponse.json({ group, net });
  }

  const rows = await db
    .select()
    .from(sharedExpenseGroups)
    .orderBy(desc(sharedExpenseGroups.createdAt))
    .limit(100);
  return NextResponse.json({ groups: rows });
}

export async function POST(req: Request) {
  const unauthorized = await requireUser();
  if (unauthorized) return unauthorized;

  const body = await req.json().catch(() => null);
  const parsed = createSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }

  try {
    const group = await createSharedExpenseGroup(parsed.data);
    const net = await netForGroup(group.id);
    return NextResponse.json({ group, net });
  } catch (e) {
    return errorResponse(e);
  }
}
