import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { StarRating } from "@/components/StarRating";

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

  const { data: booking } = await (supa as any)
    .from("airfnb_bookings")
    .select(`
      id, status, organizer_id, starts_at,
      airfnb_events ( title ),
      airfnb_booking_trucks ( truck_id, agreed_price,
        airfnb_trucks ( id, name, slug, base_city ) )
    `)
    .eq("id", bookingId)
    .maybeSingle();
  if (!booking) notFound();
  if (booking.organizer_id !== user.id) redirect("/dashboard/organizer");
  if (booking.status !== "confirmed" && booking.status !== "completed") {
    // Reviews only make sense after the event happened — fail loud rather
    // than letting the organizer post on a pending booking.
    redirect("/dashboard/organizer");
  }

  const truckRows = (booking.airfnb_booking_trucks as any[]) ?? [];
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
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error("auth required");

    const truckId = String(formData.get("truck_id") ?? "");
    const food    = Number(formData.get("rating_food") ?? 0);
    const service = Number(formData.get("rating_service") ?? 0);
    const valueR  = Number(formData.get("rating_value") ?? 0);
    const body    = String(formData.get("body") ?? "").trim();

    if (!truckId)                                                throw new Error("Truck inválido.");
    if (![food, service, valueR].every((n) => n >= 1 && n <= 5)) throw new Error("Indica 1–5 estrelas em cada categoria.");
    if (body.length < 20)                                        throw new Error("Comentário deve ter pelo menos 20 caracteres.");

    // Re-check booking ownership + status server-side (form fields are user-controlled)
    const { data: b } = await (supa as any)
      .from("airfnb_bookings")
      .select("id, organizer_id, status")
      .eq("id", bookingId)
      .maybeSingle();
    if (!b || b.organizer_id !== user.id) throw new Error("Sem permissão.");
    if (b.status !== "confirmed" && b.status !== "completed") {
      throw new Error("Só podes avaliar bookings confirmados.");
    }

    const rating_overall = Math.round(((food + service + valueR) / 3) * 10) / 10;

    const { error } = await (supa as any).from("airfnb_reviews").insert({
      booking_id:     bookingId,
      truck_id:       truckId,
      organizer_id:   user.id,
      rating_food:    food,
      rating_service: service,
      rating_value:   valueR,
      rating_overall,
      body,
      is_verified:    true,
    });
    if (error) {
      if (error.code === "23505") throw new Error("Já avaliaste este truck para este evento.");
      throw new Error(error.message);
    }
    revalidatePath(`/dashboard/organizer/avaliar/${bookingId}`);
  }

  return (
    <div className="dash" style={{ maxWidth: 820 }}>
      <nav className="breadcrumb">
        <Link href="/dashboard/organizer">Dashboard</Link> &nbsp;/&nbsp; <span>Avaliar trucks</span>
      </nav>
      <h1 style={{ margin: 0 }}>Avaliar {(booking.airfnb_events as any)?.title ?? "evento"}</h1>
      <p style={{ color: "var(--muted)", marginTop: 6 }}>
        A tua opinião ajuda outros organizadores a escolher. Avalia cada truck que participou.
      </p>

      <div style={{ display: "grid", gap: 18, marginTop: 22 }}>
        {truckRows.map((bt) => {
          const t = bt.airfnb_trucks;
          const existing = reviewByTruck.get(bt.truck_id);
          return (
            <section key={bt.truck_id} style={{ background: "#fff", border: "1px solid var(--line)", borderRadius: 14, padding: 22 }}>
              <h2 style={{ margin: 0, fontSize: 20 }}>{t?.name ?? "—"}</h2>
              <div style={{ color: "var(--muted)", fontSize: 13, marginTop: 2 }}>
                {t?.base_city ?? "—"}
              </div>

              {existing ? (
                <div style={{ marginTop: 14, padding: 14, background: "#F1FBF5", border: "1px solid #C5EBD3", borderRadius: 10 }}>
                  <strong style={{ color: "#0F7B4F" }}>★ {existing.rating_overall} — já avaliaste</strong>
                  <p style={{ marginTop: 8, whiteSpace: "pre-wrap", color: "var(--ink)" }}>{existing.body}</p>
                </div>
              ) : (
                <form action={submitReview} style={{ marginTop: 14, display: "grid", gap: 14 }}>
                  <input type="hidden" name="truck_id" value={bt.truck_id} />
                  <StarRating name="rating_food"    label="Comida"     required />
                  <StarRating name="rating_service" label="Serviço"    required />
                  <StarRating name="rating_value"   label="Relação preço/qualidade" required />
                  <label style={{ display: "grid", gap: 6 }}>
                    <span style={{ fontSize: 13, fontWeight: 600 }}>Comentário</span>
                    <textarea name="body" required minLength={20} rows={4}
                      placeholder="O que correu bem? Recomendarias?" />
                  </label>
                  <div style={{ display: "flex", justifyContent: "flex-end" }}>
                    <button type="submit" className="btn-pill">Publicar avaliação</button>
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
