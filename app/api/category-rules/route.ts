import { NextResponse } from "next/server";
import { desc } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { categoryRules } from "@/db/schema";

export const dynamic = "force-dynamic";

const createSchema = z.object({
  pattern: z.string().min(1).max(500),
  categoryId: z.string().uuid(),
  field: z.enum(["description", "counterparty"]).default("description"),
  matchType: z.enum(["contains", "equals", "startsWith", "endsWith", "regex"]).default("contains"),
  priority: z.number().int().default(0),
});

export async function GET() {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const rows = await db
    .select()
    .from(categoryRules)
    .orderBy(desc(categoryRules.priority));
  return NextResponse.json({ rules: rows });
}

export async function POST(req: Request) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const body = await req.json().catch(() => null);
  const parsed = createSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  const [row] = await db.insert(categoryRules).values(parsed.data).returning();
  return NextResponse.json({ rule: row });
}
