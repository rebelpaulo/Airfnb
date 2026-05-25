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

  // Parallelise — every query is keyed on the user id so RLS will scope.
  const [profile, trucks, requests, applications, bookings, reviewsOrg, reviewsTruck, notifications, messages, lockFees] = await Promise.all([
    (supa as any).from("airfnb_profiles").select("*").eq("id", user.id).maybeSingle(),
    (supa as any).from("airfnb_trucks").select("*").eq("owner_id", user.id),
    (supa as any).from("airfnb_event_requests").select("*").eq("organizer_id", user.id),
    (supa as any).from("airfnb_applications").select("*, airfnb_trucks!inner(owner_id)").eq("airfnb_trucks.owner_id", user.id),
    (supa as any).from("airfnb_bookings").select("*").eq("organizer_id", user.id),
    (supa as any).from("airfnb_reviews").select("*").eq("organizer_id", user.id),
    // organizer_reviews is the truck-rates-organizer direction; authorship
    // is via truck_id → airfnb_trucks.owner_id. Filtering on organizer_id
    // would return reviews ABOUT the user (already covered for organizers
    // by RLS on the underlying table) rather than the ones the user
    // authored as truck owner.
    (supa as any).from("airfnb_organizer_reviews")
      .select("*, airfnb_trucks!inner(owner_id)")
      .eq("airfnb_trucks.owner_id", user.id),
    (supa as any).from("airfnb_notifications").select("*").eq("user_id", user.id),
    (supa as any).from("airfnb_messages").select("*").eq("sender_id", user.id),
    (supa as any).from("airfnb_lock_fees").select("*"),  // RLS scopes to caller
  ]);

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
    trucks_as_owner:         trucks.data ?? [],
    event_requests:          requests.data ?? [],
    applications_as_owner:   applications.data ?? [],
    bookings_as_organizer:   bookings.data ?? [],
    reviews_left_for_trucks: reviewsOrg.data ?? [],
    reviews_left_for_organizers: reviewsTruck.data ?? [],
    notifications:           notifications.data ?? [],
    messages_sent:           messages.data ?? [],
    lock_fees:               lockFees.data ?? [],
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
