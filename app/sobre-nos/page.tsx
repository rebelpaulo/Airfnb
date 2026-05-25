import Link from "next/link";
import type { Metadata } from "next";
import { getDictionary } from "@/lib/i18n";

// TODO: i18n metadata via generateMetadata
export const metadata: Metadata = {
  title: "Sobre nós",
  description: "A Air F&B liga organizadores a food trucks certificados — curadoria, homologação e pagamento sem complicações.",
  alternates: { canonical: "/sobre-nos" },
};

export default async function SobreNosPage() {
  const dict = await getDictionary();
  const t = dict.about;
  return (
    <div className="container" style={{ paddingTop: 130, paddingBottom: 80, maxWidth: 760 }}>
      <h1 className="section-title">{t.page_title}</h1>
      <p style={{ lineHeight: 1.7, color: "var(--ink)" }}>{t.intro}</p>
      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>{t.what_title}</h2>
      <p style={{ lineHeight: 1.7 }}>{t.what_body}</p>
      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>{t.values_title}</h2>
      <ul style={{ lineHeight: 1.8 }}>
        <li>{t.value1}</li>
        <li>{t.value2}</li>
        <li>{t.value3}</li>
      </ul>
      <p style={{ marginTop: 32 }}>
        <Link href="/" style={{ color: "var(--orange)" }}>{t.back}</Link>
      </p>
    </div>
  );
}
