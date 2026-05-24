import Link from "next/link";
import { supabaseServer } from "@/lib/supabase/server";
import { truckCover } from "@/lib/img";

export const revalidate = 60;

type SearchParams = Promise<{
  city?: string;
  cat?: string;       // category slug
  pax?: string;       // minimum capacity
  from?: string;      // YYYY-MM-DD (not yet wired to availability filter)
  to?: string;        // YYYY-MM-DD (idem)
}>;

export default async function CatalogoPage({ searchParams }: { searchParams: SearchParams }) {
  const sp = await searchParams;
  const supa = await supabaseServer();

  let q = (supa as any)
    .from("airfnb_v_truck_card")
    .select("*")
    .order("rating_avg", { ascending: false })
    .order("id", { ascending: true })
    .limit(60);

  if (sp.city) q = q.ilike("base_city", `%${sp.city.trim()}%`);
  if (sp.cat)  q = q.contains("category_slugs", [sp.cat]);
  const paxNum = sp.pax ? Number(sp.pax) : NaN;
  if (Number.isFinite(paxNum) && paxNum > 0) q = q.gte("capacity", paxNum);

  const { data } = await q;
  const trucks = (data as any[]) ?? [];

  const activeFilters: Array<{ key: string; label: string }> = [];
  if (sp.city) activeFilters.push({ key: "city", label: `Cidade: ${sp.city}` });
  if (sp.cat)  activeFilters.push({ key: "cat",  label: `Categoria: ${sp.cat}` });
  if (Number.isFinite(paxNum) && paxNum > 0) activeFilters.push({ key: "pax", label: `≥ ${paxNum} pax` });

  return (
    <div className="container" style={{ paddingTop: 120, paddingBottom: 80 }}>
      <nav className="breadcrumb">
        <Link href="/">Início</Link> &nbsp;/&nbsp; <span>Catálogo</span>
      </nav>
      <h1 className="section-title">Catálogo de Food Trucks</h1>
      <p style={{ color: "var(--muted)", marginTop: -10 }}>
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
