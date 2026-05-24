import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { StarRating } from "@/components/StarRating";

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

  const { data: booking } = await (supa as any)
    .from("airfnb_bookings")
    .select(`
      id, status, organizer_id, starts_at,
      airfnb_events ( title ),
      airfnb_profiles!airfnb_bookings_organizer_id_fkey ( id, display_name ),
      airfnb_booking_trucks ( truck_id, agreed_price,
        airfnb_trucks ( id, name, slug, owner_id ) )
    `)
    .eq("id", bookingId)
    .maybeSingle();
  if (!booking) notFound();
  if (booking.status !== "confirmed" && booking.status !== "completed") {
    redirect("/dashboard/truck");
  }

  // Only show the trucks belonging to the current user
  const myTrucks = ((booking.airfnb_booking_trucks as any[]) ?? [])
    .filter((bt) => bt.airfnb_trucks?.owner_id === user.id);
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
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error("auth required");

    const truckId      = String(formData.get("truck_id") ?? "");
    const reliability  = Number(formData.get("rating_reliability")   ?? 0);
    const communication= Number(formData.get("rating_communication") ?? 0);
    const payment      = Number(formData.get("rating_payment")       ?? 0);
    const body         = String(formData.get("body") ?? "").trim();

    if (!truckId) throw new Error("Truck inválido.");
    if (![reliability, communication, payment].every((n) => n >= 1 && n <= 5)) {
      throw new Error("Indica 1–5 estrelas em cada categoria.");
    }
    if (body.length < 20) throw new Error("Comentário deve ter pelo menos 20 caracteres.");

    // Re-check truck ownership + booking participation server-side.
    const { data: own } = await (supa as any)
      .from("airfnb_booking_trucks")
      .select("truck_id, airfnb_trucks ( owner_id )")
      .eq("booking_id", bookingId)
      .eq("truck_id", truckId)
      .maybeSingle();
    if (!own || (own as any).airfnb_trucks?.owner_id !== user.id) {
      throw new Error("Sem permissão para avaliar em nome deste truck.");
    }
    const { data: b } = await (supa as any)
      .from("airfnb_bookings")
      .select("status, organizer_id")
      .eq("id", bookingId)
      .maybeSingle();
    if (!b || (b.status !== "confirmed" && b.status !== "completed")) {
      throw new Error("Só podes avaliar bookings confirmados.");
    }

    // organizer_id comes from the booking, not the form — never trust the client
    const { error } = await (supa as any).from("airfnb_organizer_reviews").insert({
      booking_id:           bookingId,
      truck_id:             truckId,
      organizer_id:         b.organizer_id,
      rating_reliability:   reliability,
      rating_communication: communication,
      rating_payment:       payment,
      body,
      is_verified:          true,
    });
    if (error) {
      if (error.code === "23505") throw new Error("Já avaliaste este organizador para este evento.");
      throw new Error(error.message);
    }
    revalidatePath(`/dashboard/truck/avaliar/${bookingId}`);
  }

  const orgProfile = (booking as any).airfnb_profiles;

  return (
    <div className="dash" style={{ maxWidth: 820 }}>
      <nav className="breadcrumb">
        <Link href="/dashboard/truck">Dashboard</Link> &nbsp;/&nbsp; <span>Avaliar organizador</span>
      </nav>
      <h1 style={{ margin: 0 }}>Avaliar {orgProfile?.display_name ?? "organizador"}</h1>
      <p style={{ color: "var(--muted)", marginTop: 6 }}>
        Evento: {(booking.airfnb_events as any)?.title ?? "—"}
      </p>

      <div style={{ display: "grid", gap: 18, marginTop: 22 }}>
        {myTrucks.map((bt) => {
          const t = bt.airfnb_trucks;
          const existing = reviewByTruck.get(bt.truck_id);
          return (
            <section key={bt.truck_id} style={{ background: "#fff", border: "1px solid var(--line)", borderRadius: 14, padding: 22 }}>
              <h2 style={{ margin: 0, fontSize: 18 }}>Em nome de: {t?.name ?? "—"}</h2>
              {existing ? (
                <div style={{ marginTop: 14, padding: 14, background: "#F1FBF5", border: "1px solid #C5EBD3", borderRadius: 10 }}>
                  <strong style={{ color: "#0F7B4F" }}>★ {existing.rating_overall} — já avaliaste</strong>
                  <p style={{ marginTop: 8, whiteSpace: "pre-wrap", color: "var(--ink)" }}>{existing.body}</p>
                </div>
              ) : (
                <form action={submitReview} style={{ marginTop: 14, display: "grid", gap: 14 }}>
                  <input type="hidden" name="truck_id" value={bt.truck_id} />
                  <StarRating name="rating_reliability"   label="Fiabilidade (cumpriu o combinado?)" required />
                  <StarRating name="rating_communication" label="Comunicação"                         required />
                  <StarRating name="rating_payment"       label="Pagamento (atempado e correto?)"    required />
                  <label style={{ display: "grid", gap: 6 }}>
                    <span style={{ fontSize: 13, fontWeight: 600 }}>Comentário</span>
                    <textarea name="body" required minLength={20} rows={4}
                      placeholder="Trabalharias outra vez com este organizador?" />
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
