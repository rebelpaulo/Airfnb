import Link from "next/link";
import type { Metadata } from "next";
import { getDictionary } from "@/lib/i18n";
import { getPublicContactEmail } from "@/lib/public-contact";

// TODO: i18n metadata via generateMetadata
export const metadata: Metadata = {
  title: "Ajuda",
  description:
    "Tira dúvidas sobre publicar eventos, registar fornecedores ou receber propostas — a equipa F&B Tailor responde em horas úteis.",
  alternates: { canonical: "/ajuda" },
};

export default async function AjudaPage() {
  const dict = await getDictionary();
  const t = dict.help;
  const supportEmail = getPublicContactEmail("support");
  return (
    <div className="container" style={{ paddingTop: 130, paddingBottom: 80, maxWidth: 760 }}>
      <h1 className="section-title">{t.page_title}</h1>
      <p style={{ color: "var(--muted)", marginTop: -10 }}>{t.subtitle}</p>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 28 }}>{t.org_title}</h2>
      <ul style={{ lineHeight: 1.8 }}>
        <li>
          {t.org_item1_pre}
          <Link href="/publicar" style={{ color: "var(--orange)" }}>{t.org_item1_link}</Link>
          {t.org_item1_post}
        </li>
        <li>
          {t.org_item2_pre}
          <Link href="/dashboard/organizer" style={{ color: "var(--orange)" }}>{t.org_item2_link}</Link>
          {t.org_item2_post}
        </li>
        <li>{t.org_item3}</li>
      </ul>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 28 }}>{t.truck_title}</h2>
      <ul style={{ lineHeight: 1.8 }}>
        <li>
          {t.truck_item1_pre}
          <Link href="/registar" style={{ color: "var(--orange)" }}>{t.truck_item1_link}</Link>
          {t.truck_item1_post}
        </li>
        <li>{t.truck_item2}</li>
        <li>{t.truck_item3}</li>
      </ul>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 28 }}>{t.team_title}</h2>
      <p style={{ lineHeight: 1.7 }}>
        {supportEmail ? (
          <>
            {t.team_email_label}{" "}
            <a href={`mailto:${supportEmail}`} style={{ color: "var(--orange)" }}>{supportEmail}</a>
            <br />
          </>
        ) : null}
        {t.team_whatsapp_label}
      </p>

      <p style={{ marginTop: 32 }}>
        <Link href="/" style={{ color: "var(--orange)" }}>{t.back}</Link>
      </p>
    </div>
  );
}
