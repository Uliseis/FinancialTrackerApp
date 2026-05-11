import { NextResponse } from "next/server";
import { desc } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { budgets } from "@/db/schema";

export const dynamic = "force-dynamic";

const createSchema = z.object({
  categoryId: z.string().uuid(),
  amountEur: z.string().regex(/^-?\d+(\.\d{1,2})?$/),
  period: z.enum(["week", "month", "year"]).default("month"),
  startsOn: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  active: z.boolean().default(true),
});

export async function GET() {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const rows = await db.select().from(budgets).orderBy(desc(budgets.createdAt));
  return NextResponse.json({ budgets: rows });
}

export async function POST(req: Request) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const body = await req.json().catch(() => null);
  const parsed = createSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  const [row] = await db.insert(budgets).values(parsed.data).returning();
  return NextResponse.json({ budget: row });
}
