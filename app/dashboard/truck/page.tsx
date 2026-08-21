import Link from "next/link";
import Image from "next/image";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { truckCover } from "@/lib/img";
import { getDictionary, getLocale } from "@/lib/i18n";

export default async function TruckDashboard() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/truck");

  const dict = await getDictionary();
  const t = dict.dashboard.truck;
  const locale = await getLocale();
  const dateLocale = locale === "en" ? "en-US" : "pt-PT";

  // List ALL trucks owned by the current user (a company can run several).
  const { data: trucksData } = await (supa as any)
    .rpc("airfnb_supplier_services", { p_truck: null })
    .order("created_at", { ascending: false });
  const trucks: any[] = trucksData ?? [];

  // Cover image per truck (single round-trip)
  const coverByTruck: Record<string, string | null> = {};
  if (trucks.length > 0) {
    const { data: imgs } = await (supa as any)
      .from("airfnb_truck_images")
      .select("truck_id, url, is_cover, sort_order")
      .in("truck_id", trucks.map((t) => t.id));
    for (const tr of trucks) {
      const matches = (imgs as any[] ?? []).filter((i) => i.truck_id === tr.id);
      matches.sort((a, b) => (b.is_cover ? 1 : 0) - (a.is_cover ? 1 : 0) || (a.sort_order ?? 0) - (b.sort_order ?? 0));
      coverByTruck[tr.id] = matches[0]?.url ?? null;
    }
  }

  if (trucks.length === 0) {
    return (
      <div className="dash">
        <h1>{t.title}</h1>
        <div className="empty">
          {t.empty_no_trucks}
          <br /><br />
          <Link className="btn-pill" href="/dashboard/truck/novo">{t.add_first_truck}</Link>
        </div>
      </div>
    );
  }

  // Aggregate stats for the company
  const active = trucks.filter((tr) => tr.status === "active").length;
  const drafts = trucks.filter((tr) => tr.status === "draft").length;
  const pending = trucks.filter((tr) => tr.status === "pending_review").length;

  // Combined matching feed across all active trucks. When the same request
  // matches several of the owner's trucks, keep the BEST match (highest score)
  // and label it with the winning truck — otherwise the first truck we
  // iterated would steal the badge even if a sibling matched better.
  type Feed = { request_id: string; title: string; start_at: string; city: string | null; expected_pax: number; match_score: number; via_truck: string };
  // Ask each truck for enough candidates that, after de-duping and ordering,
  // the merged top-12 isn't artificially capped. With p_limit=6 a single
  // active truck would only ever yield 6 rows — bump to 12 per truck.
  const byReq = new Map<string, Feed>();
  for (const tr of trucks.filter((x) => x.status === "active")) {
    const { data } = await (supa as any).rpc("airfnb_find_matching_requests", { p_truck: tr.id, p_limit: 12 });
    for (const r of (data as any[] ?? [])) {
      const candidate: Feed = { ...r, via_truck: tr.name };
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
        <h1 style={{ margin: 0 }}>{t.title}</h1>
        <Link className="btn-pill" href="/dashboard/truck/novo">{t.add_truck}</Link>
      </div>

      <div className="stat-strip" style={{ marginTop: 20 }}>
        <div className="stat"><div className="label">{t.stat_total}</div><div className="value">{trucks.length}</div></div>
        <div className="stat"><div className="label">{t.stat_active}</div><div className="value">{active}</div></div>
        <div className="stat"><div className="label">{t.stat_pending}</div><div className="value">{pending}</div></div>
        <div className="stat"><div className="label">{t.stat_drafts}</div><div className="value">{drafts}</div></div>
      </div>

      <div className="truck-grid cols-4" style={{ marginTop: 18 }}>
        {trucks.map((tr) => (
          <Link key={tr.id} href={`/dashboard/truck/${tr.id}`} className="truck-card">
            <div className="thumb" style={{ position: "relative" }}>
              <Image
                src={truckCover(coverByTruck[tr.id])}
                alt={tr.name}
                fill
                sizes="(max-width: 600px) 100vw, (max-width: 1024px) 50vw, 25vw"
                style={{ objectFit: "cover" }}
              />
              <span style={{
                position: "absolute", top: 10, left: 10,
                background: tr.status === "active" ? "#10A37F"
                         : tr.status === "pending_review" ? "var(--teal)"
                         : tr.status === "draft" ? "#888" : "#444",
                color: "#fff", padding: "4px 10px", borderRadius: 999,
                fontSize: 11, fontWeight: 700, textTransform: "uppercase", letterSpacing: 0.5,
              }}>
                {tr.status === "active" ? t.status_active
                  : tr.status === "pending_review" ? t.status_pending_review
                  : tr.status === "draft" ? t.status_draft
                  : tr.status}
              </span>
            </div>
            <div className="info">
              <h3>{tr.name}</h3>
              <div className="meta">
                <span className="loc">
                  <span className="material-symbols-outlined" style={{ fontSize: 18, color: "#FF4919" }}>location_on</span>
                  {tr.base_city ?? "—"}
                </span>
                <span className="cap">★ {Number(tr.rating_avg).toFixed(1)} ({tr.rating_count})</span>
              </div>
            </div>
          </Link>
        ))}
      </div>

      {active > 0 && (
        <>
          <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 40 }}>
            {t.matches_title}
          </h2>
          {feed.length === 0 ? (
            <div className="empty">{t.matches_empty}</div>
          ) : (
            <div className="request-grid">
              {feed.map((r) => (
                <Link key={r.request_id} href={`/pedidos/${r.request_id}`} className="request-card">
                  <h3>{r.title}</h3>
                  <div className="row">
                    <span><span className="material-symbols-outlined">event</span>
                      {new Date(r.start_at).toLocaleDateString(dateLocale, { day: "2-digit", month: "short" })}
                    </span>
                    <span><span className="material-symbols-outlined">location_on</span>{r.city ?? "—"}</span>
                    <span><span className="material-symbols-outlined">group</span>{r.expected_pax}</span>
                  </div>
                  <div className="row" style={{ justifyContent: "space-between" }}>
                    <span className="match-badge">{t.match_badge} {Math.round(Number(r.match_score))}/100 · {r.via_truck}</span>
                    <span style={{ color: "var(--orange)", fontWeight: 600 }}>{t.apply_arrow}</span>
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
