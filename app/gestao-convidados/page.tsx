import Link from "next/link";
import type { Metadata } from "next";
import { PartnerLeadForm, type FieldConfig } from "@/components/PartnerLeadForm";
import { getDictionary } from "@/lib/i18n";

// TODO: i18n metadata via generateMetadata
export const metadata: Metadata = {
  title: "Gestão de Convidados, Bilhética & Cashless — Air F&B",
  description:
    "Vendes bilhetes, geres convidados, ou precisas de cashless e POS no teu evento? Em parceria com a 3cket — a plataforma portuguesa que cobre bilhética, listas, fast-track e pagamentos no recinto.",
  alternates: { canonical: "/gestao-convidados" },
};

export default async function GestaoConvidadosPage() {
  const dict = await getDictionary();
  const t = dict.services.guest_mgmt;
  const fields: FieldConfig[] = [
    { type: "text",   name: "event_name",  label: t.f_event_name_label, placeholder: t.f_event_name_placeholder },
    { type: "date",   name: "event_date",  label: t.f_event_date_label, required: true },
    { type: "number", name: "guest_count", label: t.f_guest_count_label, required: true, placeholder: t.f_guest_count_placeholder },
    { type: "text",   name: "venue",       label: t.f_venue_label, placeholder: t.f_venue_placeholder },
    { type: "checkboxes", name: "needs", label: t.f_needs_label, options: [
      { value: "ticketing",    label: t.f_needs_ticketing },
      { value: "guest_list",   label: t.f_needs_guest_list },
      { value: "cashless",     label: t.f_needs_cashless },
      { value: "pos",          label: t.f_needs_pos },
      { value: "fast_track",   label: t.f_needs_fast_track },
      { value: "access_control", label: t.f_needs_access },
    ] },
    { type: "textarea", name: "notes",     label: t.f_notes_label, rows: 3,
      placeholder: t.f_notes_placeholder },
  ];

  return (
    <div className="container" style={{ paddingTop: 130, paddingBottom: 80, maxWidth: 820 }}>
      <h1 className="section-title">{t.page_title}</h1>
      <p style={{ color: "var(--muted)", marginTop: -10, fontSize: 17 }}>
        {t.subtitle_pre}<strong>{t.subtitle_brand}</strong>{t.subtitle_post}
      </p>

      <section style={{
        marginTop: 26, padding: 22, background: "#fff",
        border: "1px solid var(--line)", borderRadius: 14,
      }}>
        <h2 style={{ margin: 0, fontSize: 22 }}>{t.sec_title}</h2>
        <p style={{ marginTop: 10, lineHeight: 1.6, color: "var(--ink)" }}>{t.sec_p1}</p>
        <ul style={{ marginTop: 14, paddingLeft: 20, color: "var(--ink)", lineHeight: 1.7 }}>
          <li><strong>{t.bullet1_label}</strong>{t.bullet1_body}</li>
          <li><strong>{t.bullet2_label}</strong>{t.bullet2_body}</li>
          <li><strong>{t.bullet3_label}</strong>{t.bullet3_body}</li>
          <li><strong>{t.bullet4_label}</strong>{t.bullet4_body}</li>
          <li><strong>{t.bullet5_label}</strong>{t.bullet5_body}</li>
        </ul>
        <p style={{ marginTop: 14, lineHeight: 1.6, color: "var(--ink)" }}>{t.sec_p2}</p>
      </section>

      <h2 style={{ marginTop: 36, fontSize: 22 }}>{t.form_heading}</h2>
      <PartnerLeadForm
        kind="guest_mgmt"
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
