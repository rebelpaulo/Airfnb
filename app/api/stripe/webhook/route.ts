// Local Stripe webhook — same logic as supabase/functions/stripe-webhook,
// useful when developing without deploying the edge function.
import { NextResponse } from "next/server";
import Stripe from "stripe";
import { supabaseAdmin } from "@/lib/supabase/server";

export const runtime = "nodejs";

export async function POST(req: Request) {
  const sig = req.headers.get("stripe-signature");
  if (!sig) return NextResponse.json({ error: "missing signature" }, { status: 400 });
  if (!process.env.STRIPE_SECRET_KEY || !process.env.STRIPE_WEBHOOK_SECRET) {
    return NextResponse.json({ error: "stripe not configured" }, { status: 503 });
  }

  const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
  const raw = await req.text();

  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(raw, sig, process.env.STRIPE_WEBHOOK_SECRET);
  } catch (e) {
    return NextResponse.json({ error: "invalid signature", detail: String(e) }, { status: 400 });
  }

  const admin = supabaseAdmin();

  try {
    if (event.type === "checkout.session.completed") {
      const s = event.data.object as Stripe.Checkout.Session;
      const applicationId = s.metadata?.application_id ?? s.client_reference_id;
      if (!applicationId) {
        // Acknowledge so Stripe doesn't retry; but log that we couldn't link it.
        console.warn("stripe-webhook: session.completed without application_id", { session: s.id });
        return NextResponse.json({ received: true, warning: "no application_id in metadata" });
      }

      const piRef = typeof s.payment_intent === "string" ? s.payment_intent : s.payment_intent?.id;

      const upLockFee = await (admin as any)
        .from("airfnb_lock_fees")
        .update({ status: "paid", paid_at: new Date().toISOString(), provider_ref: piRef })
        .eq("application_id", applicationId);
      if (upLockFee.error) throw new Error(`lock_fee update: ${upLockFee.error.message}`);

      // upsert is idempotent on webhook retries (unique index on provider_ref, see migration 14)
      const insPayment = await (admin as any).from("airfnb_payments").upsert({
        booking_id: null,
        amount: (s.amount_total ?? 0) / 100,
        currency: (s.currency ?? "eur").toUpperCase(),
        method: "stripe",
        direction: "truck_to_platform",
        kind: "lock_fee",
        status: "paid",
        provider_ref: piRef,
        paid_at: new Date().toISOString(),
      }, { onConflict: "provider_ref" });
      if (insPayment.error) throw new Error(`payment upsert: ${insPayment.error.message}`);

      const upBooking = await (admin as any)
        .from("airfnb_bookings")
        .update({ status: "confirmed" })
        .eq("application_id", applicationId)
        .eq("status", "pending_lock_fee");
      if (upBooking.error) throw new Error(`booking update: ${upBooking.error.message}`);
    }
  } catch (e) {
    // 5xx so Stripe will retry. Log details for the operator.
    console.error("stripe-webhook handler failed", { type: event.type, error: String(e) });
    return NextResponse.json({ received: false, error: String(e) }, { status: 500 });
  }

  return NextResponse.json({ received: true });
}
