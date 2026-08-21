import Link from "next/link";
import type { Metadata } from "next";
import { getDictionary } from "@/lib/i18n";
import { getPublicContactEmail } from "@/lib/public-contact";

// TODO: i18n metadata via generateMetadata
export const metadata: Metadata = {
  title: "Equipa",
  description:
    "Conhece a equipa F&B Tailor — baseada em Lisboa e com experiência em marketplaces, eventos e restauração.",
  alternates: { canonical: "/equipa" },
};

export default async function EquipaPage() {
  const dict = await getDictionary();
  const t = dict.team;
  const partnershipEmail = getPublicContactEmail("partnerships");
  return (
    <div className="container" style={{ paddingTop: 130, paddingBottom: 80, maxWidth: 760 }}>
      <h1 className="section-title">{t.page_title}</h1>
      <p style={{ color: "var(--muted)", marginTop: -10 }}>{t.subtitle}</p>
      <p style={{ lineHeight: 1.7, marginTop: 24 }}>
        {t.body_pre}
        <Link href="/ajuda" style={{ color: "var(--orange)" }}>{t.body_link_help}</Link>
        {partnershipEmail ? (
          <>
            {t.body_mid}
            <a href={`mailto:${partnershipEmail}`} style={{ color: "var(--orange)" }}>{partnershipEmail}</a>
            {t.body_post}
          </>
        ) : "."}
      </p>
      <p style={{ marginTop: 32 }}>
        <Link href="/" style={{ color: "var(--orange)" }}>{t.back}</Link>
      </p>
    </div>
  );
}
