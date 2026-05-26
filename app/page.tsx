import Link from "next/link";
import Image from "next/image";
import type { Metadata } from "next";
import { supabaseServer } from "@/lib/supabase/server";
import { truckCover } from "@/lib/img";
import { Logo } from "@/components/Logo";
import { CityAutocomplete } from "@/components/CityAutocomplete";
import { getDictionary } from "@/lib/i18n";
import { getFavoritedTruckIds } from "@/lib/favorites";
import { HeartButton } from "@/components/HeartButton";

export const revalidate = 60;

// TODO: i18n metadata via generateMetadata
export const metadata: Metadata = {
  title: "Air F&B — Marketplace de Food Trucks para Eventos",
  description:
    "Publica o teu evento e recebe propostas dos melhores food trucks do país. Grátis para organizers.",
  alternates: { canonical: "/" },
};

const CATEGORY_SLUGS = [
  { slug: "pizza",           key: "cat_pizza",     icon: "local_pizza" },
  { slug: "kebab",           key: "cat_kebab",     icon: "restaurant" },
  { slug: "hamburguer",      key: "cat_hamburger", icon: "lunch_dining" },
  { slug: "poke",            key: "cat_poke",      icon: "set_meal" },
  { slug: "sobremesas",      key: "cat_desserts",  icon: "icecream" },
  { slug: "pequeno-almoco",  key: "cat_breakfast", icon: "free_breakfast" },
  { slug: "brunch",          key: "cat_brunch",    icon: "coffee" },
  { slug: "tacos",           key: "cat_tacos",     icon: "tapas" },
  { slug: "sushi",           key: "cat_sushi",     icon: "rice_bowl" },
  { slug: "bbq",             key: "cat_bbq",       icon: "outdoor_grill" },
  { slug: "sandwich",        key: "cat_sandwich",  icon: "bakery_dining" },
] as const;

// slug → dictionary-key lookup so featured-truck cards can render their
// category subtitle in the active locale instead of leaking the raw DB slug.
const CATEGORY_KEY_BY_SLUG = Object.fromEntries(
  CATEGORY_SLUGS.map((c) => [c.slug, c.key]),
) as Record<(typeof CATEGORY_SLUGS)[number]["slug"], (typeof CATEGORY_SLUGS)[number]["key"]>;

// Each card deep-links into /catalogo?event_kind=<kind>; the catalog
// filters via airfnb_trucks.compatible_event_kinds (truck owners pick
// these in the wizard). Kind matches the airfnb_event_kind enum.
const THEME_IMAGES = [
  { key: "theme_weddings",    kind: "wedding",    img: "https://images.unsplash.com/photo-1519671482749-fd09be7ccebf?auto=format&fit=crop&w=1200&q=80" },
  { key: "theme_festivals",   kind: "festival",   img: "https://images.unsplash.com/photo-1533174072545-7a4b6ad7a6c3?auto=format&fit=crop&w=1200&q=80" },
  { key: "theme_conferences", kind: "conference", img: "https://images.unsplash.com/photo-1505373877841-8d25f7d46678?auto=format&fit=crop&w=1200&q=80" },
  { key: "theme_private",     kind: "private",    img: "https://images.unsplash.com/photo-1530103862676-de8c9debad1d?auto=format&fit=crop&w=1200&q=80" },
  { key: "theme_birthdays",   kind: "birthday",   img: "https://images.unsplash.com/photo-1492684223066-81342ee5ff30?auto=format&fit=crop&w=1200&q=80" },
  { key: "theme_corporate",   kind: "corporate",  img: "https://images.unsplash.com/photo-1511795409834-ef04bbd61622?auto=format&fit=crop&w=1200&q=80" },
] as const;

const SERVICE_LINKS = [
  { href: "/encontrar-espaco",    key: "service_venues",     img: "https://images.unsplash.com/photo-1519167758481-83f550bb49b3?auto=format&fit=crop&w=900&q=80" },
  { href: "/gestao-convidados",   key: "service_guest_mgmt", img: "https://images.unsplash.com/photo-1492684223066-81342ee5ff30?auto=format&fit=crop&w=900&q=80" },
  { href: "/musica-animacao",     key: "service_music",      img: "https://images.unsplash.com/photo-1470229722913-7c0e2dbbafd3?auto=format&fit=crop&w=900&q=80" },
  { href: "/marketing",           key: "service_marketing",  img: "https://images.unsplash.com/photo-1432888622747-4eb9a8efeb07?auto=format&fit=crop&w=900&q=80" },
] as const;

