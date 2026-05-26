import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { money } from "@/lib/money";
import { getDictionary, getLocale } from "@/lib/i18n";

export default async function ManageRequestPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect(`/login?next=/dashboard/organizer/pedidos/${id}`);

  const { data: req } = await (supa as any)
    .from("airfnb_event_requests")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (!req) notFound();
  if (req.organizer_id !== user.id) redirect("/dashboard/organizer");

  const { data: applicationsData } = await (supa as any)
    .from("airfnb_applications")
    .select(`
      id, status, proposed_price, cover_message, deal_type,
      proposed_fixed_to_organizer, proposed_revenue_share_pct, created_at,
      airfnb_trucks ( id, name, slug, base_city, rating_avg, rating_count )
    `)
    .eq("request_id", id)
    .order("created_at", { ascending: false });
  const applications = applicationsData ?? [];

  // Map applications → conversations + bookings so accepted apps deep-link
  // straight into chat or the review form once the booking is confirmed.
  const appIds = applications.map((a: any) => a.id);
  // Invitations are queried unconditionally — curated requests start
  // life with zero applications, and we still need the invite count
  // to render the funnel stat + private-mode banner. Conversations /
  // bookings ride on application ids, so they're only worth a round-
  // trip when there's at least one application to join against.
  const invitesPromise = (supa as any)
    .from("airfnb_request_invitations")
    .select("truck_id, responded")
    .eq("request_id", id);
  const [convsRes, bookingsRes, invitesRes] = appIds.length
    ? await Promise.all([
        (supa as any).from("airfnb_conversations").select("id, application_id").in("application_id", appIds),
        (supa as any).from("airfnb_bookings").select("id, application_id, status, ics_token").in("application_id", appIds),
        invitesPromise,
      ])
    : await Promise.all([
        Promise.resolve({ data: [] } as any),
        Promise.resolve({ data: [] } as any),
        invitesPromise,
      ]);
  const invitations: any[] = (invitesRes as any).data ?? [];
  const convByApp    = new Map<string, string>(((convsRes.data as any[]) ?? []).map((c) => [c.application_id, c.id]));
  const bookingByApp = new Map<string, { id: string; status: string; ics_token: string | null }>(
    ((bookingsRes.data as any[]) ?? []).map((b) => [b.application_id, { id: b.id, status: b.status, ics_token: b.ics_token }]),
  );

  async function shortlist(formData: FormData) {
    "use server";
    const aid = String(formData.get("application_id"));
    const supa = await supabaseServer();
    await (supa as any).rpc("airfnb_shortlist_application" as any, { p_application: aid });
    revalidatePath(`/dashboard/organizer/pedidos/${id}`);
  }
  async function accept(formData: FormData) {
    "use server";
    const aid = String(formData.get("application_id"));
    const supa = await supabaseServer();
    const { error } = await (supa as any).rpc("airfnb_accept_application" as any, { p_application: aid });
    if (error) throw new Error(error.message);
    revalidatePath(`/dashboard/organizer/pedidos/${id}`);
  }
  async function reject(formData: FormData) {
    "use server";
    const aid = String(formData.get("application_id"));
    const reason = String(formData.get("reason") ?? "");
    const supa = await supabaseServer();
    await (supa as any).rpc("airfnb_reject_application" as any, { p_application: aid, p_reason: reason });
    revalidatePath(`/dashboard/organizer/pedidos/${id}`);
  }

  const dict = await getDictionary();
  const locale = await getLocale();
  const t = dict.dashboard.organizer_request_detail;
  const requestStatusMap = dict.vocab.request_status as Record<string, string>;
  const applicationStatusMap = dict.vocab.application_status as Record<string, string>;
  const dateLocale = locale === "pt" ? "pt-PT" : "en-GB";

  return (
    <div className="dash">
      <nav className="breadcrumb">
        <Link href="/dashboard/organizer">{t.breadcrumb_dashboard}</Link> &nbsp;/&nbsp; <span>{req.title}</span>
      </nav>
      <h1>{req.title}</h1>
      <div className="stat-strip">
        <div className="stat"><div className="label">{t.stat_status}</div><div className="value" style={{ fontSize: 22 }}>{requestStatusMap[req.status] ?? req.status}</div></div>
        <div className="stat"><div className="label">{t.stat_when}</div><div className="value" style={{ fontSize: 18 }}>
          {new Date(req.start_at).toLocaleString(dateLocale, { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" })}
        </div></div>
        <div className="stat"><div className="label">{t.stat_slots}</div><div className="value">{req.slots_needed}</div></div>
        <div className="stat"><div className="label">{t.stat_applications}</div><div className="value">{applications.length}</div></div>
        {req.discovery_mode === "curated" && (
          <div className="stat">
            <div className="label">{t.stat_invited ?? "Convidados"}</div>
            <div className="value">{invitations.length}</div>
          </div>
        )}
      </div>

      {req.discovery_mode === "curated" && (
        <div style={{
          marginTop: 14, padding: 12,
          background: "var(--soft-bg, #F6F7F9)",
          border: "1px solid var(--line)", borderRadius: 8,
          display: "flex", justifyContent: "space-between", alignItems: "center",
          gap: 12, flexWrap: "wrap", fontSize: 14,
        }}>
          <span>{t.curated_hint ?? "Este pedido é privado — só trucks convidados podem candidatar-se."}</span>
          <Link href={`/dashboard/organizer/pedidos/${id}/convidar`} className="btn-pill"
                style={{ background: "var(--orange)", color: "#fff", fontSize: 13, padding: "8px 16px" }}>
            {t.curated_invite_cta ?? "Convidar trucks →"}
          </Link>
        </div>
      )}

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)" }}>{t.section_proposals}</h2>

      {applications.length === 0 ? (
        <div className="empty">{t.empty_applications}</div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
          {applications.map((a: any) => (
            <div key={a.id} className="request-card" style={{ borderLeftColor:
              a.status === "accepted" ? "#10A37F" : a.status === "rejected" ? "#888" : a.status === "shortlisted" ? "#1F5B65" : "var(--orange)" }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
                <div>
                  <h3>{a.airfnb_trucks?.name ?? t.truck_dash}</h3>
                  <div className="row">
                    <span><span className="material-symbols-outlined">location_on</span>{a.airfnb_trucks?.base_city}</span>
                    <span>★ {Number(a.airfnb_trucks?.rating_avg ?? 0).toFixed(1)} ({a.airfnb_trucks?.rating_count ?? 0})</span>
                  </div>
                </div>
                <span className="match-badge">{applicationStatusMap[a.status] ?? a.status}</span>
              </div>

              <p style={{ marginTop: 8, fontSize: 14, lineHeight: 1.55 }}>{a.cover_message}</p>

              <div className="row" style={{ gap: 14, fontSize: 13 }}>
                <span><strong>{t.label_total_expected}</strong> {money(a.proposed_price)}</span>
                <span><strong>{t.label_deal}</strong> {a.deal_type}</span>
                {a.proposed_fixed_to_organizer > 0 && <span><strong>{t.label_fixed}</strong> {money(a.proposed_fixed_to_organizer)}</span>}
                {a.proposed_revenue_share_pct > 0 && <span><strong>{t.label_percent}</strong> {a.proposed_revenue_share_pct}%</span>}
              </div>

              {a.status === "accepted" && (
                <div style={{ marginTop: 10, display: "flex", gap: 8, flexWrap: "wrap" }}>
                  {convByApp.has(a.id) && (
                    <Link href={`/dashboard/conversa/${convByApp.get(a.id)}`} className="btn-pill outline"
                          style={{ padding: "8px 18px", borderColor: "var(--teal)", color: "var(--teal)", display: "inline-flex", alignItems: "center", gap: 6 }}>
                      <span className="material-symbols-outlined" style={{ fontSize: 16 }}>chat_bubble</span>
                      {t.open_conversation}
                    </Link>
                  )}
                  {(() => {
                    const b = bookingByApp.get(a.id);
                    if (!b || (b.status !== "confirmed" && b.status !== "completed")) return null;
                    return (
                      <>
                        {b.ics_token && (
                          <a
                            href={`/api/calendar/${b.ics_token}.ics`}
                            className="btn-pill outline"
                            style={{ padding: "8px 18px", borderColor: "var(--line)", color: "var(--ink)", display: "inline-flex", alignItems: "center", gap: 6 }}
                            target="_blank"
                            rel="noopener noreferrer"
                          >
                            <span className="material-symbols-outlined" style={{ fontSize: 16 }}>event</span>
                            {t.add_to_calendar}
                          </a>
                        )}
                        <Link href={`/dashboard/organizer/avaliar/${b.id}`} className="btn-pill"
                              style={{ padding: "8px 18px", display: "inline-flex", alignItems: "center", gap: 6 }}>
                          <span className="material-symbols-outlined" style={{ fontSize: 16 }}>star</span>
                          {t.rate_truck}
                        </Link>
                      </>
                    );
                  })()}
                </div>
              )}

              {(a.status === "submitted" || a.status === "shortlisted") && (
                <div style={{ display: "flex", gap: 8, marginTop: 8 }}>
                  {a.status === "submitted" && (
                    <form action={shortlist}>
                      <input type="hidden" name="application_id" value={a.id} />
                      <button className="btn-pill outline" type="submit" style={{ padding: "8px 18px" }}>{t.action_shortlist}</button>
                    </form>
                  )}
                  <form action={accept}>
                    <input type="hidden" name="application_id" value={a.id} />
                    <button className="btn-pill" type="submit" style={{ padding: "8px 18px" }}>{t.action_accept}</button>
                  </form>
                  <form action={reject}>
                    <input type="hidden" name="application_id" value={a.id} />
                    <input type="hidden" name="reason" value="rejected_by_organizer" />
                    <button className="btn-pill" type="submit" style={{ padding: "8px 18px", background: "#888" }}>{t.action_reject}</button>
                  </form>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
