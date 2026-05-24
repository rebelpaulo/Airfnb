import Link from "next/link";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { money } from "@/lib/money";

export default async function TruckDashboard() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/truck");

  const { data: myTruck } = await (supa as any)
    .from("airfnb_trucks")
    .select("id, name, rating_avg, rating_count, base_city")
    .eq("owner_id", user.id)
    .maybeSingle();

  if (!myTruck) {
    return (
      <div className="dash">
        <h1>Dashboard do truck</h1>
        <div className="empty">
          Ainda não adicionaste o teu food truck.
          <br /><br />
          <Link className="btn-pill" href="/dashboard/truck/novo">Adicionar truck</Link>
        </div>
      </div>
    );
  }

  // matching open requests via RPC
  const { data: feedData } = await (supa as any).rpc("airfnb_find_matching_requests" as any, {
    p_truck: myTruck.id,
    p_limit: 12,
  });
  const feed = feedData ?? [];

  // my applications
  const { data: appsData } = await (supa as any)
    .from("airfnb_applications")
    .select(`
      id, status, proposed_price, created_at,
      airfnb_event_requests ( id, title, start_at, city, status )
    `)
    .eq("truck_id", myTruck.id)
    .order("created_at", { ascending: false })
    .limit(10);
  const apps = appsData ?? [];

  return (
    <div className="dash">
      <h1>{myTruck.name}</h1>
      <div className="stat-strip">
        <div className="stat"><div className="label">Rating</div><div className="value">★ {Number(myTruck.rating_avg).toFixed(1)}</div></div>
        <div className="stat"><div className="label">Reviews</div><div className="value">{myTruck.rating_count}</div></div>
        <div className="stat"><div className="label">Cidade base</div><div className="value" style={{ fontSize: 22 }}>{myTruck.base_city ?? "—"}</div></div>
        <div className="stat"><div className="label">Candidaturas activas</div><div className="value">
          {apps.filter((a: any) => a.status === "submitted" || a.status === "shortlisted").length}
        </div></div>
      </div>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 20 }}>
        Pedidos que dão match contigo
      </h2>
      {feed.length === 0 ? (
        <div className="empty">Nenhum pedido relevante aberto neste momento — vamos avisar-te quando aparecer.</div>
      ) : (
        <div className="request-grid">
          {feed.map((r: any) => (
            <Link key={r.request_id} href={`/pedidos/${r.request_id}`} className="request-card">
              <h3>{r.title}</h3>
              <div className="row">
                <span><span className="material-symbols-outlined">event</span>
                  {new Date(r.start_at).toLocaleDateString("pt-PT", { day: "2-digit", month: "short" })}
                </span>
                <span><span className="material-symbols-outlined">location_on</span>{r.city ?? "—"}</span>
                <span><span className="material-symbols-outlined">group</span>{r.expected_pax}</span>
              </div>
              <div className="row" style={{ justifyContent: "space-between" }}>
                <span className="match-badge">Match {Math.round(Number(r.match_score))}/100</span>
                <span style={{ color: "var(--orange)", fontWeight: 600 }}>Aplicar →</span>
              </div>
            </Link>
          ))}
        </div>
      )}

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 40 }}>
        As minhas candidaturas
      </h2>
      {apps.length === 0 ? (
        <div className="empty">Ainda não submeteste nenhuma candidatura.</div>
      ) : (
        <div className="request-grid">
          {apps.map((a: any) => (
            <Link key={a.id}
                  href={a.status === "accepted" ? `/dashboard/truck/lock/${a.id}` : `/pedidos/${a.airfnb_event_requests?.id}`}
                  className="request-card">
              <h3>{a.airfnb_event_requests?.title ?? "—"}</h3>
              <div className="row">
                <span>Proposta: {money(a.proposed_price)}</span>
                <span className="match-badge">{a.status}</span>
              </div>
              {a.status === "accepted" && (
                <div style={{ color: "var(--orange)", fontWeight: 600, marginTop: 6 }}>
                  ⏰ Pagar lock-fee €50 →
                </div>
              )}
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
