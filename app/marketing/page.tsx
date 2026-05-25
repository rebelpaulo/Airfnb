import Link from "next/link";
import type { Metadata } from "next";
import { PartnerLeadForm, type FieldConfig } from "@/components/PartnerLeadForm";

export const metadata: Metadata = {
  title: "Marketing & Publicidade para Eventos — Air F&B",
  description:
    "Convites, sinalética, redes sociais, QR codes no recinto, relatórios pós-evento. Em parceria com agências e estúdios que conhecem o mercado de eventos.",
  alternates: { canonical: "/marketing" },
};

const fields: FieldConfig[] = [
  { type: "text",   name: "event_name", label: "Nome / tema do evento", required: true, placeholder: "Ex.: Open Day Empresa X" },
  { type: "date",   name: "event_date", label: "Data do evento", required: true },
  { type: "number", name: "guest_count", label: "Audiência esperada", placeholder: "Ex.: 500" },
  { type: "checkboxes", name: "phase", label: "Em que fase precisas de ajuda?", options: [
    { value: "before", label: "Antes — convites, save-the-date, campanhas" },
    { value: "during", label: "Durante — sinalética, QR codes, social wall" },
    { value: "after",  label: "Depois — relatório, foto-rescaldo, follow-up" },
  ] },
  { type: "checkboxes", name: "channels", label: "Canais a cobrir", options: [
    { value: "instagram", label: "Instagram" },
    { value: "facebook",  label: "Facebook" },
    { value: "linkedin",  label: "LinkedIn" },
    { value: "tiktok",    label: "TikTok" },
    { value: "press",     label: "Imprensa" },
    { value: "email",     label: "Email marketing" },
    { value: "physical",  label: "Material físico (sinalética, flyers)" },
  ] },
  { type: "select", name: "budget", label: "Orçamento aproximado", options: [
    { value: "lt_2k",   label: "Até €2 000" },
    { value: "2k_5k",   label: "€2 000 – €5 000" },
    { value: "5k_15k",  label: "€5 000 – €15 000" },
    { value: "15k_plus", label: "Acima de €15 000" },
    { value: "open",     label: "Em aberto — proponham" },
  ] },
  { type: "textarea", name: "goals", label: "Objectivos principais", rows: 3,
    placeholder: "Ex.: encher a sala, gerar leads B2B, brand awareness…" },
];

export default function MarketingPage() {
  return (
    <div className="container" style={{ paddingTop: 130, paddingBottom: 80, maxWidth: 820 }}>
      <h1 className="section-title">Marketing &amp; Publicidade</h1>
      <p style={{ color: "var(--muted)", marginTop: -10, fontSize: 17 }}>
        Da convocatória ao relatório pós-evento — os nossos parceiros
        tratam de toda a comunicação para que tu trates da experiência.
      </p>

      <section style={{
        marginTop: 26, padding: 22, background: "#fff",
        border: "1px solid var(--line)", borderRadius: 14,
      }}>
        <h2 style={{ margin: 0, fontSize: 22 }}>Comunicação completa, sem mil agências</h2>
        <p style={{ marginTop: 10, lineHeight: 1.6, color: "var(--ink)" }}>
          Trabalhamos com agências, estúdios criativos e freelancers que
          conhecem o ritmo de eventos. Em vez de coordenares 5 contactos
          diferentes, falamos com um único parceiro que assume tudo: convites
          digitais, anúncios pagos, sinalética no recinto, social wall em
          directo e relatório de impacto.
        </p>
        <p style={{ marginTop: 10, lineHeight: 1.6, color: "var(--ink)" }}>
          Para clientes Air F&amp;B, conseguimos integrar a oferta de food
          (cardápios, fotos dos trucks, copy) nos materiais — economiza
          dias de produção.
        </p>
        <ul style={{ marginTop: 14, paddingLeft: 20, color: "var(--ink)", lineHeight: 1.7 }}>
          <li><strong>Antes</strong> — save-the-date, landing pages, campanhas pagas, imprensa</li>
          <li><strong>Durante</strong> — sinalética, QR codes, social wall, fotografia ao vivo</li>
          <li><strong>Depois</strong> — relatório de impacto, foto-rescaldo, follow-up por email</li>
          <li>Briefing único, proposta consolidada</li>
        </ul>
      </section>

      <h2 style={{ marginTop: 36, fontSize: 22 }}>Conta-nos o que precisas comunicar</h2>
      <PartnerLeadForm
        kind="marketing"
        intro="Quanto mais objectivo dado, mais accionável a proposta."
        fields={fields}
        cta="Quero proposta de comunicação"
      />

      <p style={{ marginTop: 28, fontSize: 14 }}>
        <Link href="/" style={{ color: "var(--orange)" }}>← Voltar à página inicial</Link>
      </p>
    </div>
  );
}
