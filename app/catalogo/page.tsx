import Link from "next/link";
import { supabaseServer } from "@/lib/supabase/server";
import { truckCover } from "@/lib/img";

export const revalidate = 60;

export default async function CatalogoPage() {
  const supa = await supabaseServer();
  const { data } = await supa
    .from("airfnb_v_truck_card")
    .select("*")
    .order("rating_avg", { ascending: false })
    .limit(60);
  const trucks = data ?? [];

  return (
    <div className="container" style={{ paddingTop: 120, paddingBottom: 80 }}>
      <nav className="breadcrumb">
        <Link href="/">Início</Link> &nbsp;/&nbsp; <span>Catálogo</span>
      </nav>
      <h1 className="section-title">Catálogo de Food Trucks</h1>
      <p style={{ color: "var(--muted)", marginTop: -10 }}>
        Inspira-te ou convida directamente para o teu evento.
      </p>

      {trucks.length === 0 ? (
        <div className="dash empty" style={{ marginTop: 30 }}>
          Sem trucks activos para mostrar.
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
                  <span className="cap">★ {Number(t.rating_avg).toFixed(1)} ({t.rating_count})</span>
                </div>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
