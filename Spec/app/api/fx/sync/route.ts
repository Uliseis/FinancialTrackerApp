import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { backfillTransactionEurAmounts, syncFxRates } from "@/lib/fx";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

async function authorize(req: Request): Promise<boolean> {
  const session = await auth();
  if (session?.user) return true;
  const cronSecret = process.env.CRON_SECRET;
  if (cronSecret) {
    const header = req.headers.get("authorization") ?? "";
    if (header === `Bearer ${cronSecret}`) return true;
  }
  return false;
}

async function run(full: boolean, backfillLimit: number) {
  const fx = await syncFxRates({ full });
  const backfill = await backfillTransactionEurAmounts({ limit: backfillLimit });
  return { fx, backfill };
}

export async function POST(req: Request) {
  if (!(await authorize(req))) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const url = new URL(req.url);
  const full = url.searchParams.get("full") === "1";
  const limit = Number(url.searchParams.get("limit") ?? "10000");
  return NextResponse.json(await run(full, limit));
}

export async function GET(req: Request) {
  if (!(await authorize(req))) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const url = new URL(req.url);
  const full = url.searchParams.get("full") === "1";
  const limit = Number(url.searchParams.get("limit") ?? "10000");
  return NextResponse.json(await run(full, limit));
}
