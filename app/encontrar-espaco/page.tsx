import Link from "next/link";
import type { Metadata } from "next";
import { PartnerLeadForm, type FieldConfig } from "@/components/PartnerLeadForm";
import { getDictionary } from "@/lib/i18n";

// TODO: i18n metadata via generateMetadata
export const metadata: Metadata = {
  title: "Espaços para Eventos — Air F&B",
  description:
    "Estás a planear um evento e precisas do espaço perfeito? Os nossos parceiros conhecem quintas, terraços, jardins e salões em todo o país. Diz-nos o que precisas — voltamos a contactar-te.",
  alternates: { canonical: "/encontrar-espaco" },
};

export default async function EncontrarEspacoPage() {
  const dict = await getDictionary();
  const t = dict.services.venues;
  const fields: FieldConfig[] = [
    { type: "text",   name: "event_type",    label: t.f_event_type_label, required: true, placeholder: t.f_event_type_placeholder },
    { type: "date",   name: "event_date",    label: t.f_event_date_label },
    { type: "number", name: "guest_count",   label: t.f_guest_count_label, required: true, placeholder: t.f_guest_count_placeholder },
    { type: "number", name: "area_sqm",      label: t.f_area_label, placeholder: t.f_area_placeholder },
    { type: "radio",  name: "indoor_outdoor", label: t.f_indoor_label, required: true,
      options: [
        { value: "indoor",  label: t.f_indoor_indoor },
        { value: "outdoor", label: t.f_indoor_outdoor },
        { value: "both",    label: t.f_indoor_both },
      ],
    },
    { type: "text",   name: "city",          label: t.f_city_label, placeholder: t.f_city_placeholder },
    { type: "textarea", name: "notes",       label: t.f_notes_label, rows: 3,
      placeholder: t.f_notes_placeholder },
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
          <li>{t.bullet1}</li>
          <li>{t.bullet2}</li>
          <li>{t.bullet3}</li>
          <li>{t.bullet4}</li>
        </ul>
      </section>

      <h2 style={{ marginTop: 36, fontSize: 22 }}>{t.form_heading}</h2>
      <PartnerLeadForm
        kind="venues"
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
