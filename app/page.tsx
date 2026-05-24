import Link from "next/link";
import { supabaseServer } from "@/lib/supabase/server";
import { money } from "@/lib/money";
import { truckCover } from "@/lib/img";

export const revalidate = 60;

export default async function HomePage() {
  const supa = await supabaseServer();
  const { data: openRequestsData } = await (supa as any)
    .from("airfnb_event_requests")
    .select("id, title, city, start_at, expected_pax, budget_min, budget_max, kind")
    .eq("status", "open")
    .order("start_at", { ascending: true })
    .limit(6);
  const openRequests = openRequestsData ?? [];

  const { data: featuredTrucksData } = await (supa as any)
    .from("airfnb_v_truck_card")
    .select("*")
    .eq("featured", true)
    .limit(6);
  const featuredTrucks = featuredTrucksData ?? [];

  return (
    <>
      {/* ----- DUAL HERO --------------------------------------------------- */}
      <section className="dual-hero">
        <div className="dual-hero__inner">
          <Link href="/publicar" className="dual-hero__side dual-hero__side--orange">
            <div className="eyebrow">Tens um evento?</div>
            <h1>Publica grátis<br />e recebe propostas em horas</h1>
            <p>Casamentos, festas, festivais. Os melhores food trucks do país aplicam ao teu pedido.</p>
            <span className="btn-pill">Publicar Pedido</span>
          </Link>
          <Link href="/pedidos" className="dual-hero__side dual-hero__side--teal">
            <div className="eyebrow">Tens um Food Truck?</div>
            <h1>Ganha eventos<br />no teu calendário</h1>
            <p>Vê pedidos abertos perto de ti e candidata-te aos que combinam contigo.</p>
            <span className="btn-pill outline">Ver Pedidos Abertos</span>
          </Link>
        </div>
      </section>

      {/* ----- COMO FUNCIONA (3 passos) ------------------------------------ */}
      <section className="how-section">
        <div className="container">
          <div className="head">
            <div className="titles">
              <div className="eyebrow">Como funciona?</div>
              <h2>Marketplace em 3 passos</h2>
            </div>
          </div>
          <div className="steps">
            <div className="step">
              <div className="num">1º</div>
              <h3>Publica o teu pedido</h3>
              <p>Tipo de evento, data, número de convidados, orçamento. Em 60 segundos.</p>
            </div>
            <div className="step">
              <div className="num">2º</div>
              <h3>Recebe candidaturas</h3>
              <p>Os trucks que dão match recebem alerta. Tu vês todas as propostas num só sítio.</p>
            </div>
            <div className="step">
              <div className="num">3º</div>
              <h3>Escolhe e desfruta</h3>
              <p>Aceitas os que quiseres. Eles pagam o lock-fee, ficam confirmados, falas via chat.</p>
            </div>
          </div>
        </div>
      </section>

      {/* ----- PEDIDOS ABERTOS (preview para trucks) ----------------------- */}
      {openRequests && openRequests.length > 0 && (
        <section className="section">
          <div className="container">
            <h2 className="section-title">Pedidos abertos agora</h2>
            <div className="truck-grid cols-4">
              {openRequests.map((r: any) => (
                <Link key={r.id} href={`/pedidos/${r.id}`} className="truck-card">
                  <div className="thumb" style={{ background: "linear-gradient(135deg,#FFE0D2,#FF6133)", display:"flex", alignItems:"flex-end", padding:"16px", color:"#fff" }}>
                    <span className="material-symbols-outlined" style={{ fontSize: 56, opacity: .65, marginRight: "auto" }}>event</span>
                    <span style={{ fontFamily:"Bebas Neue, sans-serif", fontSize:22 }}>{r.expected_pax} pax</span>
                  </div>
                  <div className="info">
                    <h3>{r.title}</h3>
                    <div className="meta">
                      <span className="loc">
                        <span className="material-symbols-outlined" style={{ fontSize: 18, color: "#FF4919" }}>location_on</span>
                        {r.city ?? "—"}
                      </span>
                      <span className="cap">
                        {new Date(r.start_at).toLocaleDateString("pt-PT", { day: "2-digit", month: "short" })}
                      </span>
                    </div>
                    <span className="tag">
                      Orçamento {r.budget_min ? money(r.budget_min) : "?"} – {r.budget_max ? money(r.budget_max) : "?"}
                    </span>
                  </div>
                </Link>
              ))}
            </div>
            <div className="center-cta">
              <Link className="btn-pill" href="/pedidos">Ver todos os pedidos</Link>
            </div>
          </div>
        </section>
      )}

      {/* ----- DESTAQUES DO CATÁLOGO --------------------------------------- */}
      {featuredTrucks && featuredTrucks.length > 0 && (
        <section className="section" style={{ background: "#FFF6F2" }}>
          <div className="container">
            <h2 className="section-title">Inspira-te com trucks em destaque</h2>
            <div className="truck-grid cols-4">
              {featuredTrucks.map((t: any) => (
                <Link key={t.id} href={`/catalogo/${t.slug}`} className="truck-card">
                  <div className="thumb">
                    <img src={truckCover(t.cover_url)} alt={t.name} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
                  </div>
                  <div className="info">
                    <h3>{t.name}</h3>
                    <div className="meta">
                      <span className="loc">
                        <span className="material-symbols-outlined" style={{ fontSize:18, color:"#FF4919" }}>location_on</span>
                        {t.base_city}
                      </span>
                      <span className="cap">
                        ★ {Number(t.rating_avg).toFixed(1)} ({t.rating_count})
                      </span>
                    </div>
                  </div>
                </Link>
              ))}
            </div>
            <div className="center-cta">
              <Link className="btn-pill" href="/catalogo">Ver catálogo completo</Link>
            </div>
          </div>
        </section>
      )}

      {/* ----- FAQ --------------------------------------------------------- */}
      <section className="faq-section">
        <div className="container">
          <h2>Perguntas Frequentes</h2>
          <div className="faq-list">
            <details className="faq-item"><summary>Quanto custa publicar um pedido?</summary><div className="answer">Zero. Os organizers publicam grátis e recebem propostas sem qualquer custo de plataforma.</div></details>
            <details className="faq-item"><summary>Como ganha a plataforma?</summary><div className="answer">Cobramos uma taxa de lock-fee de €50 ao truck que for aceite — €25 ficam connosco, €25 são adiantados ao organizer (descontados na conta final).</div></details>
            <details className="faq-item"><summary>Em quanto tempo recebo propostas?</summary><div className="answer">A maioria dos pedidos recebe a primeira proposta em menos de 4 horas, e a média total ronda 5-8 candidaturas em 24h.</div></details>
            <details className="faq-item"><summary>Posso convidar trucks específicos?</summary><div className="answer">Sim. Podes publicar em modo Curated e convidar apenas os trucks que escolheste do catálogo.</div></details>
          </div>
        </div>
      </section>
    </>
  );
}
