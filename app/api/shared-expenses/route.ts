import { NextResponse } from "next/server";
import { desc, eq } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { sharedExpenseGroups, transactions } from "@/db/schema";
import {
  SharedExpenseError,
  createSharedExpenseGroup,
  findCandidateReimbursements,
  netForGroup,
} from "@/lib/shared-expenses";

export const dynamic = "force-dynamic";

const createSchema = z.object({
  label: z.string().min(1).max(120),
  primaryTxId: z.string().uuid(),
  reimbursementTxIds: z.array(z.string().uuid()).min(1).max(20),
});

export async function GET(req: Request) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const url = new URL(req.url);
  const txId = url.searchParams.get("txId");
  const candidatesFor = url.searchParams.get("candidatesFor");
  const q = url.searchParams.get("q") ?? "";

  if (candidatesFor) {
    try {
      const rows = await findCandidateReimbursements(candidatesFor, q);
      return NextResponse.json({ candidates: rows });
    } catch (e) {
      const status = e instanceof SharedExpenseError ? e.status : 500;
      const msg = e instanceof Error ? e.message : "error";
      return NextResponse.json({ error: msg }, { status });
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
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

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
    if (e instanceof SharedExpenseError) {
      return NextResponse.json({ error: e.message }, { status: e.status });
    }
    const msg = e instanceof Error ? e.message : "error";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
