import { randomUUID } from "node:crypto";
import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { connections } from "@/db/schema";
import { EnableBankingClient } from "@/lib/enablebanking";
import { env } from "@/lib/env";

export const dynamic = "force-dynamic";

const DEFAULT_VALIDITY_DAYS = 90;

function psuHeadersFromRequest(req: Request) {
  return {
    ipAddress:
      req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
      req.headers.get("x-real-ip") ??
      undefined,
    userAgent: req.headers.get("user-agent") ?? undefined,
  };
}

export async function POST(req: Request) {
  const session = await auth();
  if (!session?.user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const body = (await req.json().catch(() => null)) as {
    aspspName?: string;
    aspspCountry?: string;
    psuType?: "personal" | "business";
    validForDays?: number;
    connectionId?: string;
    language?: string;
  } | null;
  if (!body?.aspspName || !body?.aspspCountry) {
    return NextResponse.json(
      { error: "aspspName and aspspCountry are required" },
      { status: 400 },
    );
  }

  const validUntil = new Date();
  validUntil.setDate(validUntil.getDate() + (body.validForDays ?? DEFAULT_VALIDITY_DAYS));
  const state = randomUUID();

  try {
    const client = new EnableBankingClient(psuHeadersFromRequest(req));
    const auth_ = await client.startAuth({
      access: {
        valid_until: validUntil.toISOString(),
        balances: true,
        transactions: true,
      },
      aspsp: { name: body.aspspName, country: body.aspspCountry },
      state,
      redirect_url: env.ENABLEBANKING_REDIRECT_URL,
      psu_type: body.psuType ?? "personal",
      language: body.language,
    });

    if (body.connectionId) {
      await db
        .update(connections)
        .set({
          institutionId: body.aspspName,
          institutionName: body.aspspName,
          status: "pending",
          expiresAt: validUntil,
          metadata: {
            state,
            authorizationId: auth_.authorization_id,
            country: body.aspspCountry,
            psuType: body.psuType ?? "personal",
          },
          updatedAt: new Date(),
        })
        .where(eq(connections.id, body.connectionId));
    } else {
      await db.insert(connections).values({
        connector: "enablebanking",
        institutionId: body.aspspName,
        institutionName: body.aspspName,
        status: "pending",
        expiresAt: validUntil,
        metadata: {
          state,
          authorizationId: auth_.authorization_id,
          country: body.aspspCountry,
          psuType: body.psuType ?? "personal",
        },
      });
    }

    return NextResponse.json({ link: auth_.url, state, authorizationId: auth_.authorization_id });
  } catch (err) {
    const message = err instanceof Error ? err.message : "unknown";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
