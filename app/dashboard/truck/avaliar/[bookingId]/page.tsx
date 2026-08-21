import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { StarRating } from "@/components/StarRating";
import { getDictionary } from "@/lib/i18n";

export const dynamic = "force-dynamic";

/**
 * Truck-side review form: the truck rates the organizer of a confirmed
 * booking. The owner may have multiple trucks under the same booking
 * (rare but possible for multi-truck events) — we list each one separately.
 */
export default async function AvaliarOrganizerPage({
  params,
}: { params: Promise<{ bookingId: string }> }) {
  const { bookingId } = await params;
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect(`/login?next=/dashboard/truck/avaliar/${bookingId}`);

  const dict = await getDictionary();
  const t = dict.dashboard.truck_review;

  const { data: bookingRows } = await (supa as any)
    .rpc("airfnb_booking_service_context", { p_booking: bookingId });
  const ownedRows = ((bookingRows as any[]) ?? []).filter((row) => row.is_owned);
  const booking = ownedRows[0];
  if (!booking) notFound();
  if (booking.booking_status !== "confirmed" && booking.booking_status !== "completed") {
    redirect("/dashboard/truck");
  }

  // The RPC performs the owner-scoped join without exposing owner_id.
  const myTrucks = ownedRows.map((row) => ({
    truck_id: row.truck_id,
    agreed_price: row.agreed_price,
    airfnb_trucks: {
      id: row.truck_id,
      name: row.truck_name,
      slug: row.truck_slug,
    },
  }));
  if (myTrucks.length === 0) redirect("/dashboard/truck");

  const truckIds = myTrucks.map((bt) => bt.truck_id);

  const { data: existingReviews } = await (supa as any)
    .from("airfnb_organizer_reviews")
    .select("id, truck_id, rating_reliability, rating_communication, rating_payment, rating_overall, body, created_at")
    .eq("booking_id", bookingId)
    .in("truck_id", truckIds);
  const reviewByTruck = new Map<string, any>(((existingReviews as any[]) ?? []).map((r) => [r.truck_id, r]));

  async function submitReview(formData: FormData) {
    "use server";
    const dict = await getDictionary();
    const t = dict.dashboard.truck_review;
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error(t.err_auth);

    const truckId      = String(formData.get("truck_id") ?? "");
    const reliability  = Number(formData.get("rating_reliability")   ?? 0);
    const communication= Number(formData.get("rating_communication") ?? 0);
    const payment      = Number(formData.get("rating_payment")       ?? 0);
    const body         = String(formData.get("body") ?? "").trim();

    if (!truckId) throw new Error(t.err_invalid_truck);
    if (![reliability, communication, payment].every((n) => n >= 1 && n <= 5)) {
      throw new Error(t.err_invalid_ratings);
    }
    if (body.length < 20) throw new Error(t.err_comment_too_short);

    // Re-check truck ownership, participation and booking status server-side.
    const { data: contextRows } = await (supa as any)
      .rpc("airfnb_booking_service_context", { p_booking: bookingId });
    const own = ((contextRows as any[]) ?? []).find(
      (row) => row.truck_id === truckId && row.is_owned,
    );
    if (!own) {
      throw new Error(t.err_no_truck_perm);
    }
    if (own.booking_status !== "confirmed" && own.booking_status !== "completed") {
      throw new Error(t.err_booking_not_confirmed);
    }

    const { error } = await (supa as any).from("airfnb_organizer_reviews").insert({
      booking_id:           bookingId,
      truck_id:             truckId,
      rating_reliability:   reliability,
      rating_communication: communication,
      rating_payment:       payment,
      body,
    });
    if (error) {
      if (error.code === "23505") throw new Error(t.err_duplicate);
      throw new Error(error.message);
    }
    revalidatePath(`/dashboard/truck/avaliar/${bookingId}`);
  }

  return (
    <div className="dash" style={{ maxWidth: 820 }}>
      <nav className="breadcrumb">
        <Link href="/dashboard/truck">{t.breadcrumb_dashboard}</Link> &nbsp;/&nbsp; <span>{t.breadcrumb_current}</span>
      </nav>
      <h1 style={{ margin: 0 }}>{t.title_prefix} {booking.organizer_display_name ?? t.title_fallback}</h1>
      <p style={{ color: "var(--muted)", marginTop: 6 }}>
        {t.event_label} {booking.event_title ?? booking.request_title ?? "—"}
      </p>

      <div style={{ display: "grid", gap: 18, marginTop: 22 }}>
        {myTrucks.map((bt) => {
          const tr = bt.airfnb_trucks;
          const existing = reviewByTruck.get(bt.truck_id);
          return (
            <section key={bt.truck_id} style={{ background: "#fff", border: "1px solid var(--line)", borderRadius: 14, padding: 22 }}>
              <h2 style={{ margin: 0, fontSize: 18 }}>{t.on_behalf_of} {tr?.name ?? "—"}</h2>
              {existing ? (
                <div style={{ marginTop: 14, padding: 14, background: "var(--success-bg)", border: "1px solid var(--success-line)", borderRadius: "var(--radius-sm)" }}>
                  <strong style={{ color: "var(--success-text)" }}>{t.already_reviewed_prefix} {existing.rating_overall} {t.already_reviewed_suffix}</strong>
                  <p style={{ marginTop: 8, whiteSpace: "pre-wrap", color: "var(--ink)" }}>{existing.body}</p>
                </div>
              ) : (
                <form action={submitReview} style={{ marginTop: 14, display: "grid", gap: 14 }}>
                  <input type="hidden" name="truck_id" value={bt.truck_id} />
                  <StarRating name="rating_reliability"   label={t.label_reliability}   required />
                  <StarRating name="rating_communication" label={t.label_communication} required />
                  <StarRating name="rating_payment"       label={t.label_payment}       required />
                  <label style={{ display: "grid", gap: 6 }}>
                    <span style={{ fontSize: 13, fontWeight: 600 }}>{t.label_comment}</span>
                    <textarea name="body" required minLength={20} rows={4}
                      placeholder={t.comment_placeholder} />
                  </label>
                  <div style={{ display: "flex", justifyContent: "flex-end" }}>
                    <button type="submit" className="btn-pill">{t.submit}</button>
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
