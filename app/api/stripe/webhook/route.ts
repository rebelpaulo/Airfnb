// Local Stripe webhook — same logic as supabase/functions/stripe-webhook,
// useful when developing without deploying the edge function.
import { NextResponse } from "next/server";
import Stripe from "stripe";
import { supabaseAdmin } from "@/lib/supabase/server";

export const runtime = "nodejs";

export async function POST(req: Request) {
  const sig = req.headers.get("stripe-signature");
  if (!sig) return NextResponse.json({ error: "missing signature" }, { status: 400 });

  const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);
  const raw = await req.text();

  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(raw, sig, process.env.STRIPE_WEBHOOK_SECRET!);
  } catch (e) {
    return NextResponse.json({ error: "invalid signature", detail: String(e) }, { status: 400 });
  }

  const admin = supabaseAdmin();

  if (event.type === "checkout.session.completed") {
    const s = event.data.object as Stripe.Checkout.Session;
    const applicationId = s.metadata?.application_id ?? s.client_reference_id;
    if (applicationId) {
      // mark lock fee paid
      await admin.from("airfnb_lock_fees")
        .update({ status: "paid", paid_at: new Date().toISOString(),
                  provider_ref: typeof s.payment_intent === "string" ? s.payment_intent : s.payment_intent?.id })
        .eq("application_id", applicationId);
      // record payment
      await admin.from("airfnb_payments").insert({
        booking_id: null,
        amount: (s.amount_total ?? 0) / 100,
        currency: (s.currency ?? "eur").toUpperCase(),
        method: "stripe",
        direction: "truck_to_platform",
        kind: "lock_fee",
        status: "paid",
        provider_ref: typeof s.payment_intent === "string" ? s.payment_intent : s.payment_intent?.id,
        paid_at: new Date().toISOString(),
      });
      // confirm booking
      await admin.from("airfnb_bookings")
        .update({ status: "confirmed" })
        .eq("application_id", applicationId)
        .eq("status", "pending_lock_fee");
    }
  }

  return NextResponse.json({ received: true });
}
