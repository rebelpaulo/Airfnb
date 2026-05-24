// DEV-ONLY helper: simulate a Stripe payment so you can test the full flow
// without configuring Stripe. Hard-gated by environment + secret header.
import { NextResponse } from "next/server";
import { supabaseServer, supabaseAdmin } from "@/lib/supabase/server";

export const runtime = "nodejs";

/**
 * Gating policy:
 *   - In non-production: always available (developer convenience).
 *   - In production: requires ALL of:
 *       1. ENABLE_DEV_PAY=1
 *       2. DEV_PAY_TOKEN env set (non-empty)
 *       3. Request carries header `x-dev-pay-token` matching DEV_PAY_TOKEN
 *   Any other case returns 404 (indistinguishable from "route not deployed").
 *
 * Even with the env vars set, a leaked token is the only thing an attacker can
 * use — and the response is still constrained to the truck owner's own pending
 * lock fees (verified below). Real payments should always use Stripe.
 */
function isAllowed(req: Request): boolean {
  if (process.env.NODE_ENV !== "production") return true;
  if (process.env.ENABLE_DEV_PAY !== "1") return false;
  const expected = process.env.DEV_PAY_TOKEN;
  if (!expected) return false;
  return req.headers.get("x-dev-pay-token") === expected;
}

export async function POST(req: Request) {
  if (!isAllowed(req)) {
    return new NextResponse(null, { status: 404 });
  }

  const { application_id } = await req.json();
  if (!application_id) {
    return NextResponse.json({ error: "application_id required" }, { status: 400 });
  }

  const sb = await supabaseServer();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return NextResponse.json({ error: "unauthenticated" }, { status: 401 });

  // verify ownership
  const { data: app } = await (sb as any)
    .from("airfnb_applications")
    .select(`id, airfnb_trucks(owner_id), airfnb_lock_fees(id, amount, platform_fee, organizer_share, status)`)
    .eq("id", application_id)
    .maybeSingle();
  if (!app) return NextResponse.json({ error: "not found" }, { status: 404 });
  if (app.airfnb_trucks?.owner_id !== user.id) {
    return NextResponse.json({ error: "forbidden" }, { status: 403 });
  }
  const lf = Array.isArray(app.airfnb_lock_fees) ? app.airfnb_lock_fees[0] : app.airfnb_lock_fees;
  if (!lf || lf.status !== "pending") {
    return NextResponse.json({ error: "no pending lock fee" }, { status: 400 });
  }

  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return NextResponse.json({
      error: "Set SUPABASE_SERVICE_ROLE_KEY in .env.local to use dev-pay (Supabase Dashboard → Project Settings → API)."
    }, { status: 500 });
  }

  const admin = supabaseAdmin();

  // mark lock fee paid
  const upLockFee = await (admin as any).from("airfnb_lock_fees").update({
    status: "paid",
    paid_at: new Date().toISOString(),
    provider_ref: "dev_simulated",
  }).eq("id", lf.id);
  if (upLockFee.error) {
    return NextResponse.json({ error: "lock_fee update failed", detail: upLockFee.error.message }, { status: 500 });
  }

  // record payment row
  const insPayment = await (admin as any).from("airfnb_payments").insert({
    booking_id: null,
    amount: lf.amount,
    currency: "EUR",
    method: "manual",
    direction: "truck_to_platform",
    kind: "lock_fee",
    status: "paid",
    provider_ref: "dev_simulated",
    paid_at: new Date().toISOString(),
  });
  if (insPayment.error) {
    return NextResponse.json({ error: "payment insert failed", detail: insPayment.error.message }, { status: 500 });
  }

  // confirm booking
  const upBooking = await (admin as any)
    .from("airfnb_bookings")
    .update({ status: "confirmed" })
    .eq("application_id", application_id)
    .eq("status", "pending_lock_fee");
  if (upBooking.error) {
    return NextResponse.json({ error: "booking update failed", detail: upBooking.error.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
