import { NextResponse } from "next/server";
import Stripe from "stripe";
import { supabaseServer, supabaseAdmin } from "@/lib/supabase/server";

export const runtime = "nodejs";

export async function POST(req: Request) {
  if (!process.env.STRIPE_SECRET_KEY || !process.env.APP_URL) {
    return NextResponse.json({ error: "stripe not configured" }, { status: 503 });
  }
  const { application_id } = await req.json();
  if (!application_id) return NextResponse.json({ error: "application_id required" }, { status: 400 });

  const sb = await supabaseServer();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return NextResponse.json({ error: "unauthenticated" }, { status: 401 });

  // load application + lock fee, ensure caller owns the truck
  const { data: app } = await sb
    .from("airfnb_applications")
    .select(`
      id, status, airfnb_trucks ( id, owner_id ),
      airfnb_lock_fees ( id, amount, status )
    `)
    .eq("id", application_id)
    .maybeSingle();
  if (!app) return NextResponse.json({ error: "not found" }, { status: 404 });
  // @ts-expect-error nested
  if (app.airfnb_trucks?.owner_id !== user.id) {
    return NextResponse.json({ error: "forbidden" }, { status: 403 });
  }
  // @ts-expect-error nested
  const lockFee = Array.isArray(app.airfnb_lock_fees) ? app.airfnb_lock_fees[0] : app.airfnb_lock_fees;
  if (!lockFee || lockFee.status !== "pending") {
    return NextResponse.json({ error: "lock fee not pending" }, { status: 400 });
  }

  const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);
  const session = await stripe.checkout.sessions.create({
    mode: "payment",
    payment_method_types: ["card"],
    customer_email: user.email,
    line_items: [
      {
        price_data: {
          currency: "eur",
          unit_amount: Math.round(Number(lockFee.amount) * 100),
          product_data: {
            name: "Air F&B — Lock-fee",
            description: `Confirmação da candidatura ${application_id}`,
          },
        },
        quantity: 1,
      },
    ],
    client_reference_id: application_id,
    metadata: {
      application_id,
      lock_fee_id: lockFee.id,
      booking_id: "",     // populated later via webhook
    },
    success_url: `${process.env.APP_URL}/dashboard/truck?paid=${application_id}`,
    cancel_url:  `${process.env.APP_URL}/dashboard/truck/lock/${application_id}`,
  });

  return NextResponse.json({ url: session.url });
}
