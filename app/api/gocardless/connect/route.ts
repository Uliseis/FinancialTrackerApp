import { randomUUID } from "node:crypto";
import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { connections } from "@/db/schema";
import { GoCardlessClient } from "@/lib/gocardless";
import { env } from "@/lib/env";

export const dynamic = "force-dynamic";

export async function POST(req: Request) {
  const session = await auth();
  if (!session?.user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const body = (await req.json().catch(() => null)) as {
    institutionId?: string;
    institutionName?: string;
    maxHistoricalDays?: number;
    accessValidForDays?: number;
  } | null;
  if (!body?.institutionId) {
    return NextResponse.json({ error: "institutionId is required" }, { status: 400 });
  }

  const baseUrl = env.NEXTAUTH_URL.replace(/\/$/, "");
  const reference = randomUUID();

  try {
    const client = new GoCardlessClient();
    const agreement = await client.createAgreement({
      institutionId: body.institutionId,
      maxHistoricalDays: body.maxHistoricalDays ?? 90,
      accessValidForDays: body.accessValidForDays ?? 90,
    });
    const requisition = await client.createRequisition({
      redirect: `${baseUrl}/api/gocardless/callback`,
      institutionId: body.institutionId,
      agreementId: agreement.id,
      reference,
    });

    const expiresAt = new Date();
    expiresAt.setDate(
      expiresAt.getDate() + (body.accessValidForDays ?? agreement.access_valid_for_days),
    );

    await db.insert(connections).values({
      connector: "gocardless",
      institutionId: body.institutionId,
      institutionName: body.institutionName ?? body.institutionId,
      requisitionId: requisition.id,
      status: "pending",
      expiresAt,
      metadata: { reference, agreementId: agreement.id },
    });

    return NextResponse.json({ link: requisition.link, requisitionId: requisition.id });
  } catch (err) {
    const message = err instanceof Error ? err.message : "unknown";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
