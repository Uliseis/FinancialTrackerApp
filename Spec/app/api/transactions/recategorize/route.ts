import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { applyRulesToTransactions } from "@/lib/categorize";

export const dynamic = "force-dynamic";

export async function POST() {
  const session = await auth();
  if (!session?.user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const result = await applyRulesToTransactions();
  return NextResponse.json(result);
}
