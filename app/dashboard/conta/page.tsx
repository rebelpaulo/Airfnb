import Link from "next/link";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { DeleteAccountButton } from "./DeleteAccountButton";
import { getDictionary, getLocale } from "@/lib/i18n";

export const dynamic = "force-dynamic";

/**
 * Account management hub — the GDPR control panel.
 * Lets the user export everything we hold on them (JSON via /api/me/export)
 * and delete or anonymize their F&B membership data without deleting the
 * shared Tailor Auth identity used outside this product.
 */
export default async function ContaPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/conta");

  const dict = await getDictionary();
  const t = dict.dashboard.shared_account;
  const locale = await getLocale();
  const dateLocale = locale === "en" ? "en-US" : "pt-PT";

  const { data: profile } = await (supa as any)
    .from("airfnb_profiles")
    .select("display_name, role, created_at")
    .eq("id", user.id)
    .maybeSingle();

  return (
    <div className="dash" style={{ maxWidth: 720 }}>
      <h1 style={{ margin: 0 }}>{t.title}</h1>
      <p style={{ color: "var(--muted)", marginTop: 6 }}>
        {t.subtitle}
      </p>

      <section style={{ marginTop: 24, padding: 22, background: "#fff", border: "1px solid var(--line)", borderRadius: 14 }}>
        <h2 style={{ margin: 0, fontSize: 18 }}>{t.identification_title}</h2>
        <dl style={{ marginTop: 14, display: "grid", gridTemplateColumns: "140px 1fr", rowGap: 8, fontSize: 14 }}>
          <dt style={{ color: "var(--muted)" }}>{t.label_email}</dt>           <dd style={{ margin: 0 }}>{user.email}</dd>
          <dt style={{ color: "var(--muted)" }}>{t.label_name}</dt>            <dd style={{ margin: 0 }}>{profile?.display_name ?? "—"}</dd>
          <dt style={{ color: "var(--muted)" }}>{t.label_role}</dt>            <dd style={{ margin: 0 }}>{profile?.role ?? "—"}</dd>
          <dt style={{ color: "var(--muted)" }}>{t.label_created}</dt>         <dd style={{ margin: 0 }}>{profile?.created_at ? new Date(profile.created_at).toLocaleDateString(dateLocale) : "—"}</dd>
        </dl>
      </section>

      <section style={{ marginTop: 18, padding: 22, background: "#fff", border: "1px solid var(--line)", borderRadius: 14 }}>
        <h2 style={{ margin: 0, fontSize: 18 }}>{t.export_title}</h2>
        <p style={{ marginTop: 8, fontSize: 14, lineHeight: 1.5, color: "var(--muted)" }}>
          {t.export_body}
        </p>
        <a href="/api/me/export"
           className="btn-pill outline"
           style={{ marginTop: 10, padding: "10px 22px", borderColor: "var(--teal)", color: "var(--teal)", display: "inline-flex", alignItems: "center", gap: 6 }}>
          <span className="material-symbols-outlined" style={{ fontSize: 18 }}>download</span>
          {t.export_cta}
        </a>
      </section>

      <section style={{ marginTop: 18, padding: 22, background: "#FFF6F2", border: "1px solid #FFB89A", borderRadius: 14 }}>
        <h2 style={{ margin: 0, fontSize: 18, color: "var(--orange-deep)" }}>{t.delete_title}</h2>
        <p style={{ marginTop: 8, fontSize: 14, lineHeight: 1.5, color: "var(--ink)" }}>
          {t.delete_body}
        </p>
        <p style={{ marginTop: 8, fontSize: 14, lineHeight: 1.5, color: "var(--ink)", fontWeight: 600 }}>
          {t.delete_auth_body}
        </p>
        <p style={{ marginTop: 8, fontSize: 13, lineHeight: 1.5, color: "var(--muted)" }}>
          {t.delete_tombstone_body}
        </p>
        <DeleteAccountButton />
      </section>

      <p style={{ marginTop: 24, fontSize: 13, color: "var(--muted)" }}>
        {t.privacy_link_pre}<Link href="/privacidade" style={{ color: "var(--teal)" }}>{t.privacy_link_text}</Link>{t.privacy_link_post}
      </p>
    </div>
  );
}
