import Link from "next/link";
import type { Metadata } from "next";
import { PartnerLeadForm, type FieldConfig } from "@/components/PartnerLeadForm";

export const metadata: Metadata = {
  title: "Música & Animação — Air F&B",
  description:
    "DJ, banda ao vivo, animação infantil, fotografia ou vídeo? Os nossos parceiros cobrem todas as áreas de entretenimento para eventos. Diz-nos o que precisas — propomos as melhores opções.",
  alternates: { canonical: "/musica-animacao" },
};

const fields: FieldConfig[] = [
  { type: "text",   name: "event_type",  label: "Tipo de evento", required: true, placeholder: "Ex.: casamento, festa corporativa, festival" },
  { type: "date",   name: "event_date",  label: "Data do evento", required: true },
  { type: "text",   name: "venue",       label: "Local / cidade", placeholder: "Onde vai ser?" },
  { type: "number", name: "guest_count", label: "Nº estimado de convidados", placeholder: "Ex.: 100" },
  { type: "checkboxes", name: "services", label: "O que precisas?", options: [
    { value: "dj",          label: "DJ" },
    { value: "live_band",   label: "Banda ao vivo" },
    { value: "kids",        label: "Animação infantil" },
    { value: "host",        label: "Apresentador / MC" },
    { value: "photo",       label: "Fotografia" },
    { value: "video",       label: "Vídeo" },
    { value: "lighting",    label: "Iluminação cénica" },
    { value: "sound",       label: "PA / som" },
  ] },
  { type: "select", name: "duration", label: "Duração aproximada", options: [
    { value: "2-3h",  label: "2–3 horas" },
    { value: "4-6h",  label: "4–6 horas" },
    { value: "6-10h", label: "6–10 horas" },
    { value: "10h+",  label: "Mais de 10 horas / multi-dia" },
  ] },
  { type: "textarea", name: "vibe", label: "Estilo / vibe que procuras", rows: 3,
    placeholder: "Ex.: lounge no cocktail, set animado depois do jantar, foco em música portuguesa…" },
];

export default function MusicaAnimacaoPage() {
  return (
    <div className="container" style={{ paddingTop: 130, paddingBottom: 80, maxWidth: 820 }}>
      <h1 className="section-title">Música &amp; Animação</h1>
      <p style={{ color: "var(--muted)", marginTop: -10, fontSize: 17 }}>
        Da playlist de cocktail à pista cheia às 3 da manhã — temos parceiros
        para qualquer ambiente.
      </p>

      <section style={{
        marginTop: 26, padding: 22, background: "#fff",
        border: "1px solid var(--line)", borderRadius: 14,
      }}>
        <h2 style={{ margin: 0, fontSize: 22 }}>Rede curada de profissionais</h2>
        <p style={{ marginTop: 10, lineHeight: 1.6, color: "var(--ink)" }}>
          Trabalhamos com DJs, bandas, animadores, fotógrafos e técnicos
          espalhados pelo país. Não vendemos um pacote único — combinamos
          quem encaixa com o teu evento (estilo, duração, orçamento) e
          devolvemos 2–3 propostas comparáveis.
        </p>
        <p style={{ marginTop: 10, lineHeight: 1.6, color: "var(--ink)" }}>
          Como já sabemos a tipologia de food trucks que vais ter, calibramos
          o ambiente sonoro à hora (mais discreto à mesa, mais alto na pista)
          sem chocar com o serviço.
        </p>
        <ul style={{ marginTop: 14, paddingLeft: 20, color: "var(--ink)", lineHeight: 1.7 }}>
          <li>Selecção por estilo, duração e tipo de evento</li>
          <li>Profissionais com seguro e contrato em PT</li>
          <li>Iluminação e som incluídos quando faz sentido</li>
          <li>Resposta em 24h úteis</li>
        </ul>
      </section>

      <h2 style={{ marginTop: 36, fontSize: 22 }}>Conta-nos o que imaginas</h2>
      <PartnerLeadForm
        kind="music"
        intro="Quanto melhor descreveres a vibe, mais afinada a proposta."
        fields={fields}
        cta="Quero propostas de música e animação"
      />

      <p style={{ marginTop: 28, fontSize: 14 }}>
        <Link href="/" style={{ color: "var(--orange)" }}>← Voltar à página inicial</Link>
      </p>
    </div>
  );
}
