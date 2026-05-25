import Link from "next/link";
import type { Metadata } from "next";
import { PartnerLeadForm, type FieldConfig } from "@/components/PartnerLeadForm";
import { getDictionary } from "@/lib/i18n";

// TODO: i18n metadata via generateMetadata
export const metadata: Metadata = {
  title: "Marketing & Publicidade para Eventos — Air F&B",
  description:
    "Convites, sinalética, redes sociais, QR codes no recinto, relatórios pós-evento. Em parceria com agências e estúdios que conhecem o mercado de eventos.",
  alternates: { canonical: "/marketing" },
};

export default async function MarketingPage() {
  const dict = await getDictionary();
  const t = dict.services.marketing;
  const fields: FieldConfig[] = [
    { type: "text",   name: "event_name", label: t.f_event_name_label, required: true, placeholder: t.f_event_name_placeholder },
    { type: "date",   name: "event_date", label: t.f_event_date_label, required: true },
    { type: "number", name: "guest_count", label: t.f_audience_label, placeholder: t.f_audience_placeholder },
    { type: "checkboxes", name: "phase", label: t.f_phase_label, options: [
      { value: "before", label: t.f_phase_before },
      { value: "during", label: t.f_phase_during },
      { value: "after",  label: t.f_phase_after },
    ] },
    { type: "checkboxes", name: "channels", label: t.f_channels_label, options: [
      { value: "instagram", label: t.f_channels_instagram },
      { value: "facebook",  label: t.f_channels_facebook },
      { value: "linkedin",  label: t.f_channels_linkedin },
      { value: "tiktok",    label: t.f_channels_tiktok },
      { value: "press",     label: t.f_channels_press },
      { value: "email",     label: t.f_channels_email },
      { value: "physical",  label: t.f_channels_physical },
    ] },
    { type: "select", name: "budget", label: t.f_budget_label, options: [
      { value: "lt_2k",   label: t.f_budget_lt_2k },
      { value: "2k_5k",   label: t.f_budget_2k_5k },
      { value: "5k_15k",  label: t.f_budget_5k_15k },
      { value: "15k_plus", label: t.f_budget_15k_plus },
      { value: "open",     label: t.f_budget_open },
    ] },
    { type: "textarea", name: "goals", label: t.f_goals_label, rows: 3,
      placeholder: t.f_goals_placeholder },
  ];

  return (
    <div className="container" style={{ paddingTop: 130, paddingBottom: 80, maxWidth: 820 }}>
      <h1 className="section-title">{t.page_title}</h1>
      <p style={{ color: "var(--muted)", marginTop: -10, fontSize: 17 }}>{t.subtitle}</p>

      <section style={{
        marginTop: 26, padding: 22, background: "#fff",
        border: "1px solid var(--line)", borderRadius: 14,
      }}>
        <h2 style={{ margin: 0, fontSize: 22 }}>{t.sec_title}</h2>
        <p style={{ marginTop: 10, lineHeight: 1.6, color: "var(--ink)" }}>{t.sec_p1}</p>
        <p style={{ marginTop: 10, lineHeight: 1.6, color: "var(--ink)" }}>{t.sec_p2}</p>
        <ul style={{ marginTop: 14, paddingLeft: 20, color: "var(--ink)", lineHeight: 1.7 }}>
          <li><strong>{t.bullet1_label}</strong>{t.bullet1_body}</li>
          <li><strong>{t.bullet2_label}</strong>{t.bullet2_body}</li>
          <li><strong>{t.bullet3_label}</strong>{t.bullet3_body}</li>
          <li>{t.bullet4}</li>
        </ul>
      </section>

      <h2 style={{ marginTop: 36, fontSize: 22 }}>{t.form_heading}</h2>
      <PartnerLeadForm
        kind="marketing"
        intro={t.form_intro}
        fields={fields}
        cta={t.form_cta}
      />

      <p style={{ marginTop: 28, fontSize: 14 }}>
        <Link href="/" style={{ color: "var(--orange)" }}>{t.back_home}</Link>
      </p>
    </div>
  );
}
