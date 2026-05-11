import { randomUUID } from "node:crypto";
import { NextResponse } from "next/server";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { accounts } from "@/db/schema";

export const dynamic = "force-dynamic";

const createManualSchema = z.object({
  name: z.string().min(1).max(120),
  type: z.enum(["bank", "broker", "crypto"]).default("bank"),
  institution: z.string().min(1).max(120),
  currency: z.string().min(3).max(3).default("EUR"),
  groupId: z.string().uuid().nullable().optional(),
  balance: z.string().optional(),
});

export async function POST(req: Request) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const body = await req.json().catch(() => null);
  const parsed = createManualSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  const externalId = `manual:${randomUUID()}`;
  const balance = parsed.data.balance ?? null;
  const [row] = await db
    .insert(accounts)
    .values({
      externalId,
      type: parsed.data.type,
      institution: parsed.data.institution,
      name: parsed.data.name,
      currency: parsed.data.currency.toUpperCase(),
      groupId: parsed.data.groupId ?? null,
      balance,
      manualOpeningBalance: balance,
      balanceUpdatedAt: balance ? new Date() : null,
    })
    .returning();
  return NextResponse.json({ account: row });
}
