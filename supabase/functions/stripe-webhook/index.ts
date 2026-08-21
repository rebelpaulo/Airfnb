// Stripe Edge webhook. All financial state transitions happen inside
// airfnb_reconcile_stripe_event, the same atomic RPC used by the Next endpoint.
// Required secrets: STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY.

import Stripe from "https://esm.sh/stripe@17.7.0?target=denonext";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { json } from "../_shared/cors.ts";

const METADATA_KEYS = ["application_id", "lock_fee_id", "booking_id"] as const;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
type Metadata = Record<string, string> | null | undefined;

function paymentIntentId(value: string | Stripe.PaymentIntent | null): string {
  const id = typeof value === "string" ? value : value?.id;
  if (!id) throw new Error("missing payment intent");
  return id;
}

function resolveMetadata(primary: Metadata, fallback: Metadata) {
  const result: Record<(typeof METADATA_KEYS)[number], string> = {
    application_id: "",
    lock_fee_id: "",
    booking_id: "",
  };
  for (const key of METADATA_KEYS) {
    const direct = primary?.[key]?.trim();
    const inherited = fallback?.[key]?.trim();
    if (direct && inherited && direct !== inherited) {
      throw new Error("conflicting reconciliation metadata");
    }
    const value = direct || inherited || "";
    if (!UUID_RE.test(value)) throw new Error("incomplete reconciliation metadata");
    result[key] = value;
  }
  return result;
}

function eventTime(event: Stripe.Event): string {
  if (!Number.isInteger(event.created) || event.created <= 0) {
    throw new Error("invalid event time");
  }
  return new Date(event.created * 1000).toISOString();
}

async function reconciliationArgs(stripe: Stripe, event: Stripe.Event) {
  if (event.type === "checkout.session.completed") {
    const session = event.data.object as Stripe.Checkout.Session;
    const intentId = paymentIntentId(session.payment_intent);
    const intentMetadata = (await stripe.paymentIntents.retrieve(intentId)).metadata;
    const metadata = resolveMetadata(session.metadata, intentMetadata);
    if (session.payment_status !== "paid" || !session.amount_total || !session.currency) {
      throw new Error("checkout session is not paid or complete");
    }
    return {
      p_event_id: event.id,
      p_event_type: event.type,
      p_event_created_at: eventTime(event),
      p_application_id: metadata.application_id,
      p_lock_fee_id: metadata.lock_fee_id,
      p_booking_id: metadata.booking_id,
      p_payment_intent: intentId,
      p_amount_minor: session.amount_total,
      p_currency: session.currency,
      p_payment_status: session.payment_status,
      p_refunded_amount_minor: 0,
    };
  }

  if (event.type === "charge.refunded") {
    const charge = event.data.object as Stripe.Charge;
    const intentId = paymentIntentId(charge.payment_intent);
    const intentMetadata = (await stripe.paymentIntents.retrieve(intentId)).metadata;
    const metadata = resolveMetadata(charge.metadata, intentMetadata);
    if (charge.status !== "succeeded" || charge.amount <= 0 || charge.amount_refunded <= 0 || !charge.currency) {
      throw new Error("refund charge is not complete");
    }
    return {
      p_event_id: event.id,
      p_event_type: event.type,
      p_event_created_at: eventTime(event),
      p_application_id: metadata.application_id,
      p_lock_fee_id: metadata.lock_fee_id,
      p_booking_id: metadata.booking_id,
      p_payment_intent: intentId,
      p_amount_minor: charge.amount,
      p_currency: charge.currency,
      p_payment_status: charge.status,
      p_refunded_amount_minor: charge.amount_refunded,
    };
  }

  throw new Error("unsupported event");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const signature = req.headers.get("stripe-signature");
  if (!signature) return json({ error: "missing stripe-signature" }, 400);

  const secretKey = Deno.env.get("STRIPE_SECRET_KEY");
  const signingSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!secretKey || !signingSecret || !supabaseUrl || !serviceRoleKey) {
    return json({ error: "stripe not configured" }, 503);
  }

  const stripe = new Stripe(secretKey, {
    apiVersion: "2025-02-24.acacia",
    httpClient: Stripe.createFetchHttpClient(),
  });
  const raw = await req.text();
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      raw,
      signature,
      signingSecret,
      undefined,
      Stripe.createSubtleCryptoProvider(),
    );
  } catch {
    return json({ error: "invalid signature" }, 400);
  }

  if (event.type !== "checkout.session.completed" && event.type !== "charge.refunded") {
    return json({ received: true, ignored: true });
  }

  try {
    const args = await reconciliationArgs(stripe, event);
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { error } = await supabase.rpc("airfnb_reconcile_stripe_event", args);
    if (error) throw new Error("database reconciliation failed");
    return json({ received: true });
  } catch {
    // Never log the signed body, customer data, secrets or database details.
    // Stripe receives a 500 so an unresolved/out-of-order event is retried.
    console.error("stripe reconciliation failed", { event_id: event.id, type: event.type });
    return json({ received: false, error: "reconciliation failed" }, 500);
  }
});
