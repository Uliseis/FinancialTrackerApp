import { NextResponse } from "next/server";
import { sql } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db";
import { transactions } from "@/db/schema";
import { RULE_FIELDS, RULE_MATCH_TYPES } from "@/lib/categorize";
import { requireUser } from "@/lib/api-helpers";

export const dynamic = "force-dynamic";

const schema = z.object({
  pattern: z.string().min(1).max(500),
  field: z.enum(RULE_FIELDS).default("description"),
  matchType: z.enum(RULE_MATCH_TYPES).default("contains"),
});

interface SampleRow {
  id: string;
  bookedAt: Date;
  description: string | null;
  counterparty: string | null;
  amount: string;
  currency: string;
  direction: "credit" | "debit";
}

export async function POST(req: Request) {
  const unauthorized = await requireUser();
  if (unauthorized) return unauthorized;

  const body = await req.json().catch(() => null);
  const parsed = schema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  const { pattern, field, matchType } = parsed.data;

  const fieldCol = field === "counterparty" ? transactions.counterparty : transactions.description;

  let predicate;
  if (matchType === "regex") {
    try {
      new RegExp(pattern);
    } catch {
      return NextResponse.json({ error: "invalid regex" }, { status: 400 });
    }
    predicate = sql`coalesce(${fieldCol}, '') ~* ${pattern}`;
  } else {
    const lowered = pattern.toLowerCase();
    const escaped = lowered.replace(/\\/g, "\\\\").replace(/%/g, "\\%").replace(/_/g, "\\_");
    let needle: string;
    switch (matchType) {
      case "equals":
        needle = escaped;
        break;
      case "startsWith":
        needle = escaped + "%";
        break;
      case "endsWith":
        needle = "%" + escaped;
        break;
      case "contains":
      default:
        needle = "%" + escaped + "%";
        break;
    }
    predicate = sql`lower(coalesce(${fieldCol}, '')) like ${needle} escape '\\'`;
  }

  const [[{ count }], samples] = await Promise.all([
    db.select({ count: sql<string>`count(*)` }).from(transactions).where(predicate),
    db
      .select({
        id: transactions.id,
        bookedAt: transactions.bookedAt,
        description: transactions.description,
        counterparty: transactions.counterparty,
        amount: transactions.amount,
        currency: transactions.currency,
        direction: transactions.direction,
      })
      .from(transactions)
      .where(predicate)
      .orderBy(sql`${transactions.bookedAt} desc`)
      .limit(5) as Promise<SampleRow[]>,
  ]);

  return NextResponse.json({ count: Number(count), samples });
}
