import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { SharedExpenseError } from "@/lib/shared-expenses";

export async function requireUser(): Promise<NextResponse | null> {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  return null;
}

export function errorResponse(e: unknown): NextResponse {
  if (e instanceof SharedExpenseError) {
    return NextResponse.json({ error: e.message }, { status: e.status });
  }
  const msg = e instanceof Error ? e.message : "error";
  return NextResponse.json({ error: msg }, { status: 500 });
}
