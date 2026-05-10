import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { GoCardlessClient } from "@/lib/gocardless";

export const dynamic = "force-dynamic";

export async function GET(req: Request) {
  const session = await auth();
  if (!session?.user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const { searchParams } = new URL(req.url);
  const country = (searchParams.get("country") ?? "ES").toUpperCase();
  try {
    const client = new GoCardlessClient();
    const list = await client.listInstitutions(country);
    return NextResponse.json({ institutions: list });
  } catch (err) {
    const message = err instanceof Error ? err.message : "unknown";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
