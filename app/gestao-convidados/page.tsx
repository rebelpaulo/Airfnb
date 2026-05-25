import Link from "next/link";
import type { Metadata } from "next";
import { PartnerLeadForm, type FieldConfig } from "@/components/PartnerLeadForm";

export const metadata: Metadata = {
  title: "Gestão de Convidados, Bilhética & Cashless — Air F&B",
  description:
    "Vendes bilhetes, geres convidados, ou precisas de cashless e POS no teu evento? Em parceria com a 3cket — a plataforma portuguesa que cobre bilhética, listas, fast-track e pagamentos no recinto.",
  alternates: { canonical: "/gestao-convidados" },
};

const fields: FieldConfig[] = [
  { type: "text",   name: "event_name",  label: "Nome do evento (se já tiver)", placeholder: "Ex.: Festa de aniversário — 30 anos" },
  { type: "date",   name: "event_date",  label: "Data do evento", required: true },
  { type: "number", name: "guest_count", label: "Nº estimado de convidados", required: true, placeholder: "Ex.: 250" },
  { type: "text",   name: "venue",       label: "Local / venue", placeholder: "Onde vai ser?" },
  { type: "checkboxes", name: "needs", label: "O que precisas?", options: [
    { value: "ticketing",    label: "Bilhética online" },
    { value: "guest_list",   label: "Gestão de listas / RSVP" },
    { value: "cashless",     label: "Pulseira cashless" },
    { value: "pos",          label: "POS no recinto" },
    { value: "fast_track",   label: "Fast-track / VIP" },
    { value: "access_control", label: "Controlo de acessos com QR" },
  ] },
  { type: "textarea", name: "notes",     label: "Detalhes adicionais", rows: 3,
    placeholder: "Tipos de bilhete, preços-alvo, datas de venda…" },
];

export default function GestaoConvidadosPage() {
  return (
    <div className="container" style={{ paddingTop: 130, paddingBottom: 80, maxWidth: 820 }}>
      <h1 className="section-title">Gestão de Convidados, Bilhética &amp; Cashless</h1>
      <p style={{ color: "var(--muted)", marginTop: -10, fontSize: 17 }}>
        Da venda de bilhetes ao pagamento dentro do recinto — em parceria com
        a <strong>3cket</strong>, a plataforma portuguesa que ajuda centenas
        de eventos todos os meses.
      </p>

      <section style={{
        marginTop: 26, padding: 22, background: "#fff",
        border: "1px solid var(--line)", borderRadius: 14,
      }}>
        <h2 style={{ margin: 0, fontSize: 22 }}>Porquê a 3cket?</h2>
        <p style={{ marginTop: 10, lineHeight: 1.6, color: "var(--ink)" }}>
          Empresa irmã da Air F&amp;B, a 3cket nasceu no mercado português e
          conhece a fundo o que organizadores aqui precisam: bilhética com
          múltiplos tipos e preços, gestão de listas de convidados com QR à
          porta, pulseiras cashless integradas com POS no recinto e fast-track
          para mesas VIP em nightlife.
        </p>
        <ul style={{ marginTop: 14, paddingLeft: 20, color: "var(--ink)", lineHeight: 1.7 }}>
          <li><strong>Bilhética e RSVP</strong> — venda online, controlo de check-in com QR</li>
          <li><strong>Cashless</strong> — pulseiras pré-carregadas, recarregamento on-site</li>
          <li><strong>POS no recinto</strong> — terminais sincronizados, relatórios em tempo real</li>
          <li><strong>Fast-track &amp; VIP</strong> — listas, mesas, ordering prioritário</li>
          <li><strong>Cobertura nacional</strong> — Lisboa, Porto, Algarve, ilhas</li>
        </ul>
        <p style={{ marginTop: 14, lineHeight: 1.6, color: "var(--ink)" }}>
          Quando preencheres o formulário abaixo, recebemos o teu pedido em
          conjunto: a 3cket prepara a proposta da bilhética e nós ajustamos
          os trucks à tipologia de convidados e ao horário.
        </p>
      </section>

      <h2 style={{ marginTop: 36, fontSize: 22 }}>Conta-nos o teu evento</h2>
      <PartnerLeadForm
        kind="guest_mgmt"
        intro="Resposta em 24h úteis com a proposta da 3cket (e dos trucks compatíveis, se quiseres)."
        fields={fields}
        cta="Quero conhecer a 3cket"
      />

      <p style={{ marginTop: 28, fontSize: 14 }}>
        <Link href="/" style={{ color: "var(--orange)" }}>← Voltar à página inicial</Link>
      </p>
    </div>
  );
}
