import { NextResponse } from "next/server";
import { z } from "zod";
import { addReimbursements, netForGroup } from "@/lib/shared-expenses";
import { errorResponse, requireUser } from "@/lib/api-helpers";

export const dynamic = "force-dynamic";

const postSchema = z.object({
  txIds: z.array(z.string().uuid()).min(1).max(20),
});

export async function POST(req: Request, ctx: { params: Promise<{ groupId: string }> }) {
  const unauthorized = await requireUser();
  if (unauthorized) return unauthorized;
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
    return errorResponse(e);
  }
}
