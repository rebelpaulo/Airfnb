import Link from "next/link";
import Image from "next/image";
import type { Metadata } from "next";
import { supabaseServer } from "@/lib/supabase/server";
import { truckCover } from "@/lib/img";
import { getDictionary, getLocale } from "@/lib/i18n";
import { getFavoritedTruckIds } from "@/lib/favorites";
import { HeartButton } from "@/components/HeartButton";
import { recommendForEvent } from "@/lib/event-planning";

// Discovery-style results page that sits between the hero form on `/` and
// the publish wizard at `/publicar`. Three zones:
//
//   1. Plan card — static heuristic from lib/event-planning.ts (PR 1 keeps
//      it dumb; PR 2 will make it reactive to truck selection).
//   2. Cuisine chips — server-rendered <Link>s that toggle a value in the
//      `cuisines` URL param. No client JS needed.
//   3. Truck grid — same airfnb_v_truck_card query the /catalogo page uses,
//      narrowed to `city` and `cuisines`.
//
// The CTA at the bottom forwards every URL param into /publicar so the
// wizard can prefill its step-1 fields without losing context.

export const metadata: Metadata = {
  title: "Plano e food trucks para o teu evento",
  description: "Recomendações operacionais (eletricidade, água, espaço) e food trucks compatíveis para o teu evento.",
  alternates: { canonical: "/procurar" },
};

export const revalidate = 60;

type Raw = string | string[] | undefined;
type SearchParams = Promise<{
  city?: Raw;
  start_at?: Raw;
  end_at?: Raw;
  expected_pax?: Raw;
  cuisines?: Raw;
}>;

function first(v: Raw): string | undefined {
  if (v == null) return undefined;
  const s = Array.isArray(v) ? v[0] : v;
  return typeof s === "string" ? s.trim() || undefined : undefined;
}
function csv(v: Raw): string[] {
  const s = first(v);
  if (!s) return [];
  return s.split(",").map((x) => x.trim()).filter(Boolean);
}
function num(v: Raw): number | undefined {
  const s = first(v);
  if (!s) return undefined;
  const n = Number(s);
  return Number.isFinite(n) && n > 0 ? n : undefined;
}

/** Replace placeholders like {pax}/{min} in i18n strings. */
function fmt(template: string, vars: Record<string, string | number>): string {
  return template.replace(/\{(\w+)\}/g, (_, k) => String(vars[k] ?? ""));
}

/** Build a query string preserving every param except `cuisines`, then add
 *  the given cuisine list. Used by both the chips and the bottom CTA. */
function buildHref(
  base: string,
  baseParams: Record<string, string | undefined>,
  cuisines: string[],
): string {
  const qs = new URLSearchParams();
  for (const [k, v] of Object.entries(baseParams)) {
    if (v) qs.set(k, v);
  }
  if (cuisines.length) qs.set("cuisines", cuisines.join(","));
  const s = qs.toString();
  return s ? `${base}?${s}` : base;
}

