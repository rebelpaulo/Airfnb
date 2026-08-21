import Link from "next/link";
import type { Metadata } from "next";
import { PartnerLeadForm, type FieldConfig } from "@/components/PartnerLeadForm";
import { getDictionary } from "@/lib/i18n";

// TODO: i18n metadata via generateMetadata
export const metadata: Metadata = {
  title: "Música & Animação — F&B Tailor",
  description:
    "DJ, banda ao vivo, animação infantil, fotografia ou vídeo? Os nossos parceiros cobrem todas as áreas de entretenimento para eventos. Diz-nos o que precisas — propomos as melhores opções.",
  alternates: { canonical: "/musica-animacao" },
};

export default async function MusicaAnimacaoPage() {
  const dict = await getDictionary();
  const t = dict.services.music;
  const fields: FieldConfig[] = [
    { type: "text",   name: "event_type",  label: t.f_event_type_label, required: true, placeholder: t.f_event_type_placeholder },
    { type: "date",   name: "event_date",  label: t.f_event_date_label, required: true },
    { type: "text",   name: "venue",       label: t.f_venue_label, placeholder: t.f_venue_placeholder },
    { type: "number", name: "guest_count", label: t.f_guest_count_label, placeholder: t.f_guest_count_placeholder },
    { type: "checkboxes", name: "services", label: t.f_services_label, options: [
      { value: "dj",          label: t.f_services_dj },
      { value: "live_band",   label: t.f_services_band },
      { value: "kids",        label: t.f_services_kids },
      { value: "host",        label: t.f_services_host },
      { value: "photo",       label: t.f_services_photo },
      { value: "video",       label: t.f_services_video },
      { value: "lighting",    label: t.f_services_lighting },
      { value: "sound",       label: t.f_services_sound },
    ] },
    { type: "select", name: "duration", label: t.f_duration_label, options: [
      { value: "2-3h",  label: t.f_duration_2_3 },
      { value: "4-6h",  label: t.f_duration_4_6 },
      { value: "6-10h", label: t.f_duration_6_10 },
      { value: "10h+",  label: t.f_duration_10_plus },
    ] },
    { type: "textarea", name: "vibe", label: t.f_vibe_label, rows: 3,
      placeholder: t.f_vibe_placeholder },
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
        kind="music"
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
