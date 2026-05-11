import { NextResponse } from "next/server";
import { asc } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { accountSpaces } from "@/db/schema";

export const dynamic = "force-dynamic";

const createSchema = z.object({
  name: z.string().min(1).max(120),
  color: z.string().max(20).nullable().optional(),
  sortOrder: z.number().int().optional(),
});

export async function GET() {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const rows = await db
    .select()
    .from(accountSpaces)
    .orderBy(asc(accountSpaces.sortOrder), asc(accountSpaces.createdAt));
  return NextResponse.json({ spaces: rows });
}

export async function POST(req: Request) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const body = await req.json().catch(() => null);
  const parsed = createSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  const [row] = await db
    .insert(accountSpaces)
    .values({
      name: parsed.data.name,
      color: parsed.data.color ?? null,
      sortOrder: parsed.data.sortOrder ?? 0,
      isDefault: false,
    })
    .returning();
  return NextResponse.json({ space: row });
}
