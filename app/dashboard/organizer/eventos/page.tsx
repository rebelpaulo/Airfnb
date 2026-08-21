import Link from "next/link";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { getDictionary, getLocale } from "@/lib/i18n";
import { money } from "@/lib/money";

export const dynamic = "force-dynamic";

/**
 * Organizer-side consolidated events view. Pulls confirmed bookings from
 * airfnb_bookings (with their request title via airfnb_event_requests
 * joined through application_id) and groups them into Upcoming / Past /
 * Cancelled stacks with stat counters at the top.
 *
 * Pure list + date grouping — no calendar grid yet. The visual chronology
 * (date headers, status pills, truck name + ICS download per row) is what
 * organizers actually need pre-event; a month-grid is a nice-to-have.
 */
export default async function OrganizerEventsPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/organizer/eventos");

  const dict = await getDictionary();
  const t = (dict.dashboard as any).organizer_events as Record<string, string>;
  const locale = await getLocale();
  const dateLocale = locale === "en" ? "en-US" : "pt-PT";

  // Booking-status labels — distinct enum from application_status (which is
  // for the request/application flow). We only render the user-relevant
  // values; anything else falls through to the raw token via tStatus[...] ?? v.
  const tStatus: Record<string, string> = locale === "en" ? {
    confirmed:        "Confirmed",
    paid:             "Paid",
    in_progress:      "In progress",
    completed:        "Completed",
    cancelled:        "Cancelled",
    pending_lock_fee: "Pending lock-fee",
  } : {
    confirmed:        "Confirmado",
    paid:             "Pago",
    in_progress:      "Em curso",
    completed:        "Concluído",
    cancelled:        "Cancelado",
    pending_lock_fee: "Pendente lock-fee",
  };

  // Bookings + the title of the originating event request + the truck rows.
  // booking.organizer_id is the gate (RLS enforces this too, redundant
  // server-side filter for clarity).
  const { data: bookingRows, error: bookingsError } = await (supa as any)
    .rpc("airfnb_booking_service_context", { p_booking: null });

  // Treat a failed query as a hard error rather than silently rendering
  // the empty state — an RLS regression or DB outage would otherwise look
  // like "no events", which would convince the user nothing is wrong.
  if (bookingsError) {
    console.error("organizer/eventos bookings query failed:", bookingsError.message);
    throw new Error(bookingsError.message);
  }
  const bookingsById = new Map<string, any>();
  for (const row of (bookingRows as any[]) ?? []) {
    if (!row.is_organizer) continue;
    const booking = bookingsById.get(row.booking_id) ?? {
      id: row.booking_id,
      status: row.booking_status,
      starts_at: row.starts_at,
      ends_at: row.ends_at,
      pax_count: row.pax_count,
      total_amount: row.total_amount,
      currency: row.currency,
      ics_token: row.ics_token,
      application_id: row.application_id,
      airfnb_booking_trucks: [],
      airfnb_applications: {
        airfnb_event_requests: {
          id: row.request_id,
          title: row.request_title,
          city: row.request_city,
        },
      },
    };
    booking.airfnb_booking_trucks.push({
      truck_id: row.truck_id,
      airfnb_trucks: {
        id: row.truck_id,
        name: row.truck_name,
        slug: row.truck_slug,
        base_city: row.truck_base_city,
      },
    });
    bookingsById.set(row.booking_id, booking);
  }
  const bookings: any[] = Array.from(bookingsById.values());

  const now = Date.now();
  const upcoming  = bookings.filter((b) => Date.parse(b.starts_at) >= now && b.status !== "cancelled");
  const past      = bookings.filter((b) => Date.parse(b.starts_at) <  now && b.status !== "cancelled");
  const cancelled = bookings.filter((b) => b.status === "cancelled");

  return (
    <div className="dash" style={{ maxWidth: 1100, padding: "32px 28px" }}>
      <h1 style={{ margin: 0 }}>{t.page_title}</h1>
      <p style={{ color: "var(--muted)", marginTop: 6 }}>{t.subtitle}</p>

      <div className="stat-strip" style={{ marginTop: 22 }}>
        <div className="stat"><div className="label">{t.stat_upcoming}</div><div className="value">{upcoming.length}</div></div>
        <div className="stat"><div className="label">{t.stat_past}</div><div className="value">{past.length}</div></div>
        <div className="stat"><div className="label">{t.stat_cancelled}</div><div className="value">{cancelled.length}</div></div>
        <div className="stat"><div className="label">{t.stat_total}</div><div className="value">{bookings.length}</div></div>
      </div>

      {bookings.length === 0 ? (
        <div className="dash empty" style={{ marginTop: 28 }}>
          <p style={{ margin: 0 }}>{t.empty_state}</p>
          <Link href="/publicar" className="btn-pill" style={{ marginTop: 16, display: "inline-block" }}>
            {t.empty_cta}
          </Link>
        </div>
      ) : (
        <div style={{ display: "grid", gap: 28, marginTop: 28 }}>
          {upcoming.length > 0 && (
            <Section title={t.section_upcoming} accent="var(--orange)" rows={upcoming} t={t} tStatus={tStatus} dateLocale={dateLocale} />
          )}
          {past.length > 0 && (
            <Section title={t.section_past} accent="var(--muted)" rows={past} t={t} tStatus={tStatus} dateLocale={dateLocale} />
          )}
          {cancelled.length > 0 && (
            <Section title={t.section_cancelled} accent="#8B1100" rows={cancelled} t={t} tStatus={tStatus} dateLocale={dateLocale} />
          )}
        </div>
      )}
    </div>
  );
}