export default async function HomePage() {
  const dict = await getDictionary();
  const t = dict.landing;
  const supa = await supabaseServer();
  // Stable ordering: highest-rated featured trucks first, with id as tiebreak
  // so the SSR/ISR cache stays consistent on re-render.
  const { data: featuredData } = await (supa as any)
    .from("airfnb_v_truck_card")
    .select("*")
    .eq("featured", true)
    .order("rating_avg", { ascending: false })
    .order("id", { ascending: true })
    .limit(6);
  let trucks = (featuredData as any[]) ?? [];

  if (trucks.length === 0) {
    const { data } = await (supa as any)
      .from("airfnb_v_truck_card")
      .select("*")
      .order("rating_avg", { ascending: false })
      .order("id", { ascending: true })
      .limit(6);
    trucks = (data as any[]) ?? [];
  }

  // Hearts on the featured cards. One DB read for the user's full favourites;
  // empty Set for visitors so the heart still renders (turns into sign-in CTA).
  const favoritedIds = await getFavoritedTruckIds();
  const { data: { user } } = await supa.auth.getUser();
  const authed = !!user;

  return (
    <>
      {/* ====== HERO ====== */}
      <section className="hero">
        {/*
          Hero logo would ideally take `priority` so it loads in the LCP burst,
          but the current <Logo> component renders a raw <img> and does not
          forward a priority prop. Leaving as-is rather than reshaping the
          component in this SEO sweep — track in a follow-up if LCP needs work.
        */}
        <Logo variant="white" height="clamp(110px, 18vw, 230px)" className="logo-mark" />
        <p className="tagline">{dict.common.tagline}</p>

        {/*
          Search bar is the entry-point for organizers exploring an event.
          We submit to /procurar — the discovery page shows an operations
          plan + filtered truck grid, and forwards the same params into
          /publicar via its CTA so the wizard can prefill step 1.
        */}
        <form action="/procurar" className="search-bar" autoComplete="off">
          <div className="field">
            <label htmlFor="where">{t.hero_question}</label>
            <CityAutocomplete name="city" placeholder={dict.common.city_placeholder} />
          </div>
          <div className="field">
            <label htmlFor="checkin">{dict.common.date}</label>
            <input id="checkin" name="start_at" type="date" />
          </div>
          <div className="field">
            <label htmlFor="checkout">{dict.common.end}</label>
            <input id="checkout" name="end_at" type="date" />
          </div>
          <div className="field">
            <label htmlFor="guests">{dict.common.guests}</label>
            <input id="guests" name="expected_pax" type="number" min={1} placeholder={dict.common.guests_placeholder} />
          </div>
          <button className="search-btn" type="submit">
            <span className="material-symbols-outlined">search</span>
            {t.hero_search_btn}
          </button>
        </form>

        {/* Secondary CTA right in the hero so truck owners have an obvious
            entry path without scrolling all the way to the community section. */}
        <div style={{ marginTop: 20, color: "#fff", fontSize: 15 }}>
          {t.hero_truck_prompt}{" "}
          <Link href="/registar" style={{
            color: "#fff", fontWeight: 700, textDecoration: "underline",
            textUnderlineOffset: 4, textDecorationThickness: 2,
          }}>
            {t.hero_truck_link}
          </Link>
        </div>
      </section>

      {/* ====== CATEGORIES + TRUCKS GRID ====== */}
      <section className="section">
        <div className="container">
          <h2 className="section-title">{t.partners_title}</h2>

          <div className="category-strip">
            {CATEGORY_SLUGS.map((c) => (
              <Link key={c.slug} href={`/catalogo?cat=${c.slug}`} className="cat">
                <span className="material-symbols-outlined">{c.icon}</span>
                {t[c.key]}
              </Link>
            ))}
          </div>

          {trucks.length > 0 && (
            <div className="truck-grid">
              {trucks.map((tr: any, idx: number) => (
                <Link key={tr.id} href={`/catalogo/${tr.slug}`} className="truck-card">
                  <div className="thumb" style={{ position: "relative" }}>
                    <Image
                      src={truckCover(tr.cover_url)}
                      alt={tr.name}
                      fill
                      sizes="(max-width: 600px) 100vw, (max-width: 1024px) 50vw, 25vw"
                      priority={idx === 0}
                      style={{ objectFit: "cover" }}
                    />
                    <HeartButton truckId={tr.id} initialFavorited={favoritedIds.has(tr.id)} authed={authed} />
                  </div>
                  <div className="info">
                    <h3>{tr.name}</h3>
                    <div className="subtitle">
                      {(tr.category_slugs ?? [])
                        .slice(0, 3)
                        .map((slug: string) => {
                          const key = CATEGORY_KEY_BY_SLUG[slug as keyof typeof CATEGORY_KEY_BY_SLUG];
                          return key ? (t as Record<string, string>)[key] ?? slug : slug;
                        })
                        .join(" · ")}
                    </div>
                    <div className="meta">
                      <span className="loc">
                        <span className="material-symbols-outlined" style={{ fontSize: 18, color: "#FF4919" }}>location_on</span>
                        {tr.base_city ?? "—"}
                      </span>
                      <span className="cap">
                        {Number(tr.rating_count) > 0
                          ? `★ ${Number(tr.rating_avg).toFixed(1)} (${tr.rating_count})`
                          : t.partner_truck_new}
                      </span>
                    </div>
                  </div>
                </Link>
              ))}
            </div>
          )}
        </div>
      </section>

      {/* ====== TRUCK OWNER CTA — banner above the fold for owners scrolling past the trucks grid ====== */}
      <section style={{
        background: "linear-gradient(90deg,#FF6133,#FF4919)",
        color: "#fff",
        padding: "26px 24px",
      }}>
        <div className="container" style={{
          display: "flex", justifyContent: "space-between", alignItems: "center",
          gap: 20, flexWrap: "wrap",
        }}>
          <div>
            <div style={{ fontFamily: "Bebas Neue, sans-serif", fontSize: 28, lineHeight: 1.1 }}>
              {t.community_eyebrow}
            </div>
            <div style={{ opacity: 0.92, fontSize: 14, marginTop: 4 }}>
              {t.community_copy}
            </div>
          </div>
          <Link href="/registar" className="btn-pill"
                style={{ background: "#fff", color: "var(--orange-deep)" }}>
            {t.community_cta}
          </Link>
        </div>
      </section>

      {/* ====== COMO FUNCIONA ====== */}
      <section className="how-section">
        <div className="container">
          <div className="head">
            <div className="titles">
              <div className="eyebrow">{t.how_eyebrow}</div>
              <h2>{t.how_title}</h2>
            </div>
            <Link className="btn-pill outline" href="/catalogo">{t.how_cta}</Link>
          </div>
          <div className="steps">
            <div className="step">
              <div className="num">{t.how_step1_num}</div>
              <h3>{t.how_step1_title}</h3>
              <p>{t.how_step1_copy}</p>
            </div>
            <div className="step">
              <div className="num">{t.how_step2_num}</div>
              <h3>{t.how_step2_title}</h3>
              <p>{t.how_step2_copy}</p>
            </div>
            <div className="step">
              <div className="num">{t.how_step3_num}</div>
              <h3>{t.how_step3_title}</h3>
              <p>{t.how_step3_copy}</p>
            </div>
          </div>
        </div>
      </section>

      {/* ====== THEMED EVENTS ====== */}
      <section className="section">
        <div className="container">
          <h2 className="section-title" style={{ textAlign: "right", maxWidth: 680, marginLeft: "auto" }}>
            {t.themes_title}<br />{t.themes_title2}
          </h2>
          <div className="themed-grid">
            {THEME_IMAGES.map((th) => (
              <Link key={th.key} href={`/catalogo?event_kind=${th.kind}`} className="themed-card">
                <div className="bg" style={{ backgroundImage: `url(${th.img})` }} />
                <span className="label">{t[th.key]}</span>
              </Link>
            ))}
          </div>
          <div className="center-cta">
            <Link className="btn-pill" href="/catalogo">{t.themes_cta}</Link>
          </div>
        </div>
      </section>

      {/* ====== ORGANIZER ALTERNATIVE (secondary CTA, not hero) ====== */}
      <section className="alt-section">
        <div className="alt-left">
          <h2>{t.alt_title1}<br />{t.alt_title2}</h2>
          <p>{t.alt_copy}</p>
          <Link className="btn-pill" href="/publicar">{t.alt_cta}</Link>
        </div>
        <div className="alt-right"
             style={{ backgroundImage: "url('https://images.unsplash.com/photo-1556910103-1c02745aae4d?auto=format&fit=crop&w=1600&q=80')" }} />
      </section>

      <section className="feature-strip">
        <div className="container">
          <div className="feature-grid">
            <div><h4>{t.feature_variety_title}</h4><p>{t.feature_variety_copy}</p></div>
            <div><h4>{t.feature_cost_title}</h4><p>{t.feature_cost_copy}</p></div>
            <div><h4>{t.feature_quality_title}</h4><p>{t.feature_quality_copy}</p></div>
            <div><h4>{t.feature_support_title}</h4><p>{t.feature_support_copy}</p></div>
          </div>
        </div>
      </section>

      {/* ====== PARTNERS LOGOS ====== */}
      <section className="partners-section">
        <div className="container">
          <h2 className="section-title">{t.partners_logos_title}</h2>
          <div className="partners-logos">
            {Array.from({ length: 6 }).map((_, i) => (
              <div key={i} className="partner-logo">
                new<br />sheet<span className="small">ENTERTAINMENT</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ====== SUPPORT SERVICES ====== */}
      <section className="support-section">
        <div className="container">
          <h2 className="section-title">{t.support_title1}<br />{t.support_title2}</h2>
          <div className="support-grid">
            {SERVICE_LINKS.map((s) => (
              <Link key={s.href} href={s.href} className="support-card">
                <div className="bg" style={{ backgroundImage: `url(${s.img})` }} />
                <span className="label">{t[s.key]}</span>
              </Link>
            ))}
          </div>
        </div>
      </section>

      {/* ====== BLOG TEASER ====== */}
      <section className="blog-teaser">
        <div className="container">
          <div className="row">
            <div>
              <h2>{t.blog_teaser_title}</h2>
              <p>{t.blog_teaser_copy}</p>
              <Link className="btn-pill" href="/blog">{t.blog_teaser_cta}</Link>
            </div>
            <Link className="blog-feature" href="/blog"
                  style={{ backgroundImage: "url('https://images.unsplash.com/photo-1414235077428-338989a2e8c0?auto=format&fit=crop&w=1400&q=80')" }}>
              <div className="meta">
                <div className="title">{t.blog_feature_title}</div>
                <div className="date">{t.blog_feature_date}</div>
              </div>
            </Link>
          </div>
        </div>
      </section>

      {/* ====== TRUCK COMMUNITY — PRIMARY CTA ====== */}
      <section className="community-section">
        <div className="community-left"
             style={{ backgroundImage: "url('https://images.unsplash.com/photo-1551218372-a8789b81b253?auto=format&fit=crop&w=1400&q=80')" }} />
        <div className="community-right">
          <div className="eyebrow">{t.truck_community_eyebrow}</div>
          <h2>{t.truck_community_title1}<br />{t.truck_community_title2}</h2>
          <p style={{ maxWidth: 480, marginTop: -10, opacity: 0.92 }}>
            {t.truck_community_copy}
          </p>
          <Link className="btn-pill" href="/registar">{t.truck_community_cta}</Link>
        </div>
      </section>

      {/* ====== FAQ ====== */}
      <section className="faq-section">
        <div className="container">
          <h2>{t.faq_title}</h2>
          <div className="faq-list">
            <details className="faq-item">
              <summary>{t.faq_q1}</summary>
              <div className="answer">{t.faq_a1}</div>
            </details>
            <details className="faq-item">
              <summary>{t.faq_q2}</summary>
              <div className="answer">{t.faq_a2}</div>
            </details>
            <details className="faq-item">
              <summary>{t.faq_q3}</summary>
              <div className="answer">{t.faq_a3}</div>
            </details>
            <details className="faq-item">
              <summary>{t.faq_q4}</summary>
              <div className="answer">{t.faq_a4}</div>
            </details>
            <details className="faq-item">
              <summary>{t.faq_q5}</summary>
              <div className="answer">{t.faq_a5}</div>
            </details>
          </div>
        </div>
      </section>

      {/* ====== CONTACT ====== */}
      <section className="contact-cta">
        <div className="container">
          <h2>{t.contact_title}</h2>
          <p>{t.contact_copy}</p>
          <Link className="btn-pill" href="/ajuda">{t.contact_cta}</Link>
        </div>
      </section>
    </>
  );
}
