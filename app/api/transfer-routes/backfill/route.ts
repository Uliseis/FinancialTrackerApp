import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { applyTransferRoutes } from "@/lib/transfer-routes";

export const dynamic = "force-dynamic";

export async function POST() {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const result = await applyTransferRoutes({ sinceDays: 730 });
  return NextResponse.json({ ok: true, ...result });
}
