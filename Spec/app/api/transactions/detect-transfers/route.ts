import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { detectTransfers } from "@/lib/transfers";

export const dynamic = "force-dynamic";

export async function POST(req: Request) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const url = new URL(req.url);
  const sinceDays = Number(url.searchParams.get("sinceDays") ?? "30");
  const result = await detectTransfers({ sinceDays });
  return NextResponse.json(result);
}
