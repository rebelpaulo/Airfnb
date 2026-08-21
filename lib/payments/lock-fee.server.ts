import "server-only";

import type { User } from "@supabase/supabase-js";
import Stripe from "stripe";
import { normalizeAppOrigin } from "@/lib/app-url.mjs";
import { supabaseAdmin, supabaseServer } from "@/lib/supabase/server";

type SupplierClient = Awaited<ReturnType<typeof supabaseServer>>;

type ServiceFailure = {
  ok: false;
  status: number;
  error: string;
};

type ServiceSuccess<T> = {
  ok: true;
  value: T;
};

export type LockFeeServiceResult<T> = ServiceSuccess<T> | ServiceFailure;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function failure(status: number, error: string): ServiceFailure {
  return { ok: false, status, error };
}

function amountToMinorUnits(value: unknown): number | null {
  const amount = typeof value === "number" ? value : Number(value);
  const minor = Math.round(amount * 100);
  return Number.isFinite(amount) && Number.isSafeInteger(minor) && minor > 0
    ? minor
    : null;
}

export async function createLockFeeCheckout({
  applicationId,
  user,
  supplier,
}: {
  applicationId: string;
  user: User;
  supplier: SupplierClient;
}): Promise<LockFeeServiceResult<{ url: string }>> {
  const secretKey = process.env.STRIPE_SECRET_KEY;
  const configuredAppUrl = process.env.APP_URL;
  if (!secretKey || !configuredAppUrl || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return failure(503, "stripe not configured");
  }
  if (!UUID_RE.test(applicationId)) {
    return failure(400, "valid application_id required");
  }

  const appUrl = normalizeAppOrigin(configuredAppUrl);
  if (!appUrl) {
    return failure(503, "invalid app configuration");
  }

  // The Marketplace RPC proves supplier ownership without reopening SELECT
  // access to the protected truck owner_id column.
  const { data: lockContexts, error: contextError } = await (supplier as any).rpc(
    "airfnb_supplier_lock_fee",
    { p_application: applicationId },
  );
  if (contextError) {
    return failure(409, "payment context unavailable");
  }
  if (!Array.isArray(lockContexts) || lockContexts.length !== 1) {
    return failure(404, "not found");
  }
  const lockFee = {
    ...lockContexts[0],
    id: lockContexts[0].lock_fee_id,
    status: lockContexts[0].lock_fee_status,
  };
  const application = { status: lockFee.application_status };
  if (application.status !== "accepted") {
    return failure(409, "application not accepted");
  }

  const admin = supabaseAdmin();
  const { data: bookings, error: bookingError } = await (admin as any)
    .from("airfnb_bookings")
    .select("id,application_id,status,currency")
    .eq("application_id", applicationId)
    .limit(2);

  if (bookingError || bookings?.length !== 1) {
    return failure(409, "payment linkage not found");
  }
  const booking = bookings[0];
  if (
    lockFee.application_id !== applicationId ||
    booking.application_id !== applicationId ||
    lockFee.status !== "pending" ||
    booking.status !== "pending_lock_fee"
  ) {
    return failure(409, "payment is not pending");
  }

  const amountMinor = amountToMinorUnits(lockFee.amount);
  const currency = typeof lockFee.currency === "string"
    ? lockFee.currency.trim().toUpperCase()
    : "";
  if (!amountMinor || currency !== "EUR" || booking.currency?.trim().toUpperCase() !== "EUR") {
    return failure(409, "invalid payment amount or currency");
  }

  const nowSeconds = Math.floor(Date.now() / 1000);
  const dueSeconds = Math.floor(Date.parse(lockFee.due_until) / 1000);
  if (!Number.isFinite(dueSeconds) || dueSeconds < nowSeconds + 31 * 60) {
    return failure(409, "lock fee expired or too close to expiry");
  }
  const customExpiresAt = dueSeconds <= nowSeconds + 24 * 60 * 60
    ? dueSeconds
    : undefined;

  const metadata = {
    application_id: applicationId,
    lock_fee_id: lockFee.id,
    booking_id: booking.id,
  };
  const successUrl = new URL("/dashboard/truck", appUrl);
  successUrl.searchParams.set("paid", applicationId);
  const cancelUrl = new URL(`/dashboard/truck/lock/${applicationId}`, appUrl);

  try {
    const stripe = new Stripe(secretKey, {
      apiVersion: "2025-02-24.acacia",
    });
    const session = await stripe.checkout.sessions.create(
      {
        mode: "payment",
        payment_method_types: ["card"],
        customer_email: user.email,
        line_items: [
          {
            price_data: {
              currency: "eur",
              unit_amount: amountMinor,
              product_data: {
                name: "F&B Tailor — Lock-fee",
                description: `Confirmação da candidatura ${applicationId}`,
              },
            },
            quantity: 1,
          },
        ],
        client_reference_id: applicationId,
        metadata,
        payment_intent_data: { metadata },
        ...(customExpiresAt ? { expires_at: customExpiresAt } : {}),
        success_url: successUrl.toString(),
        cancel_url: cancelUrl.toString(),
      },
      { idempotencyKey: `airfnb-lock-fee-${lockFee.id}` },
    );

    if (!session.url) {
      return failure(502, "checkout unavailable");
    }
    return { ok: true, value: { url: session.url } };
  } catch {
    return failure(502, "checkout creation failed");
  }
}

