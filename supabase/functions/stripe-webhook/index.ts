// supabase/functions/stripe-webhook/index.ts
//
// Receives Stripe webhook events and reconciles airfnb_bookings + airfnb_payments.
//
// Required env (`supabase secrets set …`):
//   STRIPE_SECRET_KEY              — sk_live_… / sk_test_…
//   STRIPE_WEBHOOK_SECRET          — whsec_… from the Stripe webhook endpoint
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY — provided automatically
//
// Stripe dashboard → Developers → Webhooks → add endpoint
//   https://<project-ref>.functions.supabase.co/stripe-webhook
//   events:
//     - checkout.session.completed
//     - payment_intent.succeeded
//     - payment_intent.payment_failed
//     - charge.refunded
//
// Pattern: when you create the Stripe Checkout Session pass:
//   client_reference_id = booking_id (UUID)
//   metadata.booking_id  = booking_id
// so we can map events back to our DB.

import Stripe from "https://esm.sh/stripe@14.21.0?target=denonext";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { json } from "../_shared/cors.ts";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2024-06-20",
  httpClient: Stripe.createFetchHttpClient(),
});
const cryptoProvider = Stripe.createSubtleCryptoProvider();

const supa = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const SIGNING_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const signature = req.headers.get("stripe-signature");
  if (!signature) return json({ error: "missing stripe-signature" }, 400);

  const raw = await req.text();
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      raw, signature, SIGNING_SECRET, undefined, cryptoProvider,
    );
  } catch (e) {
    return json({ error: "invalid signature", detail: String(e) }, 400);
  }

  try {
    switch (event.type) {
      case "checkout.session.completed":      await onSessionCompleted(event); break;
      case "payment_intent.succeeded":        await onPaymentSucceeded(event); break;
      case "payment_intent.payment_failed":   await onPaymentFailed(event);    break;
      case "charge.refunded":                 await onRefunded(event);         break;
      default:
        await log("stripe.unhandled", { type: event.type });
    }
  } catch (e) {
    console.error("handler failed", event.type, e);
    return json({ received: true, error: String(e) }, 500);
  }
  return json({ received: true });
});

// ---- handlers ---------------------------------------------------------------
async function onSessionCompleted(ev: Stripe.Event) {
  const s = ev.data.object as Stripe.Checkout.Session;
  const bookingId = s.client_reference_id ?? s.metadata?.booking_id;
  if (!bookingId) return;

  await supa.from("airfnb_payments").insert({
    booking_id: bookingId,
    amount: (s.amount_total ?? 0) / 100,
    currency: (s.currency ?? "eur").toUpperCase(),
    method: "stripe",
    status: "paid",
    provider_ref: typeof s.payment_intent === "string" ? s.payment_intent : s.payment_intent?.id,
    paid_at: new Date().toISOString(),
  });

  await supa.from("airfnb_bookings")
    .update({ status: "paid" })
    .eq("id", bookingId)
    .in("status", ["confirmed", "accepted", "proposal_sent", "inquiry"]);

  await enqueueEmail("payment_received", { booking_id: bookingId, amount: (s.amount_total ?? 0) / 100 });
  await log("stripe.session_completed", { booking_id: bookingId });
}

async function onPaymentSucceeded(ev: Stripe.Event) {
  const pi = ev.data.object as Stripe.PaymentIntent;
  const bookingId = pi.metadata?.booking_id;
  if (!bookingId) return;
  await supa.from("airfnb_payments")
    .update({ status: "paid", paid_at: new Date().toISOString() })
    .eq("provider_ref", pi.id);
  await log("stripe.payment_succeeded", { booking_id: bookingId, pi: pi.id });
}

async function onPaymentFailed(ev: Stripe.Event) {
  const pi = ev.data.object as Stripe.PaymentIntent;
  await supa.from("airfnb_payments")
    .update({ status: "failed" })
    .eq("provider_ref", pi.id);
  await log("stripe.payment_failed", { pi: pi.id, last_error: pi.last_payment_error?.message });
}

async function onRefunded(ev: Stripe.Event) {
  const ch = ev.data.object as Stripe.Charge;
  const bookingId = ch.metadata?.booking_id;
  await supa.from("airfnb_payments")
    .update({ status: "refunded" })
    .eq("provider_ref", ch.payment_intent as string);
  if (bookingId) {
    await supa.from("airfnb_bookings").update({ status: "refunded" }).eq("id", bookingId);
    await enqueueEmail("booking_cancelled", { booking_id: bookingId, refund: (ch.amount_refunded ?? 0) / 100 });
  }
  await log("stripe.refunded", { charge: ch.id });
}

// ---- helpers ----------------------------------------------------------------
async function enqueueEmail(template: string, data: Record<string, unknown>) {
  // best-effort: call our own send-email function with the service role key
  try {
    await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/send-email`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "authorization": `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
      },
      body: JSON.stringify({ to: "ops@airfnb.local", template, data }),
    });
  } catch (_) { /* swallow */ }
}

async function log(action: string, diff: Record<string, unknown>) {
  await supa.from("airfnb_audit_log").insert({ action, entity: "stripe", diff });
}
