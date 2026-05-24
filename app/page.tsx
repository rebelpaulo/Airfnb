import Link from "next/link";
import { supabaseServer } from "@/lib/supabase/server";
import { truckCover } from "@/lib/img";

export const revalidate = 60;

const CATEGORIES = [
  { slug: "pizza",           label: "Pizza",            icon: "local_pizza" },
  { slug: "kebab",           label: "Kebab",            icon: "restaurant" },
  { slug: "hamburguer",      label: "Hamburguer",       icon: "lunch_dining" },
  { slug: "poke",            label: "Poke",             icon: "set_meal" },
  { slug: "sobremesas",      label: "Sobremesas",       icon: "icecream" },
  { slug: "pequeno-almoco",  label: "Pequeno Almoço",   icon: "free_breakfast" },
  { slug: "brunch",          label: "Brunch",           icon: "coffee" },
  { slug: "tacos",           label: "Tacos",            icon: "tapas" },
  { slug: "sushi",           label: "Sushi",            icon: "rice_bowl" },
  { slug: "bbq",             label: "BBQ",              icon: "outdoor_grill" },
  { slug: "sandwich",        label: "Sandwich",         icon: "bakery_dining" },
];

const THEMES: Array<{ label: string; img: string }> = [
  { label: "Casamentos",       img: "https://images.unsplash.com/photo-1519671482749-fd09be7ccebf?auto=format&fit=crop&w=1200&q=80" },
  { label: "Festivais",        img: "https://images.unsplash.com/photo-1533174072545-7a4b6ad7a6c3?auto=format&fit=crop&w=1200&q=80" },
  { label: "Conferências",     img: "https://images.unsplash.com/photo-1505373877841-8d25f7d46678?auto=format&fit=crop&w=1200&q=80" },
  { label: "Festas Privadas",  img: "https://images.unsplash.com/photo-1530103862676-de8c9debad1d?auto=format&fit=crop&w=1200&q=80" },
  { label: "Aniversários",     img: "https://images.unsplash.com/photo-1492684223066-81342ee5ff30?auto=format&fit=crop&w=1200&q=80" },
  { label: "Empresas",         img: "https://images.unsplash.com/photo-1511795409834-ef04bbd61622?auto=format&fit=crop&w=1200&q=80" },
];

const SERVICES = [
  { href: "/encontrar-espaco",    label: "Espaços para eventos",      img: "https://images.unsplash.com/photo-1519167758481-83f550bb49b3?auto=format&fit=crop&w=900&q=80" },
  { href: "/gestao-convidados",   label: "Gestão de Convidados",      img: "https://images.unsplash.com/photo-1492684223066-81342ee5ff30?auto=format&fit=crop&w=900&q=80" },
  { href: "/musica-animacao",     label: "Música e Animação",         img: "https://images.unsplash.com/photo-1470229722913-7c0e2dbbafd3?auto=format&fit=crop&w=900&q=80" },
  { href: "/marketing",           label: "Marketing e Publicidade",   img: "https://images.unsplash.com/photo-1432888622747-4eb9a8efeb07?auto=format&fit=crop&w=900&q=80" },
];