export async function markLockFeePaidDev({
  applicationId,
  supplier,
}: {
  applicationId: string;
  supplier: SupplierClient;
}): Promise<LockFeeServiceResult<{ reconciliation: unknown }>> {
  // This boundary is called directly by a Server Action as well as the local
  // API, so it must fail closed before any database access in production.
  if (process.env.NODE_ENV === "production") {
    return failure(404, "not found");
  }
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return failure(503, "dev payment is not configured");
  }
  if (!UUID_RE.test(applicationId)) {
    return failure(400, "valid application_id required");
  }

  const { data: lockContexts, error: contextError } = await (supplier as any).rpc(
    "airfnb_supplier_lock_fee",
    { p_application: applicationId },
  );
  if (contextError) {
    return failure(409, "payment context unavailable");
  }
  if (!Array.isArray(lockContexts) || lockContexts.length !== 1) {
    return failure(404, "not found");
  }
  const lockFee = lockContexts[0];
  if (lockFee.application_status !== "accepted") {
    return failure(409, "application not accepted");
  }

  const admin = supabaseAdmin();
  const { data: bookings, error: bookingError } = await (admin as any)
    .from("airfnb_bookings")
    .select("id,application_id,status,currency,created_at")
    .eq("application_id", applicationId)
    .limit(2);
  if (bookingError || bookings?.length !== 1) {
    return failure(409, "payment linkage not found");
  }

  const booking = bookings[0];
  const amountMinor = amountToMinorUnits(lockFee.amount);
  const currency = typeof lockFee.currency === "string" ? lockFee.currency.trim() : "";
  const dueAt = Date.parse(lockFee.due_until);
  const eventCreatedAt = typeof booking.created_at === "string" ? booking.created_at : "";
  const createdAt = Date.parse(eventCreatedAt);
  if (
    lockFee.application_id !== applicationId ||
    booking.application_id !== applicationId ||
    lockFee.lock_fee_status !== "pending" ||
    booking.status !== "pending_lock_fee" ||
    !amountMinor ||
    currency.toUpperCase() !== "EUR" ||
    booking.currency?.trim().toUpperCase() !== "EUR" ||
    !Number.isFinite(dueAt) ||
    dueAt <= Date.now() ||
    !Number.isFinite(createdAt)
  ) {
    return failure(409, "payment is not pending or valid");
  }

  const stableReference = `dev-lock-fee-${lockFee.lock_fee_id}`;
  const { data, error } = await (admin as any).rpc(
    "airfnb_reconcile_stripe_event",
    {
      p_event_id: stableReference,
      p_event_type: "checkout.session.completed",
      p_event_created_at: eventCreatedAt,
      p_application_id: applicationId,
      p_lock_fee_id: lockFee.lock_fee_id,
      p_booking_id: booking.id,
      p_payment_intent: stableReference,
      p_amount_minor: amountMinor,
      p_currency: "EUR",
      p_payment_status: "paid",
      p_refunded_amount_minor: 0,
    },
  );
  if (error) {
    return failure(500, "dev payment reconciliation failed");
  }

  return { ok: true, value: { reconciliation: data } };
}
