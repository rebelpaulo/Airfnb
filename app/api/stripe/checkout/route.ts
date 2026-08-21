import { NextResponse } from "next/server";
import { createLockFeeCheckout } from "@/lib/payments/lock-fee.server";
import { supabaseServer } from "@/lib/supabase/server";

export const runtime = "nodejs";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function POST(req: Request) {
  const sb = await supabaseServer();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthenticated" }, { status: 401 });
  }

  const secretKey = process.env.STRIPE_SECRET_KEY;
  const appUrl = process.env.APP_URL;
  if (!secretKey || !appUrl || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return NextResponse.json({ error: "stripe not configured" }, { status: 503 });
  }

  let applicationId: string;
  try {
    const body = await req.json();
    applicationId = typeof body?.application_id === "string"
      ? body.application_id.trim()
      : "";
  } catch {
    return NextResponse.json({ error: "invalid json" }, { status: 400 });
  }
  if (!UUID_RE.test(applicationId)) {
    return NextResponse.json({ error: "valid application_id required" }, { status: 400 });
  }

  const result = await createLockFeeCheckout({ applicationId, user, supplier: sb });
  if (!result.ok) {
    return NextResponse.json({ error: result.error }, { status: result.status });
  }
  return NextResponse.json(result.value);
}