function Section({ title, accent, rows, t, tStatus, dateLocale }:{
  title: string; accent: string; rows: any[];
  t: Record<string, string>; tStatus: Record<string, string>; dateLocale: string;
}) {
  return (
    <section>
      <h2 style={{ margin: 0, fontSize: 16, color: "var(--muted)", textTransform: "uppercase", letterSpacing: 0.4, fontWeight: 700 }}>
        {title}
      </h2>
      <div style={{ display: "grid", gap: 10, marginTop: 12 }}>
        {rows.map((b) => {
          const req = b.airfnb_applications?.airfnb_event_requests;
          const bts: any[] = b.airfnb_booking_trucks ?? [];
          const trucks = bts.map((bt) => bt.airfnb_trucks?.name).filter(Boolean).join(", ");
          const date = new Date(b.starts_at).toLocaleString(dateLocale, { dateStyle: "long", timeStyle: "short" });
          return (
            <article key={b.id} style={{
              padding: 16, background: "#fff", border: "1px solid var(--line)",
              borderLeft: `4px solid ${accent}`, borderRadius: 10,
              display: "grid", gridTemplateColumns: "1fr auto", gap: 12, alignItems: "center",
            }}>
              <div>
                <div style={{ fontWeight: 700, fontSize: 16 }}>{req?.title ?? "—"}</div>
                <div style={{ color: "var(--muted)", fontSize: 13, marginTop: 4 }}>
                  {date} · {req?.city ?? "—"} · {b.pax_count} pax
                </div>
                {trucks && (
                  <div style={{ color: "var(--ink)", fontSize: 13, marginTop: 4 }}>
                    <strong>{t.label_trucks}</strong> {trucks}
                  </div>
                )}
                <div style={{ fontSize: 12, color: "var(--muted)", marginTop: 6 }}>
                  <span style={{ display: "inline-block", padding: "2px 8px", borderRadius: 999, background: "#F5F5F5", marginRight: 6 }}>
                    {tStatus[b.status] ?? b.status}
                  </span>
                  {b.total_amount != null && (
                    <span>{t.label_total} {money(b.total_amount)}</span>
                  )}
                </div>
              </div>
              <div style={{ display: "flex", flexDirection: "column", gap: 6, fontSize: 13 }}>
                {req?.id && (
                  <Link href={`/dashboard/organizer/pedidos/${req.id}`} style={{ color: "var(--teal)", fontWeight: 600 }}>
                    {t.link_request} →
                  </Link>
                )}
                {b.ics_token && (
                  <a href={`/api/calendar/${b.ics_token}.ics`} style={{ color: "var(--teal)" }}>
                    📅 {t.link_calendar}
                  </a>
                )}
              </div>
            </article>
          );
        })}
      </div>
    </section>
  );
}