export default async function HomePage() {
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

  return (
    <>
      {/* ====== HERO ====== */}
      <section className="hero">
        <div className="logo-mark">air<span className="amp">&amp;</span>fb</div>
        <p className="tagline">A maior oferta de Food Trucks para o teu evento à distância de um click.</p>

        {/*
          Search bar is the entry-point for organizers publishing an event.
          We submit to /publicar so the wizard can prefill location + date +
          pax. TODO: replace the city input with a Google Places Autocomplete
          so the captured value is the same structured location we already
          collect during truck registration — this is what the matching
          algorithm joins on.
        */}
        <form action="/publicar" className="search-bar" autoComplete="off">
          <div className="field">
            <label htmlFor="where">Onde</label>
            <input id="where" name="city" type="text"
                   placeholder="Cidade ou localidade" list="airfnb-cities" />
            <datalist id="airfnb-cities">
              <option value="Lisboa" />
              <option value="Porto" />
              <option value="Cascais" />
              <option value="Sintra" />
              <option value="Coimbra" />
              <option value="Braga" />
              <option value="Aveiro" />
              <option value="Faro" />
              <option value="Algarve" />
              <option value="Setúbal" />
            </datalist>
          </div>
          <div className="field">
            <label htmlFor="checkin">Data</label>
            <input id="checkin" name="start_at" type="date" />
          </div>
          <div className="field">
            <label htmlFor="checkout">Fim (opcional)</label>
            <input id="checkout" name="end_at" type="date" />
          </div>
          <div className="field">
            <label htmlFor="guests">Convidados</label>
            <input id="guests" name="expected_pax" type="number" min={1} placeholder="Nº convidados" />
          </div>
          <button className="search-btn" type="submit">
            <span className="material-symbols-outlined">event</span>
            Tenho um evento
          </button>
        </form>

        {/* Secondary CTA right in the hero so truck owners have an obvious
            entry path without scrolling all the way to the community section. */}
        <div style={{ marginTop: 20, color: "#fff", fontSize: 15 }}>
          Tens um food truck?{" "}
          <Link href="/registar" style={{
            color: "#fff", fontWeight: 700, textDecoration: "underline",
            textUnderlineOffset: 4, textDecorationThickness: 2,
          }}>
            Regista aqui →
          </Link>
        </div>
      </section>

      {/* ====== CATEGORIES + TRUCKS GRID ====== */}
      <section className="section">
        <div className="container">
          <h2 className="section-title">Os nossos melhores parceiros</h2>

          <div className="category-strip">
            {CATEGORIES.map((c) => (
              <Link key={c.slug} href={`/catalogo?cat=${c.slug}`} className="cat">
                <span className="material-symbols-outlined">{c.icon}</span>
                {c.label}
              </Link>
            ))}
          </div>

          {trucks.length > 0 && (
            <div className="truck-grid">
              {trucks.map((t: any) => (
                <Link key={t.id} href={`/catalogo/${t.slug}`} className="truck-card">
                  <div className="thumb">
                    <img src={truckCover(t.cover_url)} alt={t.name}
                         style={{ width: "100%", height: "100%", objectFit: "cover" }} />
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
              Tens um food truck? Junta-te à comunidade.
            </div>
            <div style={{ opacity: 0.92, fontSize: 14, marginTop: 4 }}>
              Regista a empresa em 2 minutos, adiciona os teus trucks e começa a receber pedidos de eventos.
            </div>
          </div>
          <Link href="/registar" className="btn-pill"
                style={{ background: "#fff", color: "var(--orange-deep)" }}>
            Registar Food Truck
          </Link>
        </div>
      </section>

      {/* ====== COMO FUNCIONA ====== */}
      <section className="how-section">
        <div className="container">
          <div className="head">
            <div className="titles">
              <div className="eyebrow">Como funciona?</div>
              <h2>Três passos para um evento delicioso</h2>
            </div>
            <Link className="btn-pill outline" href="/catalogo">Encontrar Trucks</Link>
          </div>
          <div className="steps">
            <div className="step">
              <div className="num">1º</div>
              <h3>Encontra trucks que te interessem</h3>
              <p>Pesquisa no catálogo ou pede ajuda à equipa para encontrares os Trucks ideais para o teu evento.</p>
            </div>
            <div className="step">
              <div className="num">2º</div>
              <h3>A nossa equipa trata de tudo</h3>
              <p>Recebes uma proposta personalizada. Cuidamos da homologação dos trucks, contratos e logística.</p>
            </div>
            <div className="step">
              <div className="num">3º</div>
              <h3>Desfruta</h3>
              <p>Aproveita um evento com catering de sonho e sem qualquer complicação.</p>
            </div>
          </div>
        </div>
      </section>

      {/* ====== THEMED EVENTS ====== */}
      <section className="section">
        <div className="container">
          <h2 className="section-title" style={{ textAlign: "right", maxWidth: 680, marginLeft: "auto" }}>
            Inspire-se com os nossos<br />eventos temáticos
          </h2>
          <div className="themed-grid">
            {THEMES.map((t) => (
              <div key={t.label} className="themed-card">
                <div className="bg" style={{ backgroundImage: `url(${t.img})` }} />
                <span className="label">{t.label}</span>
              </div>
            ))}
          </div>
          <div className="center-cta">
            <Link className="btn-pill" href="/catalogo">Ver Todos</Link>
          </div>
        </div>
      </section>

      {/* ====== ORGANIZER ALTERNATIVE (secondary CTA, not hero) ====== */}
      <section className="alt-section">
        <div className="alt-left">
          <h2>A sua alternativa<br />de catering de eventos</h2>
          <p>Publica o teu evento grátis e recebe propostas dos melhores food trucks.</p>
          <Link className="btn-pill" href="/publicar">Publicar Pedido</Link>
        </div>
        <div className="alt-right"
             style={{ backgroundImage: "url('https://images.unsplash.com/photo-1556910103-1c02745aae4d?auto=format&fit=crop&w=1600&q=80')" }} />
      </section>

      <section className="feature-strip">
        <div className="container">
          <div className="feature-grid">
            <div><h4>Variedade</h4><p>Escolha entre uma ampla variedade de food trucks, de tacos a churros.</p></div>
            <div><h4>Custo</h4><p>Opções para todos os orçamentos, adaptadas à sua necessidade.</p></div>
            <div><h4>Qualidade</h4><p>Apenas food trucks certificados, garantindo um serviço de excelência.</p></div>
            <div><h4>Apoio Personalizado</h4><p>Uma equipa dedicada para um catering à medida do seu evento.</p></div>
          </div>
        </div>
      </section>

      {/* ====== PARTNERS LOGOS ====== */}
      <section className="partners-section">
        <div className="container">
          <h2 className="section-title">Trabalhamos com os melhores</h2>
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
          <h2 className="section-title">Oferecemos apoio completo<br />ao seu evento</h2>
          <div className="support-grid">
            {SERVICES.map((s) => (
              <Link key={s.href} href={s.href} className="support-card">
                <div className="bg" style={{ backgroundImage: `url(${s.img})` }} />
                <span className="label">{s.label}</span>
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
              <h2>Inspiração e dicas para um evento fora de série</h2>
              <p>Descubra tudo no nosso blog</p>
              <Link className="btn-pill" href="/blog">Ver Blog</Link>
            </div>
            <Link className="blog-feature" href="/blog"
                  style={{ backgroundImage: "url('https://images.unsplash.com/photo-1414235077428-338989a2e8c0?auto=format&fit=crop&w=1400&q=80')" }}>
              <div className="meta">
                <div className="title">Como organizar o evento perfeito com Food Trucks</div>
                <div className="date">19/01/2025</div>
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
          <div className="eyebrow">Tens uma Truck?</div>
          <h2>Entra na nossa comunidade<br />e ganha eventos no teu calendário</h2>
          <p style={{ maxWidth: 480, marginTop: -10, opacity: 0.92 }}>
            Regista a tua empresa em 2 minutos, adiciona os teus trucks e começa a aparecer aos organizers.
          </p>
          <Link className="btn-pill" href="/registar">Registar Food Truck</Link>
        </div>
      </section>

      {/* ====== FAQ ====== */}
      <section className="faq-section">
        <div className="container">
          <h2>Perguntas Frequentes</h2>
          <div className="faq-list">
            <details className="faq-item">
              <summary>Que tipos de trucks estão disponíveis?</summary>
              <div className="answer">Hambúrguer, pizza, sushi, tacos, BBQ, sobremesas, brunch e mais. Filtra no catálogo pelo estilo que procuras.</div>
            </details>
            <details className="faq-item">
              <summary>Quanto custa publicar um pedido de evento?</summary>
              <div className="answer">Zero. Os organizers publicam pedidos grátis. Cobramos só um lock-fee de €50 ao truck quando é aceite.</div>
            </details>
            <details className="faq-item">
              <summary>Em quanto tempo recebo propostas?</summary>
              <div className="answer">A maioria dos pedidos recebe a primeira proposta em menos de 4 horas, e a média total ronda 5-8 candidaturas em 24h.</div>
            </details>
            <details className="faq-item">
              <summary>Sou dono de truck — como me registo?</summary>
              <div className="answer">Clica em "Registar Food Truck" e completa o formulário da empresa. Podes adicionar quantos trucks tiveres. Cada truck passa por validação da nossa equipa antes de ficar visível no catálogo.</div>
            </details>
            <details className="faq-item">
              <summary>Restrições alimentares ou alergias?</summary>
              <div className="answer">A maioria dos trucks oferece opções vegetarianas, veganas e sem glúten. Indica as restrições no pedido.</div>
            </details>
          </div>
        </div>
      </section>

      {/* ====== CONTACT ====== */}
      <section className="contact-cta">
        <div className="container">
          <h2>Vamos conversar?</h2>
          <p>Tem alguma pergunta? Entre em contacto e a nossa equipa terá o maior prazer em ajudar.</p>
          <Link className="btn-pill" href="/ajuda">Contacte-nos</Link>
        </div>
      </section>
    </>
  );
}
