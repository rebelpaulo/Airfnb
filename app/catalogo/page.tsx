import Link from "next/link";
import type { Metadata } from "next";
import { supabaseServer } from "@/lib/supabase/server";
import { FilterModal } from "./FilterModal";
import { getDictionary } from "@/lib/i18n";
import { getFavoritedTruckIds } from "@/lib/favorites";
import { TruckCard } from "@/components/TruckCard";

// TODO: i18n metadata via generateMetadata
export const metadata: Metadata = {
  title: "Catálogo de Food Trucks",
  description: "Explora food trucks certificados em Portugal. Filtra por localização, capacidade, cozinha e dietas.",
  alternates: { canonical: "/catalogo" },
};

export const revalidate = 60;

// Next 15 hands the same key as string | string[] when the URL repeats it.
// Normalize defensively so .trim()/.toLowerCase() don't crash at runtime.
type Raw = string | string[] | undefined;
type SearchParams = Promise<{
  city?: Raw; cat?: Raw; cats?: Raw; pax?: Raw;
  price_min?: Raw; price_max?: Raw; catering?: Raw;
  cuisines?: Raw; dietary?: Raw;
  setup_max?: Raw; power?: Raw; sanitation?: Raw;
  from?: Raw; to?: Raw;
  event_kind?: Raw;
}>;

const EVENT_KINDS = ["wedding","birthday","corporate","festival","conference","private","other"] as const;

function first(v: Raw): string | undefined {
  if (v == null) return undefined;
  const s = Array.isArray(v) ? v[0] : v;
  return typeof s === "string" ? s.trim() || undefined : undefined;
}
function csv(v: Raw): string[] | undefined {
  const s = first(v);
  if (!s) return undefined;
  const parts = s.split(",").map((x) => x.trim()).filter(Boolean);
  return parts.length ? parts : undefined;
}
function num(v: Raw): number | undefined {
  const s = first(v);
  if (!s) return undefined;
  const n = Number(s);
  return Number.isFinite(n) && n > 0 ? n : undefined;
}

const POWER_MAX_KW: Record<string, number> = {
  nao_preciso: 0,
  ate_3kw:     3,
  "3_a_10kw":  10,
  mais_10kw:   100,
};

