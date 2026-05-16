import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { repairTransferGroups } from "@/lib/transfers";

export const dynamic = "force-dynamic";

export async function POST() {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const result = await repairTransferGroups();
  return NextResponse.json({ ok: true, ...result });
}
