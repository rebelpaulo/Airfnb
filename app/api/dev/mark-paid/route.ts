// DEV-ONLY helper: simulate Stripe payment so you can test the full flow
// without actually configuring Stripe. Disable by removing this route in prod.
import { NextResponse } from "next/server";
import { supabaseServer, supabaseAdmin } from "@/lib/supabase/server";

export const runtime = "nodejs";

export async function POST(req: Request) {
  const { application_id } = await req.json();
  if (!application_id) return NextResponse.json({ error: "application_id required" }, { status: 400 });

  const sb = await supabaseServer();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return NextResponse.json({ error: "unauthenticated" }, { status: 401 });

  // verify ownership
  const { data: app } = await sb
    .from("airfnb_applications")
    .select(`id, airfnb_trucks(owner_id), airfnb_lock_fees(id, amount, platform_fee, organizer_share, status)`)
    .eq("id", application_id)
    .maybeSingle();
  if (!app) return NextResponse.json({ error: "not found" }, { status: 404 });
  // @ts-expect-error nested
  if (app.airfnb_trucks?.owner_id !== user.id) {
    return NextResponse.json({ error: "forbidden" }, { status: 403 });
  }
  // @ts-expect-error nested
  const lf = Array.isArray(app.airfnb_lock_fees) ? app.airfnb_lock_fees[0] : app.airfnb_lock_fees;
  if (!lf || lf.status !== "pending") return NextResponse.json({ error: "no pending lock fee" }, { status: 400 });

  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return NextResponse.json({
      error: "Set SUPABASE_SERVICE_ROLE_KEY in .env.local to use dev-pay (find it in Supabase Dashboard → Project Settings → API)."
    }, { status: 500 });
  }

  const admin = supabaseAdmin();
  // mark lock fee paid
  await admin.from("airfnb_lock_fees").update({
    status: "paid",
    paid_at: new Date().toISOString(),
    provider_ref: "dev_simulated",
  }).eq("id", lf.id);

  // record payment row
  await admin.from("airfnb_payments").insert({
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

  // confirm booking
  await admin
    .from("airfnb_bookings")
    .update({ status: "confirmed" })
    .eq("application_id", application_id)
    .eq("status", "pending_lock_fee");

  return NextResponse.json({ ok: true });
}
