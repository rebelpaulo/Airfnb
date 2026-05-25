import Link from "next/link";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer, supabaseAdmin } from "@/lib/supabase/server";
import { getAllSettings, type Setting } from "@/lib/settings";

export const dynamic = "force-dynamic";

const GROUP_LABELS: Record<string, { pt: string; en: string }> = {
  leads:       { pt: "Leads de parceiros",  en: "Partner leads" },
  general:     { pt: "Geral",                en: "General" },
  rate_limits: { pt: "Rate limits",          en: "Rate limits" },
  lock_fee:    { pt: "Lock-fee",             en: "Lock-fee" },
  email:       { pt: "Email",                en: "Email" },
};

export default async function AdminSettingsPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/admin/definicoes");

  // Admin gate — `getAllSettings()` uses the service-role client so we
  // can't lean on RLS to silently filter; instead we re-run the same
  // admin-metrics RPC the other /admin pages use.
  const { data: gate } = await (supa as any).rpc("airfnb_admin_metrics");
  if (!(gate as any[])?.length) redirect("/dashboard/organizer");

  const grouped = await getAllSettings();
  const groups = Object.keys(grouped).sort();

  async function save(formData: FormData) {
    "use server";
    const key = String(formData.get("key") ?? "");
    const value = String(formData.get("value") ?? "");
    if (!key) throw new Error("missing key");

    // Server-side admin re-check before writing.
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error("unauthenticated");
    const { data: gate } = await (supa as any).rpc("airfnb_admin_metrics");
    if (!(gate as any[])?.length) throw new Error("not authorized");

    const admin = supabaseAdmin();
    const { error } = await (admin as any)
      .from("airfnb_platform_settings")
      .update({ value, updated_by: user.id })
      .eq("key", key);
    if (error) throw new Error(error.message);
    revalidatePath("/admin/definicoes");
  }

  return (
    <div className="dash" style={{ maxWidth: 920 }}>
      <nav className="breadcrumb">
        <Link href="/admin">Admin</Link> &nbsp;/&nbsp; <span>Definições</span>
      </nav>
      <h1 style={{ margin: 0 }}>Definições da plataforma</h1>
      <p style={{ color: "var(--muted)", marginTop: 6 }}>
        Valores aqui editados são lidos directamente pela aplicação sem
        deploy. Cada chave tem um fallback em variável de ambiente — útil em
        previews antes de o registo existir.
      </p>

      {groups.length === 0 ? (
        <div className="dash empty" style={{ marginTop: 24 }}>
          Sem definições registadas. Aplica a migration para gerar o seed inicial.
        </div>
      ) : (
        <div style={{ display: "grid", gap: 26, marginTop: 26 }}>
          {groups.map((group) => (
            <section key={group} style={{
              padding: 22, background: "#fff", border: "1px solid var(--line)",
              borderRadius: 14,
            }}>
              <h2 style={{ margin: 0, fontSize: 18, color: "var(--teal)" }}>
                {GROUP_LABELS[group]?.pt ?? group}
              </h2>
              <div style={{ display: "grid", gap: 14, marginTop: 16 }}>
                {grouped[group].map((s) => <SettingRow key={s.key} s={s} save={save} />)}
              </div>
            </section>
          ))}
        </div>
      )}
    </div>
  );
}

function SettingRow({ s, save }: { s: Setting; save: (fd: FormData) => Promise<void> }) {
  const updated = s.updated_at ? new Date(s.updated_at).toLocaleString("pt-PT", { dateStyle: "short", timeStyle: "short" }) : null;
  // Stable input id so the <label htmlFor> + screen readers tie them together.
  const inputId = `setting-${s.key}`;
  return (
    <form action={save} style={{
      display: "grid", gridTemplateColumns: "1fr auto", gap: 12, alignItems: "start",
      padding: 14, background: "#FAFAFA", border: "1px solid var(--line)", borderRadius: 10,
    }}>
      <div style={{ display: "grid", gap: 6 }}>
        <label htmlFor={inputId} style={{ fontSize: 13, fontWeight: 600, fontFamily: "monospace" }}>
          {s.key}
        </label>
        {s.description && (
          <small style={{ color: "var(--muted)", fontSize: 12, lineHeight: 1.5 }}>
            {s.description}
          </small>
        )}
        <input
          id={inputId}
          type={s.secret ? "password" : "text"}
          name="value"
          defaultValue={s.value ?? ""}
          placeholder={s.secret ? "(secret)" : "(vazio — usa fallback do env)"}
          style={{ marginTop: 4, padding: "8px 10px", border: "1px solid var(--line)", borderRadius: 8 }}
        />
        {updated && (
          <small style={{ color: "var(--muted)", fontSize: 11 }}>
            Última atualização: {updated}
          </small>
        )}
      </div>
      <input type="hidden" name="key" value={s.key} />
      <button type="submit" className="btn-pill" style={{ padding: "8px 18px", fontSize: 14, alignSelf: "start" }}>
        Guardar
      </button>
    </form>
  );
}
