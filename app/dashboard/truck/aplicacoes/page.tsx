import Link from "next/link";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { money } from "@/lib/money";
import { getDictionary, getLocale } from "@/lib/i18n";

export default async function MinhasCandidaturasPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/truck/aplicacoes");

  const dict = await getDictionary();
  const t = dict.dashboard.truck_applications;
  const locale = await getLocale();
  const dateLocale = locale === "en" ? "en-US" : "pt-PT";

  // Multi-truck companies have more than one truck under the same owner —
  // surface candidaturas for ALL of them in one feed, not just the first.
  const { data: myTrucks } = await (supa as any)
    .from("airfnb_trucks")
    .select("id, name")
    .eq("owner_id", user.id);
  if (!myTrucks?.length) redirect("/dashboard/truck/novo");

  const truckIds = myTrucks.map((t: any) => t.id);
  const truckNameById = new Map<string, string>(myTrucks.map((t: any) => [t.id, t.name]));

  const { data: appsData } = await (supa as any)
    .from("airfnb_applications")
    .select(`id, status, proposed_price, truck_id, created_at,
             airfnb_event_requests ( id, title, start_at, city, status )`)
    .in("truck_id", truckIds)
    .order("created_at", { ascending: false });
  const apps = appsData ?? [];

  // Map applications → conversations + bookings so we can deep-link directly
  // to the chat or surface a review CTA once the booking is confirmed/completed.
  const appIds = apps.map((a: any) => a.id);
  const [convsRes, bookingsRes] = appIds.length
    ? await Promise.all([
        (supa as any).from("airfnb_conversations").select("id, application_id").in("application_id", appIds),
        (supa as any).from("airfnb_bookings").select("id, application_id, status, ics_token").in("application_id", appIds),
      ])
    : [{ data: [] }, { data: [] }];
  const convByApp    = new Map<string, string>(((convsRes.data as any[]) ?? []).map((c) => [c.application_id, c.id]));
  const bookingByApp = new Map<string, { id: string; status: string; ics_token: string | null }>(
    ((bookingsRes.data as any[]) ?? []).map((b) => [b.application_id, { id: b.id, status: b.status, ics_token: b.ics_token }]),
  );

  return (
    <div className="dash">
      <nav className="breadcrumb">
        <Link href="/dashboard/truck">{t.breadcrumb_dashboard}</Link> &nbsp;/&nbsp; <span>{t.breadcrumb_current}</span>
      </nav>
      <h1>{t.title}</h1>

      {apps.length === 0 ? (
        <div className="empty">{t.empty_prefix}<Link href="/dashboard/truck/oportunidades" style={{ color: "var(--orange)" }}>{t.empty_link}</Link>{t.empty_suffix}</div>
      ) : (
        <div className="request-grid">
          {apps.map((a: any) => (
            <div key={a.id} className="request-card">
              <h3>{a.airfnb_event_requests?.title ?? "—"}</h3>
              <div className="row">
                <span><span className="material-symbols-outlined">event</span>
                  {a.airfnb_event_requests?.start_at && new Date(a.airfnb_event_requests.start_at).toLocaleDateString(dateLocale, { day: "2-digit", month: "short" })}
                </span>
                <span><span className="material-symbols-outlined">location_on</span>{a.airfnb_event_requests?.city ?? "—"}</span>
                <span>{t.proposal_prefix} {money(a.proposed_price)}</span>
                <span style={{ color: "var(--muted)", fontSize: 12 }}>{t.via_prefix} {truckNameById.get(a.truck_id) ?? "—"}</span>
              </div>
              <div className="row" style={{ justifyContent: "space-between" }}>
                <span className="match-badge">{a.status}</span>
                {a.status === "accepted" ? (
                  <div style={{ display: "flex", gap: 14, alignItems: "center", flexWrap: "wrap" }}>
                    {convByApp.has(a.id) && (
                      <Link href={`/dashboard/conversa/${convByApp.get(a.id)}`} style={{ color: "var(--teal)", fontWeight: 600 }}>
                        {t.conversation_link}
                      </Link>
                    )}
                    {(() => {
                      const b = bookingByApp.get(a.id);
                      if (b && (b.status === "confirmed" || b.status === "completed")) {
                        return (
                          <>
                            {b.ics_token && (
                              <a href={`/api/calendar/${b.ics_token}.ics`}
                                 target="_blank" rel="noopener noreferrer"
                                 style={{ color: "var(--teal)", fontWeight: 600 }}>
                                {t.calendar_link}
                              </a>
                            )}
                            <Link href={`/dashboard/truck/avaliar/${b.id}`} style={{ color: "var(--orange-deep)", fontWeight: 600 }}>
                              {t.review_link}
                            </Link>
                          </>
                        );
                      }
                      // Lock fee still pending — show the pay link instead of the review one.
                      return (
                        <Link href={`/dashboard/truck/lock/${a.id}`} style={{ color: "var(--orange)", fontWeight: 600 }}>
                          {t.pay_lock_link}
                        </Link>
                      );
                    })()}
                  </div>
                ) : a.airfnb_event_requests?.status === "open" ? (
                  // Only link out when the brief still accepts traffic — the
                  // oportunidades route redirects closed requests to /aplicacoes,
                  // so the link would just bounce back for non-open briefs.
                  <Link href={`/dashboard/truck/oportunidades/${a.airfnb_event_requests?.id}`} style={{ color: "var(--teal)", fontWeight: 600 }}>
                    {t.view_request_link}
                  </Link>
                ) : (
                  <span style={{ color: "var(--muted)", fontSize: 13 }}>
                    {t.request_closed_prefix} {a.airfnb_event_requests?.status ?? t.request_closed_fallback}
                  </span>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
