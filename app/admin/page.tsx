import Link from "next/link";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { money } from "@/lib/money";

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

  return (
    <div className="dash" style={{ maxWidth: 1100 }}>
      <h1 style={{ margin: 0 }}>Admin</h1>
      <p style={{ color: "var(--muted)", marginTop: 6 }}>Visão rápida do estado da plataforma.</p>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: 12, marginTop: 22 }}>
        <Stat label="Trucks ativos"        value={m.trucks_active} sub={`${m.trucks_total} no total`} />
        <Stat label="Trucks pending"       value={m.trucks_pending} accent={m.trucks_pending > 0 ? "var(--orange)" : undefined} />
        <Stat label="Pedidos abertos"      value={m.requests_open} />
        <Stat label="Bookings confirmadas" value={m.bookings_confirmed} />
        <Stat label="Lock-fees pagas"      value={m.lockfees_paid_count} sub={money(m.lockfees_paid_total ?? 0)} />
        <Stat label="Receita plataforma"   value={money(m.revenue_platform ?? 0)} accent="#10A37F" />
        <Stat label="Users na plataforma"  value={m.organizers_total} />
      </div>

      <section style={{ marginTop: 32 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <h2 style={{ margin: 0 }}>Trucks à espera de revisão</h2>
          <Link href="/admin/trucks" style={{ color: "var(--teal)", fontWeight: 600 }}>Ver todos →</Link>
        </div>
        {pending.length === 0 ? (
          <div className="empty" style={{ marginTop: 12 }}>Sem trucks pendentes.</div>
        ) : (
          <ul style={{ listStyle: "none", padding: 0, marginTop: 14, display: "grid", gap: 10 }}>
            {pending.map((t) => (
              <li key={t.id} style={{ border: "1px solid var(--line)", borderRadius: 12, padding: 14, background: "#fff", display: "grid", gridTemplateColumns: "1fr auto", gap: 12, alignItems: "center" }}>
                <div>
                  <strong>{t.name}</strong>
                  <div style={{ color: "var(--muted)", fontSize: 13 }}>
                    {t.base_city ?? "—"} · submetido por {t.owner_name ?? "—"} · {new Date(t.created_at).toLocaleDateString("pt-PT")}
                  </div>
                </div>
                <Link href={`/admin/trucks#${t.id}`} className="btn-pill outline" style={{ padding: "8px 16px", borderColor: "var(--teal)", color: "var(--teal)" }}>
                  Rever
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
