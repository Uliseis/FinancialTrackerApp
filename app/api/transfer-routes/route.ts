import { NextResponse } from "next/server";
import { desc, asc } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { transferRoutes } from "@/db/schema";
import { RULE_FIELDS, RULE_MATCH_TYPES } from "@/lib/rules";

export const dynamic = "force-dynamic";

const createSchema = z.object({
  pattern: z.string().min(1).max(500),
  targetAccountId: z.string().uuid(),
  sourceAccountId: z.string().uuid().nullable().optional(),
  field: z.enum(RULE_FIELDS).default("description"),
  matchType: z.enum(RULE_MATCH_TYPES).default("contains"),
  direction: z.enum(["debit", "credit"]).nullable().optional(),
  priority: z.number().int().default(0),
  enabled: z.boolean().default(true),
});

export async function GET() {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const rows = await db
    .select()
    .from(transferRoutes)
    .orderBy(desc(transferRoutes.priority), asc(transferRoutes.createdAt));
  return NextResponse.json({ routes: rows });
}

export async function POST(req: Request) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const body = await req.json().catch(() => null);
  const parsed = createSchema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  if (parsed.data.sourceAccountId === parsed.data.targetAccountId) {
    return NextResponse.json(
      { error: "sourceAccountId and targetAccountId must differ" },
      { status: 400 },
    );
  }
  const [row] = await db.insert(transferRoutes).values(parsed.data).returning();
  return NextResponse.json({ route: row });
}
