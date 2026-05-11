import { NextResponse } from "next/server";
import { netForGroup, removeReimbursement } from "@/lib/shared-expenses";
import { errorResponse, requireUser } from "@/lib/api-helpers";

export const dynamic = "force-dynamic";

export async function DELETE(
  _req: Request,
  ctx: { params: Promise<{ groupId: string; txId: string }> },
) {
  const unauthorized = await requireUser();
  if (unauthorized) return unauthorized;
  const { groupId, txId } = await ctx.params;
  try {
    await removeReimbursement(groupId, txId);
    const net = await netForGroup(groupId);
    return NextResponse.json({ ok: true, net });
  } catch (e) {
    return errorResponse(e);
  }
}
