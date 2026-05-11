import { NextResponse } from "next/server";
import { asc } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { categories } from "@/db/schema";

export const dynamic = "force-dynamic";

const createSchema = z.object({
  name: z.string().min(1).max(120),
  kind: z.enum(["expense", "income"]).default("expense"),
  parentId: z.string().uuid().nullable().optional(),
  color: z.string().max(20).nullable().optional(),
});

export async function GET() {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const rows = await db.select().from(categories).orderBy(asc(categories.name));
  return NextResponse.json({ categories: rows });
}

export async function POST(req: Request) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const body = await req.json().catch(() => null);
  const parsed = createSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  const [row] = await db.insert(categories).values(parsed.data).returning();
  return NextResponse.json({ category: row });
}
