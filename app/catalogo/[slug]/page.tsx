import Link from "next/link";
import { notFound } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { money } from "@/lib/money";
import { truckCover, TRUCK_PLACEHOLDER } from "@/lib/img";

export default async function TruckDetailPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const supa = await supabaseServer();

  const { data: truck } = await (supa as any)
    .from("airfnb_trucks")
    .select(`
      *,
      airfnb_truck_images ( id, url, alt, is_cover, sort_order ),
      airfnb_menu_items   ( id, name, description, price, category ),
      airfnb_truck_categories ( airfnb_categories ( slug, name_pt, icon ) )
    `)
    .eq("slug", slug)
    .maybeSingle();
  if (!truck) notFound();

  const images = (truck.airfnb_truck_images ?? []).sort((a:any,b:any)=> (b.is_cover?1:0)-(a.is_cover?1:0) || a.sort_order-b.sort_order);
  const menu = (truck.airfnb_menu_items ?? []);
  const cats = (truck.airfnb_truck_categories ?? []).map((tc:any)=> tc.airfnb_categories?.name_pt).filter(Boolean);

  const { data: { user } } = await supa.auth.getUser();
  let myOpenRequests: { id: string; title: string }[] = [];
  if (user) {
    const { data: openReqs } = await (supa as any)
      .from("airfnb_event_requests")
      .select("id, title")
      .eq("organizer_id", user.id)
      .in("status", ["open", "reviewing"])
      .order("start_at", { ascending: true });
    myOpenRequests = openReqs ?? [];
  }

  async function invite(formData: FormData) {
    "use server";
    const reqId = String(formData.get("request_id"));
    const supa = await supabaseServer();
    await (supa as any).from("airfnb_request_invitations").insert({
      request_id: reqId,
      truck_id: truck!.id,
      invited_by: (await supa.auth.getUser()).data.user!.id,
    });
  }

  return (
    <div className="container" style={{ paddingTop: 120, paddingBottom: 80, maxWidth: 1100 }}>
      <nav className="breadcrumb">
        <Link href="/catalogo">Catálogo</Link> &nbsp;/&nbsp; <span>{truck.name}</span>
      </nav>

      <h1 className="section-title" style={{ marginBottom: 8 }}>{truck.name}</h1>
      <p style={{ color: "var(--muted)", margin: 0, fontSize: 18 }}>{truck.tagline}</p>

      <div style={{ display: "grid", gridTemplateColumns: "2fr 1fr", gap: 20, marginTop: 24 }}>
        <div>
          <div className="thumb" style={{ aspectRatio: "16/10" }}>
            <img src={truckCover(images[0]?.url)} alt={truck.name} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
          </div>
          {images.length > 1 && (
            <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 8, marginTop: 8 }}>
              {images.slice(1, 5).map((i: any) => (
                <div key={i.id} className="thumb" style={{ aspectRatio: "1/1" }}>
                  <img src={i.url} alt={i.alt ?? ""} />
                </div>
              ))}
            </div>
          )}

          <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 24 }}>Sobre</h2>
          <p style={{ lineHeight: 1.65 }}>{truck.description ?? "Sem descrição."}</p>

          {menu.length > 0 && (
            <>
              <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 24 }}>Menu</h2>
              <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
                {menu.map((m: any) => (
                  <div key={m.id} style={{ display: "flex", justifyContent: "space-between", borderBottom: "1px solid var(--line)", padding: "10px 0" }}>
                    <div>
                      <div style={{ fontWeight: 600 }}>{m.name}</div>
                      {m.description && <div style={{ fontSize: 13, color: "var(--muted)" }}>{m.description}</div>}
                    </div>
                    <div style={{ color: "var(--orange)", fontWeight: 700 }}>{money(m.price)}</div>
                  </div>
                ))}
              </div>
            </>
          )}
        </div>

        <aside style={{ position: "sticky", top: 100, alignSelf: "flex-start", padding: 22, background: "#fff", borderRadius: 14, boxShadow: "var(--shadow-card)" }}>
          <div style={{ fontFamily: "Bebas Neue, sans-serif", fontSize: 28, color: "var(--orange)" }}>
            ★ {Number(truck.rating_avg).toFixed(1)} <span style={{ fontSize: 14, color: "var(--muted)" }}>({truck.rating_count} reviews)</span>
          </div>
          <div style={{ marginTop: 14, display: "flex", flexDirection: "column", gap: 8, fontSize: 14 }}>
            <div><strong>Cidade base:</strong> {truck.base_city ?? "—"}</div>
            <div><strong>Capacidade:</strong> {truck.capacity} pax</div>
            <div><strong>Raio:</strong> {truck.service_radius_km} km</div>
            <div><strong>Preço base:</strong> {truck.base_price ? money(truck.base_price) : "—"}</div>
            <div><strong>Por pax:</strong> {truck.price_per_pax ? money(truck.price_per_pax) : "—"}</div>
          </div>

          {cats.length > 0 && (
            <div style={{ marginTop: 14 }}>
              {cats.map((c: string) => (
                <span key={c} style={{ display: "inline-block", padding: "4px 10px", borderRadius: 999, background: "#FFF6F2", color: "var(--orange-deep)", fontSize: 12, marginRight: 6, marginBottom: 6 }}>{c}</span>
              ))}
            </div>
          )}

          {!user ? (
            <Link href={`/login?next=/catalogo/${slug}`} className="btn-pill" style={{ marginTop: 18, width: "100%", justifyContent: "center", display: "inline-flex" }}>
              Entrar para convidar
            </Link>
          ) : myOpenRequests.length > 0 ? (
            <form action={invite} style={{ marginTop: 18 }}>
              <label style={{ display: "block", fontSize: 12, fontWeight: 700, textTransform: "uppercase", marginBottom: 6 }}>Convidar para um pedido</label>
              <select name="request_id" className="filters-btn" style={{ width: "100%", padding: "10px 14px" }} required>
                {myOpenRequests.map((r) => (<option key={r.id} value={r.id}>{r.title}</option>))}
              </select>
              <button className="btn-pill" type="submit" style={{ marginTop: 10, width: "100%", justifyContent: "center" }}>Enviar convite</button>
            </form>
          ) : (
            <Link href="/publicar" className="btn-pill outline" style={{ marginTop: 18, width: "100%", justifyContent: "center", display: "inline-flex" }}>
              Publica um pedido para convidar
            </Link>
          )}
        </aside>
      </div>
    </div>
  );
}
