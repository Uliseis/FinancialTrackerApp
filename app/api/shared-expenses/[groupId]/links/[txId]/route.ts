import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { SharedExpenseError, netForGroup, removeReimbursement } from "@/lib/shared-expenses";

export const dynamic = "force-dynamic";

export async function DELETE(
  _req: Request,
  ctx: { params: Promise<{ groupId: string; txId: string }> },
) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { groupId, txId } = await ctx.params;
  try {
    await removeReimbursement(groupId, txId);
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
