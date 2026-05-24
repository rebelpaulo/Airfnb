import Link from "next/link";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { truckCover } from "@/lib/img";

export default async function TruckDashboard() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/truck");

  // List ALL trucks owned by the current user (a company can run several).
  const { data: trucksData } = await (supa as any)
    .from("airfnb_trucks")
    .select("id, name, slug, rating_avg, rating_count, base_city, status, featured")
    .eq("owner_id", user.id)
    .order("created_at", { ascending: false });
  const trucks: any[] = trucksData ?? [];

  // Cover image per truck (single round-trip)
  const coverByTruck: Record<string, string | null> = {};
  if (trucks.length > 0) {
    const { data: imgs } = await (supa as any)
      .from("airfnb_truck_images")
      .select("truck_id, url, is_cover, sort_order")
      .in("truck_id", trucks.map((t) => t.id));
    for (const t of trucks) {
      const matches = (imgs as any[] ?? []).filter((i) => i.truck_id === t.id);
      matches.sort((a, b) => (b.is_cover ? 1 : 0) - (a.is_cover ? 1 : 0) || (a.sort_order ?? 0) - (b.sort_order ?? 0));
      coverByTruck[t.id] = matches[0]?.url ?? null;
    }
  }

  if (trucks.length === 0) {
    return (
      <div className="dash">
        <h1>Os meus food trucks</h1>
        <div className="empty">
          Ainda não tens nenhum truck. Começa por adicionar o primeiro — leva 2 minutos.
          <br /><br />
          <Link className="btn-pill" href="/dashboard/truck/novo">Adicionar primeiro truck</Link>
        </div>
      </div>
    );
  }

  // Aggregate stats for the company
  const active = trucks.filter((t) => t.status === "active").length;
  const drafts = trucks.filter((t) => t.status === "draft").length;
  const pending = trucks.filter((t) => t.status === "pending_review").length;

  // Combined matching feed across all active trucks. When the same request
  // matches several of the owner's trucks, keep the BEST match (highest score)
  // and label it with the winning truck — otherwise the first truck we
  // iterated would steal the badge even if a sibling matched better.
  type Feed = { request_id: string; title: string; start_at: string; city: string | null; expected_pax: number; match_score: number; via_truck: string };
  const byReq = new Map<string, Feed>();
  for (const t of trucks.filter((x) => x.status === "active")) {
    const { data } = await (supa as any).rpc("airfnb_find_matching_requests", { p_truck: t.id, p_limit: 6 });
    for (const r of (data as any[] ?? [])) {
      const candidate: Feed = { ...r, via_truck: t.name };
      const existing = byReq.get(r.request_id);
      if (!existing || Number(candidate.match_score) > Number(existing.match_score)) {
        byReq.set(r.request_id, candidate);
      }
    }
  }
  const feed: Feed[] = Array.from(byReq.values())
    .sort((a, b) => Number(b.match_score) - Number(a.match_score))
    .slice(0, 12);

  return (
    <div className="dash">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end", flexWrap: "wrap", gap: 14 }}>
        <h1 style={{ margin: 0 }}>Os meus food trucks</h1>
        <Link className="btn-pill" href="/dashboard/truck/novo">+ Adicionar truck</Link>
      </div>

      <div className="stat-strip" style={{ marginTop: 20 }}>
        <div className="stat"><div className="label">Total</div><div className="value">{trucks.length}</div></div>
        <div className="stat"><div className="label">Activos</div><div className="value">{active}</div></div>
        <div className="stat"><div className="label">Em revisão</div><div className="value">{pending}</div></div>
        <div className="stat"><div className="label">Rascunho</div><div className="value">{drafts}</div></div>
      </div>

      <div className="truck-grid cols-4" style={{ marginTop: 18 }}>
        {trucks.map((t) => (
          <Link key={t.id} href={`/dashboard/truck/${t.id}`} className="truck-card">
            <div className="thumb" style={{ position: "relative" }}>
              <img src={truckCover(coverByTruck[t.id])} alt={t.name}
                   style={{ width: "100%", height: "100%", objectFit: "cover" }} />
              <span style={{
                position: "absolute", top: 10, left: 10,
                background: t.status === "active" ? "#10A37F"
                         : t.status === "pending_review" ? "var(--teal)"
                         : t.status === "draft" ? "#888" : "#444",
                color: "#fff", padding: "4px 10px", borderRadius: 999,
                fontSize: 11, fontWeight: 700, textTransform: "uppercase", letterSpacing: 0.5,
              }}>
                {t.status === "active" ? "Activo"
                  : t.status === "pending_review" ? "Em revisão"
                  : t.status === "draft" ? "Rascunho"
                  : t.status}
              </span>
            </div>
            <div className="info">
              <h3>{t.name}</h3>
              <div className="meta">
                <span className="loc">
                  <span className="material-symbols-outlined" style={{ fontSize: 18, color: "#FF4919" }}>location_on</span>
                  {t.base_city ?? "—"}
                </span>
                <span className="cap">★ {Number(t.rating_avg).toFixed(1)} ({t.rating_count})</span>
              </div>
            </div>
          </Link>
        ))}
      </div>

      {active > 0 && (
        <>
          <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 40 }}>
            Pedidos que dão match contigo
          </h2>
          {feed.length === 0 ? (
            <div className="empty">Nenhum pedido relevante aberto neste momento — avisamos-te quando aparecer.</div>
          ) : (
            <div className="request-grid">
              {feed.map((r) => (
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
                    <span className="match-badge">Match {Math.round(Number(r.match_score))}/100 · {r.via_truck}</span>
                    <span style={{ color: "var(--orange)", fontWeight: 600 }}>Aplicar →</span>
                  </div>
                </Link>
              ))}
            </div>
          )}
        </>
      )}
    </div>
  );
}
