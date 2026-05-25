import Link from "next/link";
import type { Metadata } from "next";
import { getDictionary } from "@/lib/i18n";

// TODO: i18n metadata via generateMetadata
export const metadata: Metadata = {
  title: "Termos e Condições",
  description: "Termos de utilização do marketplace Air F&B.",
  alternates: { canonical: "/termos" },
};

export default async function TermosPage() {
  const dict = await getDictionary();
  const t = dict.terms;
  return (
    <div className="container" style={{ paddingTop: 120, paddingBottom: 80, maxWidth: 780 }}>
      <h1 className="section-title">{t.page_title}</h1>
      <p style={{ color: "var(--muted)", marginTop: -6 }}>{t.last_updated}</p>

      <Section title={t.s1_title}>{t.s1_body}</Section>

      <Section title={t.s2_title}>
        {t.s2_pre}
        <Link href="/privacidade" style={{ color: "var(--orange)" }}>{t.s2_link}</Link>
        {t.s2_post}
      </Section>

      <Section title={t.s3_title}>{t.s3_body}</Section>
      <Section title={t.s4_title}>{t.s4_body}</Section>
      <Section title={t.s5_title}>{t.s5_body}</Section>
      <Section title={t.s6_title}>{t.s6_body}</Section>

      <Section title={t.s7_title}>
        {t.s7_pre}
        <Link href="/dashboard/conta" style={{ color: "var(--orange)" }}>{t.s7_link}</Link>
        {t.s7_post}
      </Section>

      <Section title={t.s8_title}>{t.s8_body}</Section>
      <Section title={t.s9_title}>{t.s9_body}</Section>

      <Section title={t.s10_title}>
        <a href="mailto:legal@airfnb.pt">legal@airfnb.pt</a>
      </Section>

      <p style={{ marginTop: 40 }}>
        <Link href="/" style={{ color: "var(--orange)" }}>{t.back}</Link>
        {t.sep}
        <Link href="/privacidade" style={{ color: "var(--orange)" }}>{t.to_privacy}</Link>
      </p>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section style={{ marginTop: 28 }}>
      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", fontSize: 24, margin: "0 0 8px" }}>
        {title}
      </h2>
      <div style={{ lineHeight: 1.65, color: "var(--ink)" }}>{children}</div>
    </section>
  );
}
