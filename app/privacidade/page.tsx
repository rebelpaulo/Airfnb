import Link from "next/link";
import type { Metadata } from "next";
import { getDictionary } from "@/lib/i18n";

// TODO: i18n metadata via generateMetadata
export const metadata: Metadata = {
  title: "Política de Privacidade",
  description: "Como a Air F&B trata os teus dados pessoais sob o RGPD.",
  alternates: { canonical: "/privacidade" },
};

export default async function PrivacidadePage() {
  const dict = await getDictionary();
  const t = dict.privacy;
  return (
    <div className="container" style={{ paddingTop: 120, paddingBottom: 80, maxWidth: 780 }}>
      <h1 className="section-title">{t.page_title}</h1>
      <p style={{ color: "var(--muted)", marginTop: -6 }}>{t.last_updated}</p>

      <Section title={t.who_title}>
        {t.who_body_pre}<strong>{t.who_domain}</strong>{t.who_body_mid}
        <a href="mailto:privacidade@airfnb.pt">privacidade@airfnb.pt</a>{t.who_body_post}
      </Section>

      <Section title={t.data_title}>
        <ul>
          <li><strong>{t.data_account_label}</strong>{t.data_account_body}</li>
          <li><strong>{t.data_profile_label}</strong>{t.data_profile_body}</li>
          <li><strong>{t.data_content_label}</strong>{t.data_content_body}</li>
          <li><strong>{t.data_payments_label}</strong>{t.data_payments_body}</li>
          <li><strong>{t.data_tech_label}</strong>{t.data_tech_body}</li>
        </ul>
      </Section>

      <Section title={t.use_title}>
        <ul>
          <li><strong>{t.use_op_label}</strong>{t.use_op_body}</li>
          <li><strong>{t.use_trust_label}</strong>{t.use_trust_body}</li>
          <li><strong>{t.use_sec_label}</strong>{t.use_sec_body}</li>
          <li><strong>{t.use_comm_label}</strong>{t.use_comm_body}</li>
        </ul>
      </Section>

      <Section title={t.legal_title}>
        <ul>
          <li>{t.legal_1}</li>
          <li>{t.legal_2}</li>
          <li>{t.legal_3}</li>
          <li>{t.legal_4}</li>
        </ul>
      </Section>

      <Section title={t.share_title}>
        <ul>
          <li><strong>{t.share_stripe}</strong>{t.share_stripe_body}</li>
          <li><strong>{t.share_supabase}</strong>{t.share_supabase_body}</li>
          <li><strong>{t.share_vercel}</strong>{t.share_vercel_body}</li>
          <li>{t.share_no_sell}</li>
        </ul>
      </Section>

      <Section title={t.retention_title}>
        <ul>
          <li>{t.retention_1}</li>
          <li>{t.retention_2}</li>
          <li>{t.retention_3}</li>
          <li>{t.retention_4}</li>
        </ul>
      </Section>

      <Section title={t.rights_title}>
        <ul>
          <li><strong>{t.rights_access_label}</strong>{t.rights_access_pre}<Link href="/dashboard/conta">{t.rights_access_link}</Link>{t.rights_access_post}</li>
          <li><strong>{t.rights_rect_label}</strong>{t.rights_rect_body}</li>
          <li><strong>{t.rights_del_label}</strong>{t.rights_del_pre}<Link href="/dashboard/conta">{t.rights_del_link}</Link>{t.rights_del_post}</li>
          <li><strong>{t.rights_port_label}</strong>{t.rights_port_body}</li>
          <li><strong>{t.rights_comp_label}</strong>{t.rights_comp_pre}<a href="https://www.cnpd.pt" target="_blank" rel="noopener noreferrer">{t.rights_comp_link}</a>{t.rights_comp_post}</li>
        </ul>
      </Section>

      <Section title={t.cookies_title}>{t.cookies_body}</Section>

      <Section title={t.changes_title}>{t.changes_body}</Section>

      <p style={{ marginTop: 40 }}>
        <Link href="/" style={{ color: "var(--orange)" }}>{t.back}</Link>
        {t.sep}
        <Link href="/termos" style={{ color: "var(--orange)" }}>{t.to_terms}</Link>
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
