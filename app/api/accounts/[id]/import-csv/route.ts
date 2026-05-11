import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { importRevolutCsv } from "@/lib/csv-import";

export const dynamic = "force-dynamic";

const MAX_BYTES = 5 * 1024 * 1024;

export async function POST(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const session = await auth();
  if (!session?.user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { id } = await ctx.params;

  const form = await req.formData().catch(() => null);
  if (!form) return NextResponse.json({ error: "expected multipart form" }, { status: 400 });
  const file = form.get("file");
  if (!(file instanceof File)) {
    return NextResponse.json({ error: "missing file field" }, { status: 400 });
  }
  if (file.size === 0) {
    return NextResponse.json({ error: "empty file" }, { status: 400 });
  }
  if (file.size > MAX_BYTES) {
    return NextResponse.json({ error: "file too large" }, { status: 400 });
  }
  const name = file.name.toLowerCase();
  if (!name.endsWith(".csv") && file.type !== "text/csv" && file.type !== "application/vnd.ms-excel") {
    return NextResponse.json({ error: "expected a .csv file" }, { status: 400 });
  }

  const csvText = await file.text();
  try {
    const result = await importRevolutCsv(id, csvText);
    return NextResponse.json(result);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return NextResponse.json({ error: message }, { status: 400 });
  }
}
