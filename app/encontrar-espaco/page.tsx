import Link from "next/link";
import type { Metadata } from "next";
import { PartnerLeadForm, type FieldConfig } from "@/components/PartnerLeadForm";

export const metadata: Metadata = {
  title: "Espaços para Eventos — Air F&B",
  description:
    "Estás a planear um evento e precisas do espaço perfeito? Os nossos parceiros conhecem quintas, terraços, jardins e salões em todo o país. Diz-nos o que precisas — voltamos a contactar-te.",
  alternates: { canonical: "/encontrar-espaco" },
};

const fields: FieldConfig[] = [
  { type: "text",   name: "event_type",    label: "Que tipo de evento?", required: true, placeholder: "Ex.: casamento, festa de empresa, aniversário" },
  { type: "date",   name: "event_date",    label: "Data prevista (aproximada)" },
  { type: "number", name: "guest_count",   label: "Nº estimado de convidados", required: true, placeholder: "Ex.: 80" },
  { type: "number", name: "area_sqm",      label: "Área necessária aproximada (m²)", placeholder: "Ex.: 150" },
  { type: "radio",  name: "indoor_outdoor", label: "Onde gostarias?", required: true,
    options: [
      { value: "indoor",  label: "Interior" },
      { value: "outdoor", label: "Exterior" },
      { value: "both",    label: "Misto / qualquer" },
    ],
  },
  { type: "text",   name: "city",          label: "Cidade / zona pretendida", placeholder: "Ex.: Lisboa, Porto, Algarve" },
  { type: "textarea", name: "notes",       label: "Notas adicionais", rows: 3,
    placeholder: "Estacionamento, acessibilidade, particularidades…" },
];

export default function EncontrarEspacoPage() {
  return (
    <div className="container" style={{ paddingTop: 130, paddingBottom: 80, maxWidth: 820 }}>
      <h1 className="section-title">Espaços para Eventos</h1>
      <p style={{ color: "var(--muted)", marginTop: -10, fontSize: 17 }}>
        Encontra o espaço perfeito para o teu evento — sem perderes semanas
        a pesquisar.
      </p>

      <section style={{
        marginTop: 26, padding: 22, background: "#fff",
        border: "1px solid var(--line)", borderRadius: 14,
      }}>
        <h2 style={{ margin: 0, fontSize: 22 }}>Trabalhamos com curadores de espaços</h2>
        <p style={{ marginTop: 10, lineHeight: 1.6, color: "var(--ink)" }}>
          Os nossos parceiros têm acesso a centenas de quintas, terraços,
          jardins, salões e venues urbanos em Portugal. Combinamos o teu
          briefing com a tipologia de evento e devolvemos 2–3 sugestões já
          filtradas — sem comissão para ti.
        </p>
        <p style={{ marginTop: 10, lineHeight: 1.6, color: "var(--ink)" }}>
          Quando indicas que vais ter food trucks connosco, o parceiro já
          sabe os requisitos (energia, sanitação, acesso) e prioriza venues
          compatíveis. Menos viagens, menos surpresas.
        </p>
        <ul style={{ marginTop: 14, paddingLeft: 20, color: "var(--ink)", lineHeight: 1.7 }}>
          <li>Curadoria com base no nº de convidados, data e tipo de evento</li>
          <li>Venues pré-validados para receber food trucks</li>
          <li>Resposta em 24h úteis com 2–3 opções</li>
          <li>Negociação directa com o espaço — sem intermediário extra</li>
        </ul>
      </section>

      <h2 style={{ marginTop: 36, fontSize: 22 }}>Diz-nos o que precisas</h2>
      <PartnerLeadForm
        kind="venues"
        intro="Quanto mais detalhe nos deres, mais afinada será a curadoria."
        fields={fields}
        cta="Ajuda-me a encontrar o espaço"
      />

      <p style={{ marginTop: 28, fontSize: 14 }}>
        <Link href="/" style={{ color: "var(--orange)" }}>← Voltar à página inicial</Link>
      </p>
    </div>
  );
}
