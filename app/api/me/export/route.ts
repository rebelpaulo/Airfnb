// GDPR Article 15 — right of access. Returns a JSON archive of everything
// the platform stores about the calling user. Auth-gated; the user can
// only export their own data (we don't expose other parties' messages
// even within shared conversations beyond the body the user already saw).
import { NextResponse } from "next/server";
import { supabaseServer } from "@/lib/supabase/server";

export const runtime = "nodejs";

export async function GET() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthenticated" }, { status: 401 });
  }

  // Parallelise. Supplier-owned collections cross the closed owner_id
  // boundary through a bounded, owner-scoped SECURITY DEFINER projection.
  const [profile, requests, bookings, reviewsOrg, notifications, messages, supplierExport] = await Promise.all([
    (supa as any).from("airfnb_profiles").select("*").eq("id", user.id).maybeSingle(),
    (supa as any).rpc("airfnb_private_event_requests", { p_request_id: null }),
    (supa as any).from("airfnb_bookings").select("*").eq("organizer_id", user.id),
    (supa as any).from("airfnb_reviews").select("*").eq("organizer_id", user.id),
    (supa as any).from("airfnb_notifications").select("*").eq("user_id", user.id),
    (supa as any).from("airfnb_messages").select("*").eq("sender_id", user.id),
    (supa as any).rpc("airfnb_supplier_export_data"),
  ]);

  if (supplierExport.error) {
    return NextResponse.json({ error: "export_failed" }, { status: 500 });
  }
  const supplierData = (supplierExport.data ?? {}) as Record<string, unknown>;

  const archive = {
    exported_at: new Date().toISOString(),
    schema_version: 1,
    note: "Esta exportação satisfaz o teu direito de acesso (GDPR Art. 15). " +
          "Inclui apenas os dados pessoais que processamos sobre ti.",
    auth: {
      id:    user.id,
      email: user.email,
      created_at: user.created_at,
      last_sign_in_at: (user as any).last_sign_in_at,
    },
    profile:                 profile.data,
    trucks_as_owner:         supplierData.trucks_as_owner ?? [],
    event_requests:          requests.data ?? [],
    applications_as_owner:   supplierData.applications_as_owner ?? [],
    bookings_as_organizer:   bookings.data ?? [],
    reviews_left_for_trucks: reviewsOrg.data ?? [],
    reviews_left_for_organizers: supplierData.reviews_left_for_organizers ?? [],
    notifications:           notifications.data ?? [],
    messages_sent:           messages.data ?? [],
    lock_fees:               supplierData.lock_fees ?? [],
  };

  const filename = `airfnb-export-${user.id.slice(0, 8)}-${new Date().toISOString().slice(0, 10)}.json`;
  return new NextResponse(JSON.stringify(archive, null, 2), {
    status: 200,
    headers: {
      "content-type":        "application/json; charset=utf-8",
      "content-disposition": `attachment; filename="${filename}"`,
      "cache-control":       "no-store",
    },
  });
}