export default async function CatalogoPage({ searchParams }: { searchParams: SearchParams }) {
  const dict = await getDictionary();
  const t = dict.catalog;
  const sp = await searchParams;
  const city       = first(sp.city);
  // `cat` (legacy single) and `cats` (modal multi) both supported; merged
  const catSingle  = first(sp.cat);
  const cats       = csv(sp.cats) ?? (catSingle ? [catSingle] : undefined);
  const pax        = num(sp.pax);
  const priceMin   = num(sp.price_min);
  const priceMax   = num(sp.price_max);
  const cuisines   = csv(sp.cuisines);
  const dietary    = csv(sp.dietary);
  const setupMax   = num(sp.setup_max);
  const power      = first(sp.power);
  const sanitation = first(sp.sanitation);
  // FilterModal persists this as `catering` (food/drinks/food_and_drinks);
  // backed by airfnb_trucks.serves.
  const serves     = first(sp.catering);
  // Deep-linked from the themed cards on the landing
  // (/catalogo?event_kind=wedding). Validate against the airfnb_event_kind enum.
  const eventKindRaw = first(sp.event_kind);
  const validEventKind = eventKindRaw && (EVENT_KINDS as readonly string[]).includes(eventKindRaw)
    ? eventKindRaw : undefined;

  // Validate enum-style params once so chip rendering below can use the same
  // accept/reject decision as the query — avoids showing chips for malformed
  // URLs (e.g. ?power=foo) that the query silently ignores.
  const validPower      = power && POWER_MAX_KW[power] != null ? power : undefined;
  const validSanitation = sanitation && ["none", "wc_proximo", "wc_dedicado"].includes(sanitation)
    ? sanitation : undefined;
  const validServes     = serves && ["food", "drinks", "food_and_drinks"].includes(serves)
    ? serves : undefined;

  const supa = await supabaseServer();

  let q = (supa as any)
    .from("airfnb_v_truck_card")
    .select("*")
    .order("rating_avg", { ascending: false })
    .order("id", { ascending: true })
    .limit(60);

  if (city)             q = q.ilike("base_city", `%${city}%`);
  if (cats?.length)     q = q.overlaps("category_slugs", cats);
  if (pax)              q = q.gte("capacity", pax);
  // Themed landing cards filter on `compatible_event_kinds` (truck owner
  // opted-in via the wizard). `contains` translates to the PG `@>` operator
  // which the GIN index on this column makes cheap.
  if (validEventKind)   q = q.contains("compatible_event_kinds", [validEventKind]);
  if (priceMin)         q = q.gte("base_price", priceMin);
  if (priceMax)         q = q.lte("base_price", priceMax);
  if (cuisines?.length) q = q.overlaps("cuisine_types", cuisines);
  if (dietary?.length)  q = q.overlaps("dietary_options", dietary);
  if (setupMax)         q = q.lte("setup_minutes", setupMax);
  if (validPower) q = q.lte("power_required_kw", POWER_MAX_KW[validPower]);
  if (validServes) {
    // 'food_and_drinks' trucks satisfy any of the three picks; otherwise an
    // exact match on the simpler picks.
    if (validServes === "food_and_drinks") q = q.eq("serves", "food_and_drinks");
    else                                   q = q.in("serves", [validServes, "food_and_drinks"]);
  }
  if (validSanitation) {
    // A truck that needs more amenities than the event provides shouldn't show.
    // Wizard semantics: organizer says what they offer; truck must require ≤ that.
    const allowed = validSanitation === "wc_dedicado" ? ["none","wc_proximo","wc_dedicado"]
                  : validSanitation === "wc_proximo"  ? ["none","wc_proximo"]
                  : ["none"];
    q = q.in("sanitation_required", allowed);
  }

  const { data: trucks = [], error } = await q;
  if (error) console.error("catalogo query failed", error.message);

  // One read for which trucks the current user has hearted; HeartButton
  // gets the initial state per-card. Unauth visitors return empty Set.
  const favoritedIds = await getFavoritedTruckIds();
  const { data: { user } } = await supa.auth.getUser();
  const authed = !!user;

  const { data: categoriesData } = await (supa as any)
    .from("airfnb_categories")
    .select("id, slug, name_pt, icon")
    .order("name_pt");
  const categories = categoriesData ?? [];

  // Value → dictionary-key lookups so active-filter chips show translated
  // labels instead of raw URL slugs (e.g. "italiana", "vegan", "nao_preciso").
  // Mirrors the same maps used by FilterModal.
  const tFilter = dict.catalog.filter_modal as Record<string, string>;
  const CUISINE_KEY: Record<string, string> = {
    portuguesa: "cuisine_pt", italiana: "cuisine_it", japonesa: "cuisine_jp",
    turca: "cuisine_tr", espanhola: "cuisine_es", chinesa: "cuisine_cn",
    mexicana: "cuisine_mx", tailandesa: "cuisine_th", marroquina: "cuisine_ma",
    americana: "cuisine_us",
  };
  const DIETARY_KEY: Record<string, string> = {
    vegetarian: "dietary_vegetarian", vegan: "dietary_vegan", gluten_free: "dietary_gluten_free",
  };
  const POWER_KEY: Record<string, string> = {
    nao_preciso: "power_none", ate_3kw: "power_3", "3_a_10kw": "power_3_10", mais_10kw: "power_10_plus",
  };
  const SANI_KEY: Record<string, string> = {
    none: "sani_none", wc_proximo: "sani_close", wc_dedicado: "sani_dedicated",
  };
  const CATERING_KEY: Record<string, string> = {
    food: "catering_food", drinks: "catering_drinks", food_and_drinks: "catering_both",
  };
  // Event kind labels live in vocab.event_kinds (added by PR #33 wizards
  // so both wizards share the same chip vocab). Reuse here.
  const tEventKinds = (dict as any).vocab?.event_kinds ?? {};
  const lookup = (map: Record<string, string>, v: string) => tFilter[map[v] ?? ""] ?? v;

  const activeFilters: Array<{ key: string; label: string }> = [];
  if (city)             activeFilters.push({ key: "city",      label: `${t.filter_city}: ${city}` });
  if (cats?.length)     activeFilters.push({ key: "cats",      label: `${t.filter_specialties}: ${cats.join(", ")}` });
  if (pax)              activeFilters.push({ key: "pax",       label: `≥ ${pax} ${t.filter_pax}` });
  if (priceMin)         activeFilters.push({ key: "price_min", label: `${t.filter_min} ${priceMin}` });
  if (priceMax)         activeFilters.push({ key: "price_max", label: `${t.filter_max} ${priceMax}` });
  if (cuisines?.length) activeFilters.push({ key: "cuisines",  label: `${t.filter_cuisines}: ${cuisines.map((c) => lookup(CUISINE_KEY, c)).join(", ")}` });
  if (dietary?.length)  activeFilters.push({ key: "dietary",   label: `${t.filter_dietary}: ${dietary.map((d) => lookup(DIETARY_KEY, d)).join(", ")}` });
  if (setupMax)         activeFilters.push({ key: "setup_max", label: `${t.filter_setup} ≤ ${setupMax}${t.filter_setup_unit}` });
  if (validPower)       activeFilters.push({ key: "power",     label: `${t.filter_power}: ${lookup(POWER_KEY, validPower)}` });
  if (validSanitation)  activeFilters.push({ key: "sanitation",label: `${t.filter_wc}: ${lookup(SANI_KEY, validSanitation)}` });
  if (validServes)      activeFilters.push({ key: "catering",  label: `${t.filter_catering}: ${lookup(CATERING_KEY, validServes)}` });
  if (validEventKind)   activeFilters.push({ key: "event_kind",label: `${t.filter_event_kind ?? "Evento"}: ${tEventKinds[validEventKind] ?? validEventKind}` });

  return (
    <div className="container" style={{ paddingTop: 120, paddingBottom: 80 }}>
      <nav className="breadcrumb">
        <Link href="/">{t.breadcrumb_home}</Link> &nbsp;/&nbsp; <span>{t.breadcrumb_self}</span>
      </nav>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 16, flexWrap: "wrap", marginTop: 6 }}>
        <h1 className="section-title" style={{ margin: 0 }}>{t.page_title}</h1>
        <FilterModal
          initial={{
            city, pax,
            priceMin, priceMax,
            cateringType: first(sp.catering),
            cuisines, specialties: cats, dietary,
            setupMax, power, sanitation,
          }}
          categories={categories}
        />
      </div>
      <p style={{ color: "var(--muted)", marginTop: 6 }}>
        {t.subtitle}
      </p>

      {activeFilters.length > 0 && (
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", margin: "16px 0 8px" }}>
          {activeFilters.map((f) => (
            <span key={f.key} className="active-filter-chip">{f.label}</span>
          ))}
          <Link href="/catalogo" style={{ color: "var(--muted)", fontSize: 13, alignSelf: "center" }}>
            {dict.common.clear_filters}
          </Link>
        </div>
      )}

      {trucks.length === 0 ? (
        <div className="dash empty" style={{ marginTop: 30 }}>
          {activeFilters.length > 0
            ? t.empty_filtered
            : t.empty_no_trucks}
        </div>
      ) : (
        <div className="truck-grid cols-4" style={{ marginTop: 26 }}>
          {trucks.map((tr: any) => (
            <TruckCard
              key={tr.id}
              truck={tr}
              initialFavorited={favoritedIds.has(tr.id)}
              authed={authed}
              newLabel={t.truck_new}
            />
          ))}
        </div>
      )}
    </div>
  );
}
