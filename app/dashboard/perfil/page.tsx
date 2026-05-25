import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { getDictionary } from "@/lib/i18n";
import { AvatarUpload } from "@/components/AvatarUpload";

export const dynamic = "force-dynamic";

/**
 * User-level profile editor (distinct from /dashboard/truck/perfil which
 * edits a truck row). Lets the user update name, phone, company, VAT,
 * avatar and the marketing-opt-in flag without re-running the onboarding
 * wizard.
 *
 * Form fields mirror the onboarding wizards so we don't drift in
 * validation rules.
 */
export default async function ProfilePage({ searchParams }: {
  searchParams: Promise<{ ok?: string }>;
}) {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/perfil");

  const dict = await getDictionary();
  const t = dict.dashboard_profile;
  // Only the literal "1" flips the banner — any other value (or absence)
  // hides it. Stops a stray ?ok=anything from showing a false confirmation.
  const { ok } = await searchParams;
  const showSaved = ok === "1";

  const { data: profile } = await (supa as any)
    .from("airfnb_profiles")
    .select("full_name, display_name, phone, company_name, vat_number, avatar_url, marketing_opt_in, role")
    .eq("id", user.id)
    .maybeSingle();

  async function save(formData: FormData) {
    "use server";
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error("auth required");

    const dict = await getDictionary();
    const tt = dict.dashboard_profile;

    const full_name    = String(formData.get("full_name") ?? "").trim();
    const display_name = String(formData.get("display_name") ?? "").trim() || null;
    const phone        = String(formData.get("phone") ?? "").trim() || null;
    const company_name = String(formData.get("company_name") ?? "").trim() || null;
    const vat_number_raw = String(formData.get("vat_number") ?? "").trim();
    const marketing    = formData.get("marketing") === "on";

    if (!full_name) throw new Error(tt.err_full_name);
    // VAT is optional; only validate when present.
    if (vat_number_raw && !/^[0-9]{9}$/.test(vat_number_raw)) {
      throw new Error(tt.err_vat_format);
    }
    const vat_number = vat_number_raw || null;

    const { error } = await (supa as any)
      .from("airfnb_profiles")
      .update({
        full_name, display_name, phone,
        company_name, vat_number,
        marketing_opt_in: marketing,
      })
      .eq("id", user.id);
    if (error) throw new Error(error.message);

    revalidatePath("/dashboard/perfil");
    redirect("/dashboard/perfil?ok=1");
  }

  return (
    <div className="dash" style={{ maxWidth: 760, padding: "32px 28px" }}>
      <h1 style={{ margin: 0 }}>{t.page_title}</h1>
      <p style={{ color: "var(--muted)", marginTop: 6 }}>{t.subtitle}</p>

      {showSaved && (
        <div style={{
          marginTop: 20, padding: 12,
          background: "var(--success-bg)", color: "var(--success-text)",
          border: "1px solid var(--success-line)", borderRadius: "var(--radius-sm)",
          fontSize: 14,
        }}>
          {t.saved_ok}
        </div>
      )}

      <section style={{
        marginTop: 22, padding: 24, background: "#fff",
        border: "1px solid var(--line)", borderRadius: 14,
      }}>
        <h2 style={{ margin: 0, fontSize: 18 }}>{t.section_personal}</h2>

        <div style={{ marginTop: 18 }}>
          <AvatarUpload userId={user.id} initialUrl={profile?.avatar_url ?? null} />
        </div>

        <form action={save} className="wizard" style={{ marginTop: 18, display: "grid", gap: 14 }}>
          <div>
            <label htmlFor="full_name">{t.field_full_name}</label>
            <input id="full_name" name="full_name" required defaultValue={profile?.full_name ?? ""} />
          </div>

          <div>
            <label htmlFor="display_name">{t.field_display_name}</label>
            <input id="display_name" name="display_name" defaultValue={profile?.display_name ?? ""} />
          </div>

          <div>
            <label htmlFor="phone">{t.field_phone}</label>
            <input id="phone" name="phone" type="tel" defaultValue={profile?.phone ?? ""}
                   placeholder="+351 9XX XXX XXX" autoComplete="tel" />
          </div>

          <h2 style={{ margin: "10px 0 0", fontSize: 18 }}>{t.section_billing}</h2>

          <div style={{ display: "grid", gridTemplateColumns: "2fr 1fr", gap: 14 }}>
            <div>
              <label htmlFor="company_name">{t.field_company}</label>
              <input id="company_name" name="company_name" defaultValue={profile?.company_name ?? ""} />
            </div>
            <div>
              <label htmlFor="vat_number">{t.field_vat}</label>
              <input id="vat_number" name="vat_number" defaultValue={profile?.vat_number ?? ""}
                     inputMode="numeric" pattern="[0-9]{9}" />
            </div>
          </div>

          <label style={{ display: "flex", alignItems: "center", gap: 10, marginTop: 8, fontSize: 14 }}>
            <input type="checkbox" name="marketing" defaultChecked={!!profile?.marketing_opt_in} />
            {t.field_marketing}
          </label>

          <div style={{ display: "flex", justifyContent: "flex-end", marginTop: 14 }}>
            <button type="submit" className="btn-pill">{t.save_button}</button>
          </div>
        </form>
      </section>
    </div>
  );
}
