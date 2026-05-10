import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { EnableBankingClient } from "@/lib/enablebanking";

export const dynamic = "force-dynamic";

export async function GET(req: Request) {
  const session = await auth();
  if (!session?.user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const { searchParams } = new URL(req.url);
  const country = (searchParams.get("country") ?? "ES").toUpperCase();
  const psuType = (searchParams.get("psuType") ?? "personal") as "personal" | "business";
  try {
    const client = new EnableBankingClient();
    const list = await client.listAspsps({ country, psuType });
    return NextResponse.json({ aspsps: list });
  } catch (err) {
    const message = err instanceof Error ? err.message : "unknown";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
