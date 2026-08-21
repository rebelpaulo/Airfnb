import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { StarRating } from "@/components/StarRating";
import { getDictionary } from "@/lib/i18n";

export const dynamic = "force-dynamic";

/**
 * Organizer-side review form: rate each truck involved in a confirmed
 * booking. One row per (booking, truck) in airfnb_reviews. Existing
 * reviews show as read-only so the organizer can see what they already
 * submitted alongside the trucks still pending review.
 */
export default async function AvaliarTrucksPage({
  params,
}: { params: Promise<{ bookingId: string }> }) {
  const { bookingId } = await params;
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect(`/login?next=/dashboard/organizer/avaliar/${bookingId}`);

  const { data: contextRows } = await (supa as any)
    .rpc("airfnb_booking_service_context", { p_booking: bookingId });
  const rows = ((contextRows as any[]) ?? []).filter((row) => row.is_organizer);
  if (rows.length === 0) notFound();
  const booking = {
    id: rows[0].booking_id,
    status: rows[0].booking_status,
    airfnb_events: { title: rows[0].event_title ?? rows[0].request_title },
  };
  if (booking.status !== "confirmed" && booking.status !== "completed") {
    // Reviews only make sense after the event happened — fail loud rather
    // than letting the organizer post on a pending booking.
    redirect("/dashboard/organizer");
  }

  const truckRows = rows.map((row) => ({
    truck_id: row.truck_id,
    agreed_price: row.agreed_price,
    airfnb_trucks: {
      id: row.truck_id,
      name: row.truck_name,
      slug: row.truck_slug,
      base_city: row.truck_base_city,
    },
  }));
  const truckIds = truckRows.map((bt) => bt.truck_id);

  const { data: existingReviews } = await (supa as any)
    .from("airfnb_reviews")
    .select("id, truck_id, rating_food, rating_service, rating_value, rating_overall, body, created_at")
    .eq("booking_id", bookingId)
    .in("truck_id", truckIds);
  const reviewByTruck = new Map<string, any>(((existingReviews as any[]) ?? []).map((r) => [r.truck_id, r]));

  async function submitReview(formData: FormData) {
    "use server";
    const supa = await supabaseServer();
    const dict = await getDictionary();
    const e = dict.dashboard.organizer_review;
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error(e.err_auth);

    const truckId = String(formData.get("truck_id") ?? "");
    const food    = Number(formData.get("rating_food") ?? 0);
    const service = Number(formData.get("rating_service") ?? 0);
    const valueR  = Number(formData.get("rating_value") ?? 0);
    const body    = String(formData.get("body") ?? "").trim();

    if (!truckId)                                                throw new Error(e.err_invalid_truck);
    if (![food, service, valueR].every((n) => n >= 1 && n <= 5)) throw new Error(e.err_rating_range);
    if (body.length < 20)                                        throw new Error(e.err_comment_short);

    // Re-check booking ownership + status server-side (form fields are user-controlled)
    const { data: actionRows } = await (supa as any)
      .rpc("airfnb_booking_service_context", { p_booking: bookingId });
    const actionRow = ((actionRows as any[]) ?? []).find(
      (row) => row.is_organizer && row.truck_id === truckId,
    );
    if (!actionRow) throw new Error(e.err_no_perm);
    if (actionRow.booking_status !== "confirmed" && actionRow.booking_status !== "completed") {
      throw new Error(e.err_booking_status);
    }

    const { error } = await (supa as any).from("airfnb_reviews").insert({
      booking_id:     bookingId,
      truck_id:       truckId,
      rating_food:    food,
      rating_service: service,
      rating_value:   valueR,
      body,
    });
    if (error) {
      if (error.code === "23505") throw new Error(e.err_duplicate_review);
      throw new Error(error.message);
    }
    revalidatePath(`/dashboard/organizer/avaliar/${bookingId}`);
  }

  const dict = await getDictionary();
  const t = dict.dashboard.organizer_review;

  return (
    <div className="dash" style={{ maxWidth: 820 }}>
      <nav className="breadcrumb">
        <Link href="/dashboard/organizer">{t.breadcrumb_dashboard}</Link> &nbsp;/&nbsp; <span>{t.breadcrumb_current}</span>
      </nav>
      <h1 style={{ margin: 0 }}>{t.heading_prefix}{(booking.airfnb_events as any)?.title ?? t.heading_fallback_event}</h1>
      <p style={{ color: "var(--muted)", marginTop: 6 }}>
        {t.subtitle}
      </p>

      <div style={{ display: "grid", gap: 18, marginTop: 22 }}>
        {truckRows.map((bt) => {
          const truck = bt.airfnb_trucks;
          const existing = reviewByTruck.get(bt.truck_id);
          return (
            <section key={bt.truck_id} style={{ background: "#fff", border: "1px solid var(--line)", borderRadius: 14, padding: 22 }}>
              <h2 style={{ margin: 0, fontSize: 20 }}>{truck?.name ?? t.truck_dash}</h2>
              <div style={{ color: "var(--muted)", fontSize: 13, marginTop: 2 }}>
                {truck?.base_city ?? t.truck_dash}
              </div>

              {existing ? (
                <div style={{ marginTop: 14, padding: 14, background: "var(--success-bg)", border: "1px solid var(--success-line)", borderRadius: "var(--radius-sm)" }}>
                  <strong style={{ color: "var(--success-text)" }}>{t.already_rated_prefix}{existing.rating_overall}{t.already_rated_suffix}</strong>
                  <p style={{ marginTop: 8, whiteSpace: "pre-wrap", color: "var(--ink)" }}>{existing.body}</p>
                </div>
              ) : (
                <form action={submitReview} style={{ marginTop: 14, display: "grid", gap: 14 }}>
                  <input type="hidden" name="truck_id" value={bt.truck_id} />
                  <StarRating name="rating_food"    label={t.label_food}    required />
                  <StarRating name="rating_service" label={t.label_service} required />
                  <StarRating name="rating_value"   label={t.label_value}   required />
                  <label style={{ display: "grid", gap: 6 }}>
                    <span style={{ fontSize: 13, fontWeight: 600 }}>{t.label_comment}</span>
                    <textarea name="body" required minLength={20} rows={4}
                      placeholder={t.comment_placeholder} />
                  </label>
                  <div style={{ display: "flex", justifyContent: "flex-end" }}>
                    <button type="submit" className="btn-pill">{t.submit_cta}</button>
                  </div>
                </form>
              )}
            </section>
          );
        })}
      </div>
    </div>
  );
}
