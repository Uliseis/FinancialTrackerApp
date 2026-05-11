import { NextResponse } from "next/server";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { SharedExpenseError, addReimbursements, netForGroup } from "@/lib/shared-expenses";

export const dynamic = "force-dynamic";

const postSchema = z.object({
  txIds: z.array(z.string().uuid()).min(1).max(20),
});

export async function POST(req: Request, ctx: { params: Promise<{ groupId: string }> }) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { groupId } = await ctx.params;
  const body = await req.json().catch(() => null);
  const parsed = postSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }
  try {
    await addReimbursements(groupId, parsed.data.txIds);
    const net = await netForGroup(groupId);
    return NextResponse.json({ ok: true, net });
  } catch (e) {
    if (e instanceof SharedExpenseError) {
      return NextResponse.json({ error: e.message }, { status: e.status });
    }
    const msg = e instanceof Error ? e.message : "error";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
