import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { syncAllGocardlessConnections, syncGocardlessConnection } from "@/lib/sync-gocardless";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

async function authorize(req: Request): Promise<boolean> {
  const session = await auth();
  if (session?.user) return true;
  // Vercel cron sends Authorization: Bearer <CRON_SECRET> when configured.
  const cronSecret = process.env.CRON_SECRET;
  if (cronSecret) {
    const header = req.headers.get("authorization") ?? "";
    if (header === `Bearer ${cronSecret}`) return true;
  }
  return false;
}

export async function POST(req: Request) {
  if (!(await authorize(req))) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const body = (await req.json().catch(() => null)) as { connectionId?: string } | null;
  if (body?.connectionId) {
    const result = await syncGocardlessConnection(body.connectionId);
    return NextResponse.json(result);
  }
  const results = await syncAllGocardlessConnections();
  return NextResponse.json({ results });
}

export async function GET(req: Request) {
  // Vercel Cron uses GET. Body-less; sync everything.
  if (!(await authorize(req))) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const results = await syncAllGocardlessConnections();
  return NextResponse.json({ results });
}
