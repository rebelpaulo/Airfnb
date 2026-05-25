import Link from "next/link";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { DeleteAccountButton } from "./DeleteAccountButton";

export const dynamic = "force-dynamic";

/**
 * Account management hub — the GDPR control panel.
 * Lets the user export everything we hold on them (JSON via /api/me/export)
 * and trigger a self-destruct that cascades through the profile row.
 */
export default async function ContaPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/conta");

  const { data: profile } = await (supa as any)
    .from("airfnb_profiles")
    .select("display_name, role, created_at")
    .eq("id", user.id)
    .maybeSingle();

  return (
    <div className="dash" style={{ maxWidth: 720 }}>
      <h1 style={{ margin: 0 }}>A minha conta</h1>
      <p style={{ color: "var(--muted)", marginTop: 6 }}>
        Gerir os teus dados pessoais ao abrigo do RGPD.
      </p>

      <section style={{ marginTop: 24, padding: 22, background: "#fff", border: "1px solid var(--line)", borderRadius: 14 }}>
        <h2 style={{ margin: 0, fontSize: 18 }}>Identificação</h2>
        <dl style={{ marginTop: 14, display: "grid", gridTemplateColumns: "140px 1fr", rowGap: 8, fontSize: 14 }}>
          <dt style={{ color: "var(--muted)" }}>Email</dt>           <dd style={{ margin: 0 }}>{user.email}</dd>
          <dt style={{ color: "var(--muted)" }}>Nome</dt>            <dd style={{ margin: 0 }}>{profile?.display_name ?? "—"}</dd>
          <dt style={{ color: "var(--muted)" }}>Papel</dt>           <dd style={{ margin: 0 }}>{profile?.role ?? "—"}</dd>
          <dt style={{ color: "var(--muted)" }}>Conta criada</dt>    <dd style={{ margin: 0 }}>{profile?.created_at ? new Date(profile.created_at).toLocaleDateString("pt-PT") : "—"}</dd>
        </dl>
      </section>

      <section style={{ marginTop: 18, padding: 22, background: "#fff", border: "1px solid var(--line)", borderRadius: 14 }}>
        <h2 style={{ margin: 0, fontSize: 18 }}>Exportar os meus dados</h2>
        <p style={{ marginTop: 8, fontSize: 14, lineHeight: 1.5, color: "var(--muted)" }}>
          Descarrega um ficheiro JSON com tudo o que guardamos sobre ti (perfil, trucks,
          pedidos, candidaturas, mensagens, avaliações, notificações, lock-fees).
          Direito de portabilidade — Art. 20 RGPD.
        </p>
        <a href="/api/me/export"
           className="btn-pill outline"
           style={{ marginTop: 10, padding: "10px 22px", borderColor: "var(--teal)", color: "var(--teal)", display: "inline-flex", alignItems: "center", gap: 6 }}>
          <span className="material-symbols-outlined" style={{ fontSize: 18 }}>download</span>
          Descarregar JSON
        </a>
      </section>

      <section style={{ marginTop: 18, padding: 22, background: "#FFF6F2", border: "1px solid #FFB89A", borderRadius: 14 }}>
        <h2 style={{ margin: 0, fontSize: 18, color: "var(--orange-deep)" }}>Apagar a minha conta</h2>
        <p style={{ marginTop: 8, fontSize: 14, lineHeight: 1.5, color: "var(--ink)" }}>
          Esta acção apaga o teu perfil, trucks, candidaturas, mensagens e notificações.
          Não é reversível. Registos de faturação ficam retidos por obrigação fiscal (10 anos).
        </p>
        <DeleteAccountButton />
      </section>

      <p style={{ marginTop: 24, fontSize: 13, color: "var(--muted)" }}>
        Vê também a <Link href="/privacidade" style={{ color: "var(--teal)" }}>Política de Privacidade</Link>.
      </p>
    </div>
  );
}
