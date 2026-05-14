import { NextResponse } from "next/server";
import { eq, sql } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { accountGroups, accounts, portfolioValuations } from "@/db/schema";

export const dynamic = "force-dynamic";

const createSchema = z.object({
  accountId: z.string().uuid(),
  asOf: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  marketValueEur: z.string().regex(/^\d+(\.\d{1,2})?$/),
  notes: z.string().trim().max(500).optional().nullable(),
});

async function isInvestmentAccount(accountId: string): Promise<boolean> {
  const [row] = await db
    .select({ kind: accountGroups.kind })
    .from(accounts)
    .innerJoin(accountGroups, eq(accounts.groupId, accountGroups.id))
    .where(eq(accounts.id, accountId))
    .limit(1);
  return row?.kind === "investment";
}

export async function POST(req: Request) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const body = await req.json().catch(() => null);
  const parsed = createSchema.safeParse(body);
  if (!parsed.success)
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  if (!(await isInvestmentAccount(parsed.data.accountId))) {
    return NextResponse.json(
      { error: "account is not in an investment-kind group" },
      { status: 400 },
    );
  }

  const asOf = new Date(parsed.data.asOf + "T00:00:00.000Z");
  const notes = parsed.data.notes?.trim() ? parsed.data.notes.trim() : null;

  const [row] = await db
    .insert(portfolioValuations)
    .values({
      accountId: parsed.data.accountId,
      asOf,
      marketValueEur: parsed.data.marketValueEur,
      notes,
    })
    .onConflictDoUpdate({
      target: [portfolioValuations.accountId, portfolioValuations.asOf],
      set: {
        marketValueEur: parsed.data.marketValueEur,
        notes,
        updatedAt: sql`now()`,
      },
    })
    .returning();

  return NextResponse.json({ valuation: row });
}
