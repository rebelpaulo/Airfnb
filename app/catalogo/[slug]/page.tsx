import Link from "next/link";
import Image from "next/image";
import { notFound } from "next/navigation";
import type { Metadata } from "next";
import { supabaseServer } from "@/lib/supabase/server";
import { money } from "@/lib/money";
import { truckCover, TRUCK_PLACEHOLDER } from "@/lib/img";
import { getDictionary } from "@/lib/i18n";

// TODO: i18n metadata via generateMetadata
export async function generateMetadata(
  { params }: { params: Promise<{ slug: string }> },
): Promise<Metadata> {
  const { slug } = await params;
  const supa = await supabaseServer();
  const { data: t } = await (supa as any)
    .from("airfnb_v_truck_card")
    .select("name, tagline, base_city, cover_url, rating_avg, rating_count")
    .eq("slug", slug)
    .maybeSingle();
  if (!t) return { title: "Truck não encontrado" };

  const title = `${t.name}${t.base_city ? ` · ${t.base_city}` : ""}`;
  const description =
    (t.tagline as string | null) ??
    `${t.name}, food truck${t.base_city ? ` em ${t.base_city}` : ""} disponível para o teu evento.`;
  const cover = truckCover(t.cover_url);

  return {
    title,
    description,
    alternates: { canonical: `/catalogo/${slug}` },
    openGraph: {
      title,
      description,
      url: `/catalogo/${slug}`,
      type: "website",
      images: cover ? [{ url: cover, width: 1200, height: 630, alt: t.name }] : undefined,
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: cover ? [cover] : undefined,
    },
  };
}

export default async function TruckDetailPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const dict = await getDictionary();
  const t = dict.truck_detail;
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

  // Schema.org Restaurant for richer Google SERP cards + aggregateRating
  // when we have ratings, breadcrumbs for the catalogo→truck path.
  const coverForLd = images.find((i: any) => i.is_cover)?.url ?? images[0]?.url;
  const restaurantLd = {
    "@context":   "https://schema.org",
    "@type":      "Restaurant",
    name:         truck.name,
    description:  truck.description ?? truck.tagline ?? undefined,
    url:          `/catalogo/${truck.slug}`,
    image:        coverForLd ? truckCover(coverForLd) : undefined,
    address:      truck.base_city ? { "@type": "PostalAddress", addressLocality: truck.base_city, addressCountry: "PT" } : undefined,
    servesCuisine: cats.length ? cats : undefined,
    priceRange:   truck.base_price ? `€${truck.base_price}+` : undefined,
    aggregateRating: Number(truck.rating_count) > 0
      ? {
          "@type":     "AggregateRating",
          ratingValue: Number(truck.rating_avg).toFixed(1),
          reviewCount: Number(truck.rating_count),
          bestRating:  5,
          worstRating: 1,
        }
      : undefined,
  };
  const breadcrumbLd = {
    "@context": "https://schema.org",
    "@type":    "BreadcrumbList",
    itemListElement: [
      { "@type": "ListItem", position: 1, name: t.breadcrumb_home, item: "/" },
      { "@type": "ListItem", position: 2, name: t.breadcrumb_catalog, item: "/catalogo" },
      { "@type": "ListItem", position: 3, name: truck.name,        item: `/catalogo/${truck.slug}` },
    ],
  };

  return (
    <div className="container" style={{ paddingTop: 120, paddingBottom: 80, maxWidth: 1100 }}>
      <script
        type="application/ld+json"
        // JSON.stringify drops `undefined` fields and the truck data is server-rendered,
        // so the payload is safe to inject without sanitization.
        dangerouslySetInnerHTML={{ __html: JSON.stringify(restaurantLd) }}
      />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(breadcrumbLd) }}
      />
      <nav className="breadcrumb">
        <Link href="/catalogo">{t.breadcrumb_catalog}</Link> &nbsp;/&nbsp; <span>{truck.name}</span>
      </nav>

      <h1 className="section-title" style={{ marginBottom: 8 }}>{truck.name}</h1>
      <p style={{ color: "var(--muted)", margin: 0, fontSize: 18 }}>{truck.tagline}</p>

      <div style={{ display: "grid", gridTemplateColumns: "2fr 1fr", gap: 20, marginTop: 24 }}>
        <div>
          <div className="thumb" style={{ aspectRatio: "16/10", position: "relative" }}>
            <Image
              src={truckCover(images[0]?.url)}
              alt={truck.name}
              fill
              sizes="(max-width: 768px) 100vw, 66vw"
              priority
              style={{ objectFit: "cover" }}
            />
          </div>
          {images.length > 1 && (
            <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 8, marginTop: 8 }}>
              {images.slice(1, 5).map((i: any) => (
                <div key={i.id} className="thumb" style={{ aspectRatio: "1/1", position: "relative" }}>
                  <Image
                    src={i.url}
                    alt={i.alt ?? ""}
                    fill
                    sizes="(max-width: 768px) 25vw, 165px"
                    style={{ objectFit: "cover" }}
                  />
                </div>
              ))}
            </div>
          )}

          <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 24 }}>{t.about_title}</h2>
          <p style={{ lineHeight: 1.65 }}>{truck.description ?? t.no_description}</p>

          {menu.length > 0 && (
            <>
              <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 24 }}>{t.menu_title}</h2>
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
            ★ {Number(truck.rating_avg).toFixed(1)} <span style={{ fontSize: 14, color: "var(--muted)" }}>({truck.rating_count} {t.reviews})</span>
          </div>
          <div style={{ marginTop: 14, display: "flex", flexDirection: "column", gap: 8, fontSize: 14 }}>
            <div><strong>{t.label_city}</strong> {truck.base_city ?? t.em_dash}</div>
            <div><strong>{t.label_capacity}</strong> {truck.capacity} {t.label_capacity_unit}</div>
            <div><strong>{t.label_radius}</strong> {truck.service_radius_km} {t.label_radius_unit}</div>
            <div><strong>{t.label_base_price}</strong> {truck.base_price ? money(truck.base_price) : t.em_dash}</div>
            <div><strong>{t.label_per_pax}</strong> {truck.price_per_pax ? money(truck.price_per_pax) : t.em_dash}</div>
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
              {t.login_to_invite}
            </Link>
          ) : myOpenRequests.length > 0 ? (
            <form action={invite} style={{ marginTop: 18 }}>
              <label style={{ display: "block", fontSize: 12, fontWeight: 700, textTransform: "uppercase", marginBottom: 6 }}>{t.invite_label}</label>
              <select name="request_id" className="filters-btn" style={{ width: "100%", padding: "10px 14px" }} required>
                {myOpenRequests.map((r) => (<option key={r.id} value={r.id}>{r.title}</option>))}
              </select>
              <button className="btn-pill" type="submit" style={{ marginTop: 10, width: "100%", justifyContent: "center" }}>{t.send_invite}</button>
            </form>
          ) : (
            <Link href="/publicar" className="btn-pill outline" style={{ marginTop: 18, width: "100%", justifyContent: "center", display: "inline-flex" }}>
              {t.publish_to_invite}
            </Link>
          )}
        </aside>
      </div>
    </div>
  );
}
