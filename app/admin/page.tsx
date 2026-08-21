import Link from "next/link";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { money } from "@/lib/money";
import { getDictionary, getLocale } from "@/lib/i18n";

export const dynamic = "force-dynamic";

export default async function AdminDashboardPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/admin");

  // The metrics RPC returns 0 rows for non-admins (the SECURITY DEFINER
  // function gates internally via airfnb_is_admin()) — that's our auth signal.
  const { data: metricsRows } = await (supa as any).rpc("airfnb_admin_metrics");
  const m = ((metricsRows as any[]) ?? [])[0];
  if (!m) redirect("/dashboard/organizer");

  const { data: pendingTrucks } = await (supa as any)
    .rpc("airfnb_admin_pending_trucks", { p_limit: 5 });
  const pending: any[] = (pendingTrucks as any[]) ?? [];

  // Assisted requests are the "Preciso de ajuda especializada" branch:
  // organizer wants the F&B Tailor team to curate the shortlist. Surface
  // them prominently so the team can pick them up alongside trucks
  // pending moderation. We pull live requests only (status open) so
  // historical assisted requests don't clutter the queue.
  const { data: assistedRaw } = await (supa as any)
    .from("airfnb_event_requests")
    .select("id, title, city, locality, expected_pax, start_at, created_at, organizer_id")
    .eq("assistance_requested", true)
    .eq("status", "open")
    .order("created_at", { ascending: false })
    .limit(8);
  const assisted: any[] = (assistedRaw as any[]) ?? [];

  const dict = await getDictionary();
  const t = dict.admin;
  const locale = await getLocale();
  const dateLocale = locale === "en" ? "en-US" : "pt-PT";

  return (
    <div className="dash" style={{ maxWidth: 1100 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 16, flexWrap: "wrap" }}>
        <div>
          <h1 style={{ margin: 0 }}>Admin</h1>
          <p style={{ color: "var(--muted)", marginTop: 6 }}>{t.subtitle}</p>
        </div>
        <Link href="/admin/definicoes" className="btn-pill outline"
              style={{ padding: "8px 18px", borderColor: "var(--teal)", color: "var(--teal)", fontSize: 14 }}>
          {t.settings_link}
        </Link>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: 12, marginTop: 22 }}>
        <Stat label={t.stat_trucks_active}      value={m.trucks_active} sub={`${m.trucks_total} ${t.stat_total_suffix}`} />
        <Stat label={t.stat_trucks_pending}     value={m.trucks_pending} accent={m.trucks_pending > 0 ? "var(--orange)" : undefined} />
        <Stat label={t.stat_open_requests}      value={m.requests_open} />
        <Stat label={t.stat_bookings_confirmed} value={m.bookings_confirmed} />
        <Stat label={t.stat_lockfees_paid}      value={m.lockfees_paid_count} sub={money(m.lockfees_paid_total ?? 0)} />
        <Stat label={t.stat_revenue}            value={money(m.revenue_platform ?? 0)} accent="#10A37F" />
        <Stat label={t.stat_users}              value={m.organizers_total} />
      </div>

      {assisted.length > 0 && (
        <section style={{ marginTop: 32 }}>
          <h2 style={{ margin: 0 }}>{t.assisted_title ?? "Pedidos a aguardar curadoria"}</h2>
          <p style={{ color: "var(--muted)", fontSize: 13, marginTop: 4 }}>
            {t.assisted_subtitle ?? "Organizadores que pediram a ajuda da equipa F&B Tailor para curar a shortlist."}
          </p>
          <ul style={{ listStyle: "none", padding: 0, marginTop: 14, display: "grid", gap: 10 }}>
            {assisted.map((r) => (
              <li key={r.id} style={{ border: "1px solid var(--line)", borderLeft: "4px solid var(--orange)", borderRadius: 12, padding: 14, background: "#fff", display: "grid", gridTemplateColumns: "1fr auto", gap: 12, alignItems: "center" }}>
                <div>
                  <strong>{r.title}</strong>
                  <div style={{ color: "var(--muted)", fontSize: 13 }}>
                    {(r.city ?? r.locality ?? "—")} · {r.expected_pax} pax · {new Date(r.start_at).toLocaleDateString(dateLocale)}
                  </div>
                </div>
                <Link href={`/dashboard/organizer/pedidos/${r.id}`} className="btn-pill outline" style={{ padding: "8px 16px", borderColor: "var(--teal)", color: "var(--teal)" }}>
                  {t.assisted_open ?? "Abrir pedido"}
                </Link>
              </li>
            ))}
          </ul>
        </section>
      )}

      <section style={{ marginTop: 32 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <h2 style={{ margin: 0 }}>{t.pending_title}</h2>
          <Link href="/admin/trucks" style={{ color: "var(--teal)", fontWeight: 600 }}>{t.view_all}</Link>
        </div>
        {pending.length === 0 ? (
          <div className="empty" style={{ marginTop: 12 }}>{t.empty_pending}</div>
        ) : (
          <ul style={{ listStyle: "none", padding: 0, marginTop: 14, display: "grid", gap: 10 }}>
            {pending.map((tr) => (
              <li key={tr.id} style={{ border: "1px solid var(--line)", borderRadius: 12, padding: 14, background: "#fff", display: "grid", gridTemplateColumns: "1fr auto", gap: 12, alignItems: "center" }}>
                <div>
                  <strong>{tr.name}</strong>
                  <div style={{ color: "var(--muted)", fontSize: 13 }}>
                    {tr.base_city ?? "—"} · {t.submitted_by} {tr.owner_name ?? "—"} · {new Date(tr.created_at).toLocaleDateString(dateLocale)}
                  </div>
                </div>
                <Link href={`/admin/trucks#${tr.id}`} className="btn-pill outline" style={{ padding: "8px 16px", borderColor: "var(--teal)", color: "var(--teal)" }}>
                  {t.review}
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}

function Stat({ label, value, sub, accent }: { label: string; value: React.ReactNode; sub?: string; accent?: string }) {
  return (
    <div style={{ border: "1px solid var(--line)", borderRadius: 12, padding: 16, background: "#fff" }}>
      <div style={{ fontSize: 12, color: "var(--muted)", letterSpacing: 0.4, textTransform: "uppercase", fontWeight: 700 }}>{label}</div>
      <div style={{ fontFamily: "Bebas Neue, sans-serif", fontSize: 36, color: accent ?? "var(--ink)", lineHeight: 1, marginTop: 4 }}>{value}</div>
      {sub && <div style={{ color: "var(--muted)", fontSize: 12, marginTop: 4 }}>{sub}</div>}
    </div>
  );
}
