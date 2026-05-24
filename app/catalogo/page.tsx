import Link from "next/link";
import { supabaseServer } from "@/lib/supabase/server";
import { truckCover } from "@/lib/img";
import { FilterModal } from "./FilterModal";

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
}>;

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
  if (priceMin)         q = q.gte("base_price", priceMin);
  if (priceMax)         q = q.lte("base_price", priceMax);
  if (cuisines?.length) q = q.overlaps("cuisine_types", cuisines);
  if (dietary?.length)  q = q.overlaps("dietary_options", dietary);
  if (setupMax)         q = q.lte("setup_minutes", setupMax);
  if (power && POWER_MAX_KW[power] != null) q = q.lte("power_required_kw", POWER_MAX_KW[power]);
  if (serves && ["food","drinks","food_and_drinks"].includes(serves)) {
    // 'food_and_drinks' trucks satisfy any of the three picks; otherwise an
    // exact match on the simpler picks.
    if (serves === "food_and_drinks") q = q.eq("serves", "food_and_drinks");
    else                              q = q.in("serves", [serves, "food_and_drinks"]);
  }
  if (sanitation) {
    // A truck that needs more amenities than the event provides shouldn't show.
    // Wizard semantics: organizer says what they offer; truck must require ≤ that.
    const allowed = sanitation === "wc_dedicado" ? ["none","wc_proximo","wc_dedicado"]
                  : sanitation === "wc_proximo"  ? ["none","wc_proximo"]
                  : ["none"];
    q = q.in("sanitation_required", allowed);
  }

  const { data: trucks = [], error } = await q;
  if (error) console.error("catalogo query failed", error.message);

  const { data: categoriesData } = await (supa as any)
    .from("airfnb_categories")
    .select("id, slug, name_pt, icon")
    .order("name_pt");
  const categories = categoriesData ?? [];

  const activeFilters: Array<{ key: string; label: string }> = [];
  if (city)             activeFilters.push({ key: "city",      label: `Cidade: ${city}` });
  if (cats?.length)     activeFilters.push({ key: "cats",      label: `Especialidades: ${cats.join(", ")}` });
  if (pax)              activeFilters.push({ key: "pax",       label: `≥ ${pax} pax` });
  if (priceMin)         activeFilters.push({ key: "price_min", label: `Min € ${priceMin}` });
  if (priceMax)         activeFilters.push({ key: "price_max", label: `Max € ${priceMax}` });
  if (cuisines?.length) activeFilters.push({ key: "cuisines",  label: `Cozinhas: ${cuisines.join(", ")}` });
  if (dietary?.length)  activeFilters.push({ key: "dietary",   label: `Dietas: ${dietary.join(", ")}` });
  if (setupMax)         activeFilters.push({ key: "setup_max", label: `Montagem ≤ ${setupMax}min` });
  if (power)            activeFilters.push({ key: "power",     label: `Energia: ${power}` });
  if (sanitation)       activeFilters.push({ key: "sanitation",label: `WC: ${sanitation}` });
  if (serves)           activeFilters.push({ key: "catering",  label: `Catering: ${serves.replace("_and_", " & ")}` });

  return (
    <div className="container" style={{ paddingTop: 120, paddingBottom: 80 }}>
      <nav className="breadcrumb">
        <Link href="/">Página Inicial</Link> &nbsp;/&nbsp; <span>Catálogo</span>
      </nav>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 16, flexWrap: "wrap", marginTop: 6 }}>
        <h1 className="section-title" style={{ margin: 0 }}>Catálogo de Food Trucks</h1>
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
        Inspira-te ou convida directamente para o teu evento.
      </p>

      {activeFilters.length > 0 && (
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", margin: "16px 0 8px" }}>
          {activeFilters.map((f) => (
            <span key={f.key} style={{
              display: "inline-flex", alignItems: "center", gap: 6,
              padding: "6px 12px", borderRadius: 999,
              background: "#FFF6F2", color: "var(--orange-deep)",
              fontSize: 13, fontWeight: 600,
            }}>{f.label}</span>
          ))}
          <Link href="/catalogo" style={{ color: "var(--muted)", fontSize: 13, alignSelf: "center" }}>
            limpar filtros
          </Link>
        </div>
      )}

      {trucks.length === 0 ? (
        <div className="dash empty" style={{ marginTop: 30 }}>
          {activeFilters.length > 0
            ? "Nenhum truck activo encontrado para estes filtros."
            : "Sem trucks activos para mostrar."}
        </div>
      ) : (
        <div className="truck-grid cols-4" style={{ marginTop: 26 }}>
          {trucks.map((t: any) => (
            <Link key={t.id} href={`/catalogo/${t.slug}`} className="truck-card">
              <div className="thumb">
                <img src={truckCover(t.cover_url)} alt={t.name} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
              </div>
              <div className="info">
                <h3>{t.name}</h3>
                <div className="subtitle">{(t.category_slugs ?? []).slice(0, 3).join(" · ")}</div>
                <div className="meta">
                  <span className="loc">
                    <span className="material-symbols-outlined" style={{ fontSize: 18, color: "#FF4919" }}>location_on</span>
                    {t.base_city ?? "—"}
                  </span>
                  <span className="cap">
                    {Number(t.rating_count) > 0
                      ? `★ ${Number(t.rating_avg).toFixed(1)} (${t.rating_count})`
                      : "Novo"}
                  </span>
                </div>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