export default async function ProcurarPage({ searchParams }: { searchParams: SearchParams }) {
  const dict = await getDictionary();
  const t = (dict as any).procurar as Record<string, string>;
  const sp = await searchParams;

  const city     = first(sp.city);
  const startAt  = first(sp.start_at);
  const endAt    = first(sp.end_at);
  const pax      = num(sp.expected_pax) ?? 100;
  const cuisines = csv(sp.cuisines);

  const plan = recommendForEvent(pax);

  const supa = await supabaseServer();

  // Truck query — same view as /catalogo, scoped to city + cuisines.
  let q = (supa as any)
    .from("airfnb_v_truck_card")
    .select("*")
    .order("rating_avg", { ascending: false })
    .order("id", { ascending: true })
    .limit(60);
  if (city)            q = q.ilike("base_city", `%${city}%`);
  if (cuisines.length) q = q.overlaps("cuisine_types", cuisines);

  const { data: trucks = [], error } = await q;
  if (error) console.error("procurar query failed", error.message);

  // For the cuisine chips: count occurrences of each cuisine across the
  // FULL city set (so chips don't disappear when a filter is applied).
  // Run a second query without the cuisine filter — cheap, capped at 200.
  let qAll = (supa as any)
    .from("airfnb_v_truck_card")
    .select("cuisine_types")
    .limit(200);
  if (city) qAll = qAll.ilike("base_city", `%${city}%`);
  const { data: allTrucks = [] } = await qAll;

  const cuisineCounts = new Map<string, number>();
  for (const tr of (allTrucks as any[])) {
    for (const c of (tr?.cuisine_types ?? []) as string[]) {
      cuisineCounts.set(c, (cuisineCounts.get(c) ?? 0) + 1);
    }
  }
  const allCuisines = Array.from(cuisineCounts.entries()).sort((a, b) => b[1] - a[1]);

  // Heart-button initial state (matches /catalogo behaviour).
  const favoritedIds = await getFavoritedTruckIds();
  const { data: { user } } = await supa.auth.getUser();
  const authed = !!user;

  // Translated cuisine labels (mirror /catalogo's CUISINE_KEY map).
  const tFilter = (dict.catalog?.filter_modal ?? {}) as Record<string, string>;
  const CUISINE_KEY: Record<string, string> = {
    portuguesa: "cuisine_pt", italiana: "cuisine_it", japonesa: "cuisine_jp",
    turca: "cuisine_tr", espanhola: "cuisine_es", chinesa: "cuisine_cn",
    mexicana: "cuisine_mx", tailandesa: "cuisine_th", marroquina: "cuisine_ma",
    americana: "cuisine_us",
  };
  const cuisineLabel = (slug: string) => tFilter[CUISINE_KEY[slug] ?? ""] ?? slug;

  // Base param dict shared by chip links and CTA — preserves everything
  // EXCEPT cuisines (chips compose their own cuisine list).
  const baseParams = {
    city,
    start_at: startAt,
    end_at: endAt,
    expected_pax: pax ? String(pax) : undefined,
  };

  const ctaHref = buildHref("/publicar", baseParams, cuisines);

  // Format header summary in the active locale ("250 convidados em 20 de
  // julho de 2026" vs. "250 guests on July 20, 2026"). Hardcoding pt-PT
  // here was leaking PT month names into EN sessions.
  const locale = await getLocale();
  const dateLocale = locale === "en" ? "en-US" : "pt-PT";
  const formattedDate = startAt
    ? new Date(startAt).toLocaleDateString(dateLocale, { day: "2-digit", month: "long", year: "numeric" })
    : null;
  const summaryParts = [
    fmt(t.summary_pax, { pax }),
    formattedDate ? fmt(t.summary_date, { date: formattedDate }) : "",
  ].filter(Boolean).join(" · ");

  return (
    <div className="container" style={{ paddingTop: 120, paddingBottom: 80, maxWidth: 1100 }}>
      <nav className="breadcrumb">
        <Link href="/">{dict.catalog?.breadcrumb_home ?? "Home"}</Link> &nbsp;/&nbsp; <span>{t.breadcrumb_self}</span>
      </nav>

      <div style={{ marginTop: 8 }}>
        <div style={{ fontSize: 12, color: "var(--muted)", letterSpacing: 0.4, textTransform: "uppercase", fontWeight: 700 }}>
          {t.page_eyebrow}
        </div>
        <h1 className="section-title" style={{ margin: "4px 0 6px" }}>
          {city ? fmt(t.page_title_with_city, { city }) : t.page_title_no_city}
        </h1>
        <p style={{ color: "var(--muted)", margin: 0 }}>{summaryParts}</p>
      </div>

      {/* ============ PLAN CARD ============ */}
      <section
        aria-labelledby="plan-title"
        style={{
          marginTop: 28,
          padding: 24,
          background: "linear-gradient(180deg, #FFF6F2 0%, #FFFFFF 100%)",
          border: "1px solid var(--line)",
          borderRadius: 14,
        }}
      >
        <h2 id="plan-title" style={{ margin: 0, fontSize: 20 }}>{t.plan_title}</h2>
        <p style={{ color: "var(--muted)", marginTop: 6, fontSize: 14 }}>{t.plan_subtitle}</p>

        <div style={{
          display: "grid",
          // Tile min-width must be < smallest mobile viewport content area
          // (320 - 28*2 container - 24*2 card = 212px) to avoid forcing
          // horizontal scroll on small phones. 180px gives breathing room.
          gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))",
          gap: 16,
          marginTop: 18,
        }}>
          <PlanTile
            icon="local_shipping"
            label={t.plan_trucks_label}
            value={fmt(t.plan_trucks_value, { min: plan.trucks.min, max: plan.trucks.max })}
            help={t.plan_trucks_help}
            highlight
          />
          <PlanTile
            icon="bolt"
            label={t.plan_electricity}
            value={fmt(t.plan_electricity_val, { min: plan.kva.min, max: plan.kva.max })}
            help={fmt(t.plan_electricity_help, { genset: plan.gensetKva })}
          />
          <PlanTile
            icon="water_drop"
            label={t.plan_water}
            value={fmt(t.plan_water_val, { min: plan.waterLiters.min, max: plan.waterLiters.max })}
            help={t.plan_water_help}
          />
          <PlanTile
            icon="space_dashboard"
            label={t.plan_area}
            value={fmt(t.plan_area_val, { min: plan.areaM2.min, max: plan.areaM2.max })}
            help={t.plan_area_help}
          />
          <PlanTile
            icon="delete"
            label={t.plan_waste}
            value={fmt(t.plan_waste_val, { bins: plan.waste.bins240l, drums: plan.waste.greaseDrums })}
            help=""
          />
        </div>

        <p style={{ marginTop: 18, fontSize: 12, color: "var(--muted)", fontStyle: "italic" }}>
          {t.plan_disclaimer}
        </p>
      </section>

      {/* ============ CUISINE CHIPS ============ */}
      {allCuisines.length > 0 && (
        <section style={{ marginTop: 36 }}>
          <h2 style={{ fontSize: 16, margin: "0 0 12px" }}>{t.cuisines_title}</h2>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
            {allCuisines.map(([slug, count]) => {
              const active = cuisines.includes(slug);
              const nextCuisines = active
                ? cuisines.filter((c) => c !== slug)
                : [...cuisines, slug];
              return (
                <Link
                  key={slug}
                  href={buildHref("/procurar", baseParams, nextCuisines)}
                  scroll={false}
                  aria-pressed={active}
                  style={{
                    display: "inline-flex", alignItems: "center", gap: 6,
                    padding: "8px 14px",
                    borderRadius: 999,
                    border: "1px solid",
                    borderColor: active ? "var(--orange)" : "var(--line)",
                    background: active ? "var(--orange)" : "#fff",
                    color: active ? "#fff" : "var(--ink)",
                    fontSize: 14,
                    fontWeight: active ? 700 : 500,
                    textDecoration: "none",
                    transition: "background 0.15s, color 0.15s, border-color 0.15s",
                  }}
                >
                  {cuisineLabel(slug)}
                  <span style={{ opacity: 0.7, fontSize: 12 }}>({count})</span>
                </Link>
              );
            })}
            {cuisines.length > 0 && (
              <Link
                href={buildHref("/procurar", baseParams, [])}
                scroll={false}
                style={{
                  display: "inline-flex", alignItems: "center",
                  padding: "8px 14px",
                  borderRadius: 999,
                  border: "1px dashed var(--muted)",
                  background: "transparent",
                  color: "var(--muted)",
                  fontSize: 14,
                  textDecoration: "none",
                }}
              >
                {t.cuisines_clear}
              </Link>
            )}
          </div>
        </section>
      )}

      {/* ============ COUNT + GRID ============ */}
      <section style={{ marginTop: 28 }}>
        <p style={{ color: "var(--muted)", marginTop: 0, fontSize: 14 }}>
          {trucks.length === 1
            ? t.results_count_one
            : fmt(t.results_count, { shown: trucks.length, total: allTrucks.length })}
        </p>

        {trucks.length === 0 ? (
          <div className="dash empty" style={{ marginTop: 16, padding: 32, textAlign: "center" }}>
            {t.results_empty}
          </div>
        ) : (
          <div className="truck-grid cols-4" style={{ marginTop: 16 }}>
            {(trucks as any[]).map((tr: any) => (
              <Link key={tr.id} href={`/catalogo/${tr.slug}`} className="truck-card">
                <div className="thumb" style={{ position: "relative" }}>
                  <Image
                    src={truckCover(tr.cover_url)}
                    alt={tr.name}
                    fill
                    sizes="(max-width: 768px) 100vw, (max-width: 1200px) 33vw, 25vw"
                    style={{ objectFit: "cover" }}
                  />
                  <HeartButton truckId={tr.id} initialFavorited={favoritedIds.has(tr.id)} authed={authed} />
                </div>
                <div className="info">
                  <h3>{tr.name}</h3>
                  <div className="subtitle">{(tr.category_slugs ?? []).slice(0, 3).join(" · ")}</div>
                  <div className="meta">
                    <span className="loc">
                      <span className="material-symbols-outlined" style={{ fontSize: 18, color: "#FF4919" }}>location_on</span>
                      {tr.base_city ?? "—"}
                    </span>
                    <span className="cap">
                      {Number(tr.rating_count) > 0
                        ? `★ ${Number(tr.rating_avg).toFixed(1)} (${tr.rating_count})`
                        : (dict.catalog?.truck_new ?? "New")}
                    </span>
                  </div>
                </div>
              </Link>
            ))}
          </div>
        )}
      </section>

      {/* ============ CTA ============ */}
      <section
        aria-labelledby="cta-title"
        style={{
          marginTop: 48,
          padding: 28,
          background: "var(--orange)",
          color: "#fff",
          borderRadius: 14,
          textAlign: "center",
        }}
      >
        <div style={{ fontSize: 12, letterSpacing: 0.4, textTransform: "uppercase", fontWeight: 700, opacity: 0.85 }}>
          {t.cta_eyebrow}
        </div>
        <h2 id="cta-title" style={{ margin: "6px 0 10px", fontSize: 24 }}>{t.cta_title}</h2>
        <p style={{ margin: "0 auto 18px", maxWidth: 580, opacity: 0.95 }}>{t.cta_body}</p>
        <Link
          href={ctaHref}
          className="btn-pill"
          style={{ background: "#fff", color: "var(--orange)", fontWeight: 700, display: "inline-block" }}
        >
          {t.cta_button}
        </Link>
      </section>
    </div>
  );
}

function PlanTile({ icon, label, value, help, highlight }: {
  icon: string; label: string; value: string; help: string; highlight?: boolean;
}) {
  return (
    <div style={{
      background: "#fff",
      border: "1px solid var(--line)",
      borderLeft: highlight ? "4px solid var(--orange)" : "1px solid var(--line)",
      borderRadius: 10,
      padding: 16,
    }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        <span className="material-symbols-outlined" aria-hidden="true" style={{ fontSize: 22, color: "var(--orange)" }}>{icon}</span>
        <div style={{ fontSize: 12, color: "var(--muted)", textTransform: "uppercase", letterSpacing: 0.3, fontWeight: 700 }}>{label}</div>
      </div>
      <div style={{ fontSize: 22, fontWeight: 800, marginTop: 6 }}>{value}</div>
      {help && (
        <div style={{ fontSize: 12, color: "var(--muted)", marginTop: 6, lineHeight: 1.4 }}>{help}</div>
      )}
    </div>
  );
}
