import Link from "next/link";
import { notFound } from "next/navigation";
import type { Metadata } from "next";
import { supabaseServer } from "@/lib/supabase/server";
import { money } from "@/lib/money";
import { truckCover } from "@/lib/img";
import { getDictionary } from "@/lib/i18n";
import { getFavoritedTruckIds } from "@/lib/favorites";
import { HeartButton } from "@/components/HeartButton";
import { TruckGallery } from "@/components/TruckGallery";

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
      airfnb_truck_images ( id, url, alt, is_cover, sort_order, kind ),
      airfnb_menu_items   ( id, name, description, price, category ),
      airfnb_truck_categories ( airfnb_categories ( slug, name_pt, icon ) ),
      owner:airfnb_profiles!airfnb_trucks_owner_id_fkey ( id, display_name, full_name, avatar_url, created_at )
    `)
    .eq("slug", slug)
    .maybeSingle();
  if (!truck) notFound();

  // Reviews + truck documents — parallel fetches so the detail page stays
  // a single roundtrip even with the richer layout. Reviews join the
  // reviewer's display_name for the "by X" line.
  const [reviewsRes, docsRes] = await Promise.all([
    (supa as any)
      .from("airfnb_reviews")
      .select(`
        id, rating_overall, body, reply_body, reply_at, is_verified, created_at,
        reviewer:airfnb_profiles!airfnb_reviews_organizer_id_fkey ( display_name, full_name )
      `)
      .eq("truck_id", truck.id)
      .order("created_at", { ascending: false })
      .limit(6),
    (supa as any)
      .from("airfnb_truck_documents")
      .select("kind, expires_at")
      .eq("truck_id", truck.id),
  ]);
  const reviews: any[] = reviewsRes.data ?? [];
  const docs: any[]    = docsRes.data ?? [];

  // Order matches the airfnb_v_truck_card view: truck → food → venue →
  // team → other, then is_cover, then sort_order. Keeps the carousel
  // semantically grouped so organisers see the truck first.
  const KIND_RANK: Record<string, number> = { truck: 1, food: 2, venue: 3, team: 4, other: 5 };
  const images = (truck.airfnb_truck_images ?? [])
    .slice()
    .sort((a: any, b: any) =>
      (KIND_RANK[a.kind ?? "other"] - KIND_RANK[b.kind ?? "other"]) ||
      ((b.is_cover ? 1 : 0) - (a.is_cover ? 1 : 0)) ||
      (a.sort_order - b.sort_order)
    );
  const menu = (truck.airfnb_menu_items ?? []);
  const cats = (truck.airfnb_truck_categories ?? []).map((tc:any)=> tc.airfnb_categories?.name_pt).filter(Boolean);

  const { data: { user } } = await supa.auth.getUser();
  const authed = !!user;
  // Heart state for the sidebar button. One read per page; falls back to
  // empty Set for anon visitors (HeartButton then renders a sign-in CTA).
  const favoritedIds = await getFavoritedTruckIds();
  const initialFavorited = favoritedIds.has(truck.id);
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
      {truck.tagline && <p style={{ color: "var(--muted)", margin: 0, fontSize: 18 }}>{truck.tagline}</p>}

      {/* Stat strip — one line summary that travels with the H1. The
          fields the organizer cares about most for an at-a-glance call:
          rating, response speed, location. */}
      <div style={{ display: "flex", gap: 18, flexWrap: "wrap", marginTop: 10, fontSize: 14, color: "var(--muted)" }}>
        {truck.rating_count > 0 && Number.isFinite(Number(truck.rating_avg)) ? (
          <span><strong style={{ color: "var(--ink)" }}>★ {Number(truck.rating_avg).toFixed(1)}</strong> ({truck.rating_count} {t.reviews})</span>
        ) : (
          <span>{t.unrated}</span>
        )}
        {Number(truck.lead_response_rate) > 0 && (
          <span>·</span>
        )}
        {Number(truck.lead_response_rate) > 0 && (
          <span>{Number(truck.lead_response_rate) >= 0.9 ? t.stat_response_high : fmtTpl(t.stat_responds_in, { h: "24" })}</span>
        )}
        {truck.base_city && (<><span>·</span><span>{truck.base_city}</span></>)}
      </div>

      <div style={{ marginTop: 22 }}>
        <TruckGallery
          images={images.length > 0
            ? images.map((i: any) => ({ id: i.id, url: i.url, alt: i.alt }))
            : [{ id: "placeholder", url: truckCover(null), alt: truck.name }]
          }
          fallbackAlt={truck.name}
        />
      </div>

      {/* Trust badges — only render the ones we actually have. Each
          chip is a positive trust signal; expired/expiring states use
          the warning style so the organizer notices before booking. */}
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 18 }}>
        {trustBadges(docs, truck, t).map((b, i) => (
          <span key={i} style={{
            display: "inline-flex", alignItems: "center", gap: 6,
            padding: "6px 12px", borderRadius: 999,
            border: `1px solid ${b.tone === "warn" ? "#E2B341" : "var(--line)"}`,
            background: b.tone === "warn" ? "#FFF8E6" : "#fff",
            color: "var(--ink)", fontSize: 13, fontWeight: 600,
          }}>
            <span className="material-symbols-outlined" aria-hidden="true" style={{ fontSize: 16, color: b.tone === "warn" ? "#A57600" : "#10A37F" }}>
              {b.tone === "warn" ? "warning" : "verified"}
            </span>
            {b.label}
          </span>
        ))}
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "2fr 1fr", gap: 28, marginTop: 28 }}>
        <div>
          {/* ABOUT */}
          <section>
            <h2 style={sectionTitle}>{t.about_title}</h2>
            <p style={{ lineHeight: 1.65 }}>{truck.description ?? t.no_description}</p>
          </section>

          {/* WHAT WE SERVE */}
          <section style={{ marginTop: 28 }}>
            <h2 style={sectionTitle}>{t.section_serves}</h2>
            {Array.isArray(truck.cuisine_types) && truck.cuisine_types.length > 0 && (
              <ChipRow items={truck.cuisine_types} dict={dict.vocab.cuisines as Record<string, string>} accent="orange" />
            )}
            {Array.isArray(truck.dietary_options) && truck.dietary_options.length > 0 && (
              <>
                <div style={{ fontSize: 12, color: "var(--muted)", fontWeight: 700, textTransform: "uppercase", letterSpacing: 0.3, marginTop: 12 }}>{t.dietary_label}</div>
                <ChipRow items={truck.dietary_options} dict={{ vegetarian: "Vegetariano", vegan: "Vegan", gluten_free: "Sem glúten" }} accent="teal" />
              </>
            )}
            {truck.catering_type && (
              <div style={{ marginTop: 12, fontSize: 14, color: "var(--muted)" }}>
                <span className="material-symbols-outlined" aria-hidden="true" style={{ fontSize: 16, verticalAlign: "middle", color: "var(--orange)" }}>restaurant</span>{" "}
                {cateringLabel(truck.catering_type, t)}
              </div>
            )}
          </section>

          {/* MENU */}
          {menu.length > 0 && (
            <section style={{ marginTop: 28 }}>
              <h2 style={sectionTitle}>{t.menu_title}</h2>
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
            </section>
          )}

          {/* IDEAL FOR */}
          <section style={{ marginTop: 28 }}>
            <h2 style={sectionTitle}>{t.section_ideal}</h2>
            <p style={{ color: "var(--muted)", margin: "4px 0 10px", fontSize: 14 }}>
              {idealPaxLabel(truck.min_event_pax, truck.max_event_pax, t)}
            </p>
            {Array.isArray(truck.compatible_event_kinds) && truck.compatible_event_kinds.length > 0 && (
              <ChipRow items={truck.compatible_event_kinds} dict={dict.vocab.event_kinds as Record<string, string>} accent="teal" />
            )}
          </section>

          {/* LOGISTICS */}
          <section style={{ marginTop: 28 }}>
            <h2 style={sectionTitle}>{t.section_logistics}</h2>
            <div style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))",
              gap: 12, marginTop: 6,
            }}>
              <LogisticsTile icon="bolt" label={t.logistics_power} value={
                Number(truck.power_required_kw) > 0 ? fmtTpl(t.logistics_power_val, { kw: truck.power_required_kw }) : t.logistics_power_none
              } />
              <LogisticsTile icon="water_drop" label={t.logistics_water} value={truck.needs_water ? t.logistics_water_yes : t.logistics_water_no} />
              {truck.setup_minutes != null && (
                <LogisticsTile icon="schedule" label={t.logistics_setup} value={fmtTpl(t.logistics_setup_val, { min: truck.setup_minutes })} />
              )}
              {truck.teardown_minutes != null && (
                <LogisticsTile icon="schedule" label={t.logistics_teardown} value={fmtTpl(t.logistics_teardown_val, { min: truck.teardown_minutes })} />
              )}
              {Array.isArray(truck.dimensions_m) && truck.dimensions_m.length === 3 && (
                <LogisticsTile icon="straighten" label={t.logistics_dimensions} value={fmtTpl(t.logistics_dimensions_val, { w: truck.dimensions_m[0], l: truck.dimensions_m[1], h: truck.dimensions_m[2] })} />
              )}
              {truck.sanitation_required && (
                <LogisticsTile icon="wc" label={t.logistics_sanitation} value={sanitationLabel(truck.sanitation_required, t)} />
              )}
            </div>
          </section>

          {/* REVIEWS */}
          <section style={{ marginTop: 28 }}>
            <h2 style={sectionTitle}>{t.section_reviews}</h2>
            {reviews.length === 0 ? (
              <p style={{ color: "var(--muted)" }}>{t.reviews_empty}</p>
            ) : (
              <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
                {reviews.map((r: any) => {
                  const reviewerName = r.reviewer?.display_name?.trim() || r.reviewer?.full_name?.trim() || t.review_anonymous;
                  const dateStr = new Date(r.created_at).toLocaleDateString("pt-PT", { year: "numeric", month: "long" });
                  return (
                    <article key={r.id} style={{ border: "1px solid var(--line)", borderRadius: 10, padding: 14, background: "#fff" }}>
                      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: 8 }}>
                        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                          <strong>{reviewerName}</strong>
                          <span style={{ color: "var(--muted)", fontSize: 13 }}>· {dateStr}</span>
                        </div>
                        <span style={{ color: "var(--orange)", fontWeight: 700 }}>★ {Number(r.rating_overall).toFixed(1)}</span>
                      </div>
                      {r.body && <p style={{ marginTop: 8, lineHeight: 1.55 }}>{r.body}</p>}
                      {r.reply_body && (
                        <div style={{ marginTop: 10, padding: 10, background: "var(--soft-bg, #F6F7F9)", borderRadius: 8, fontSize: 14 }}>
                          <div style={{ fontSize: 12, fontWeight: 700, color: "var(--muted)", textTransform: "uppercase" }}>{t.review_owner_replied}</div>
                          <div style={{ marginTop: 4 }}>{r.reply_body}</div>
                        </div>
                      )}
                    </article>
                  );
                })}
                {Number(truck.rating_count) > reviews.length && (
                  <div style={{ color: "var(--muted)", fontSize: 14 }}>
                    {fmtTpl(t.reviews_show_all, { n: truck.rating_count })}
                  </div>
                )}
              </div>
            )}
          </section>
        </div>

        {/* STICKY SIDEBAR */}
        <aside style={{ position: "sticky", top: 100, alignSelf: "flex-start", padding: 22, background: "#fff", borderRadius: 14, boxShadow: "var(--shadow-card)" }}>
          {/* Owner card */}
          {truck.owner && (
            <div style={{ display: "flex", alignItems: "center", gap: 12, paddingBottom: 14, marginBottom: 14, borderBottom: "1px solid var(--line)" }}>
              {truck.owner.avatar_url ? (
                /* eslint-disable-next-line @next/next/no-img-element */
                <img src={truck.owner.avatar_url} alt="" style={{ width: 44, height: 44, borderRadius: "50%", objectFit: "cover" }} />
              ) : (
                <div style={{ width: 44, height: 44, borderRadius: "50%", background: "var(--orange)", color: "#fff", display: "inline-flex", alignItems: "center", justifyContent: "center", fontWeight: 700 }}>
                  {(truck.owner.display_name ?? truck.owner.full_name ?? "?").trim().slice(0, 1).toUpperCase()}
                </div>
              )}
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 12, color: "var(--muted)", fontWeight: 700, textTransform: "uppercase", letterSpacing: 0.3 }}>{t.section_owner}</div>
                <div style={{ fontWeight: 700, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                  {truck.owner.display_name ?? truck.owner.full_name ?? "—"}
                </div>
                {truck.owner.created_at && (
                  <div style={{ fontSize: 12, color: "var(--muted)" }}>
                    {fmtTpl(t.trust_member_since, { year: String(new Date(truck.owner.created_at).getFullYear()) })}
                  </div>
                )}
              </div>
              <HeartButton truckId={truck.id} initialFavorited={initialFavorited} authed={authed} absolute={false} />
            </div>
          )}

          {/* Price block */}
          <div style={{ display: "grid", gap: 6, fontSize: 14 }}>
            <div style={{ fontFamily: "Bebas Neue, sans-serif", fontSize: 26, color: "var(--orange)" }}>
              {truck.base_price ? money(truck.base_price) : t.em_dash}
              <span style={{ fontSize: 13, color: "var(--muted)", marginLeft: 6 }}>base</span>
            </div>
            <div>
              <span style={{ color: "var(--muted)" }}>{t.label_per_pax} </span>
              <strong>{truck.price_per_pax ? money(truck.price_per_pax) : t.em_dash}</strong>
            </div>
            <div>
              <span style={{ color: "var(--muted)" }}>{t.label_capacity} </span>
              <strong>{truck.capacity} {t.label_capacity_unit}</strong>
            </div>
            <div>
              <span style={{ color: "var(--muted)" }}>{t.label_radius} </span>
              <strong>{truck.service_radius_km} {t.label_radius_unit}</strong>
            </div>
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

// =====================================================================
// Helpers
// =====================================================================

const sectionTitle: React.CSSProperties = {
  fontFamily: "Bebas Neue, sans-serif",
  color: "var(--teal)",
  fontSize: 22,
  margin: 0,
  marginBottom: 8,
};

function fmtTpl(template: string, vars: Record<string, string | number>): string {
  return (template ?? "").replace(/\{(\w+)\}/g, (_, k) => String(vars[k] ?? ""));
}

function ChipRow({ items, dict, accent }: {
  items: string[];
  dict: Record<string, string>;
  accent: "orange" | "teal";
}) {
  const bg = accent === "orange" ? "#FFF6F2" : "#EEF6F7";
  const fg = accent === "orange" ? "var(--orange-deep)" : "var(--teal)";
  return (
    <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginTop: 6 }}>
      {items.map((it) => (
        <span key={it} style={{
          display: "inline-block", padding: "5px 12px", borderRadius: 999,
          background: bg, color: fg, fontSize: 13, fontWeight: 600,
        }}>{dict?.[it] ?? it}</span>
      ))}
    </div>
  );
}

function LogisticsTile({ icon, label, value }: { icon: string; label: string; value: string }) {
  return (
    <div style={{ border: "1px solid var(--line)", borderRadius: 10, padding: 14, background: "#fff" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <span className="material-symbols-outlined" aria-hidden="true" style={{ fontSize: 20, color: "var(--orange)" }}>{icon}</span>
        <div style={{ fontSize: 12, color: "var(--muted)", textTransform: "uppercase", letterSpacing: 0.3, fontWeight: 700 }}>{label}</div>
      </div>
      <div style={{ fontSize: 15, fontWeight: 600, marginTop: 4 }}>{value}</div>
    </div>
  );
}

type TrustBadge = { label: string; tone: "ok" | "warn" };
function trustBadges(docs: any[], truck: any, t: Record<string, string>): TrustBadge[] {
  const out: TrustBadge[] = [];
  const today = Date.now();
  const dayMs = 86400000;
  // ASAE + insurance — pull from airfnb_truck_documents (kind='asae' / 'seguro')
  // first, fall back to the per-truck homologation/insurance columns if no
  // doc row is present.
  const asaeExp = (docs.find((d) => d.kind === "asae")?.expires_at) ?? truck.homologation_expires_at;
  if (asaeExp) {
    const days = Math.round((new Date(asaeExp).getTime() - today) / dayMs);
    if (days < 0) out.push({ label: t.trust_asae_expired, tone: "warn" });
    else if (days < 30) out.push({ label: fmtTpl(t.trust_asae_expiring, { days }), tone: "warn" });
    else out.push({ label: t.trust_asae_ok, tone: "ok" });
  }
  const insExp = (docs.find((d) => d.kind === "seguro")?.expires_at) ?? truck.insurance_expires_at;
  if (insExp) {
    const days = Math.round((new Date(insExp).getTime() - today) / dayMs);
    if (days < 0) out.push({ label: t.trust_insurance_expired, tone: "warn" });
    else if (days < 30) out.push({ label: fmtTpl(t.trust_insurance_expiring, { days }), tone: "warn" });
    else out.push({ label: t.trust_insurance_ok, tone: "ok" });
  }
  if (truck.status === "active") out.push({ label: t.trust_verified, tone: "ok" });
  return out;
}

function cateringLabel(v: string, t: Record<string, string>): string {
  if (v === "food") return t.catering_food_label;
  if (v === "drinks") return t.catering_drinks_label;
  if (v === "food_and_drinks") return t.catering_both_label;
  return v;
}

function sanitationLabel(v: string, t: Record<string, string>): string {
  if (v === "nao_necessario" || v === "none") return t.logistics_sanitation_none;
  if (v === "wc_proximo") return t.logistics_sanitation_proximo;
  if (v === "wc_dedicado") return t.logistics_sanitation_dedicado;
  return v;
}

function idealPaxLabel(min: number | null, max: number | null, t: Record<string, string>): string {
  if (min && max) return fmtTpl(t.ideal_pax_range, { min, max });
  if (min)        return fmtTpl(t.ideal_pax_min,   { min });
  if (max)        return fmtTpl(t.ideal_pax_max,   { max });
  return "";
}
