import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { getDictionary } from "@/lib/i18n";
import { AvatarUpload } from "@/components/AvatarUpload";
import { ProfileTabs } from "./ProfileTabs";

export const dynamic = "force-dynamic";

/**
 * User-level profile editor. Tabbed: personal data vs billing data.
 * Each tab is its own <form> with its own server action so saving one
 * doesn't touch the other slice.
 *
 * `?ok=personal` or `?ok=billing` controls both the success banner and
 * which tab opens (so the user lands on the one they just saved).
 */
export default async function ProfilePage({ searchParams }: {
  searchParams: Promise<{ ok?: string }>;
}) {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/perfil");

  const dict = await getDictionary();
  const t = dict.dashboard_profile;
  const { ok } = await searchParams;
  const showSaved = ok === "personal" || ok === "billing";
  const initialTab: "personal" | "billing" = ok === "billing" ? "billing" : "personal";

  const { data: profile } = await (supa as any)
    .from("airfnb_profiles")
    .select("full_name, display_name, phone, address_line, company_name, vat_number, billing_address_line, avatar_url, marketing_opt_in, role")
    .eq("id", user.id)
    .maybeSingle();

  async function savePersonal(formData: FormData) {
    "use server";
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error("auth required");
    const dict = await getDictionary();
    const tt = dict.dashboard_profile;

    const full_name    = String(formData.get("full_name") ?? "").trim();
    const display_name = String(formData.get("display_name") ?? "").trim() || null;
    const phone        = String(formData.get("phone") ?? "").trim() || null;
    const address_line = String(formData.get("address_line") ?? "").trim() || null;
    const marketing    = formData.get("marketing") === "on";

    if (!full_name) throw new Error(tt.err_full_name);

    const { error } = await (supa as any)
      .from("airfnb_profiles")
      .update({ full_name, display_name, phone, address_line, marketing_opt_in: marketing })
      .eq("id", user.id);
    if (error) throw new Error(error.message);
    revalidatePath("/dashboard/perfil");
    redirect("/dashboard/perfil?ok=personal");
  }

  async function saveBilling(formData: FormData) {
    "use server";
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error("auth required");
    const dict = await getDictionary();
    const tt = dict.dashboard_profile;

    const company_name         = String(formData.get("company_name") ?? "").trim() || null;
    const vat_number_raw       = String(formData.get("vat_number") ?? "").trim();
    const billing_address_line = String(formData.get("billing_address_line") ?? "").trim() || null;

    if (vat_number_raw && !/^[0-9]{9}$/.test(vat_number_raw)) {
      throw new Error(tt.err_vat_format);
    }
    const vat_number = vat_number_raw || null;

    const { error } = await (supa as any)
      .from("airfnb_profiles")
      .update({ company_name, vat_number, billing_address_line })
      .eq("id", user.id);
    if (error) throw new Error(error.message);
    revalidatePath("/dashboard/perfil");
    redirect("/dashboard/perfil?ok=billing");
  }

  const personalForm = (
    <section style={{
      marginTop: 0, padding: 24, background: "#fff",
      border: "1px solid var(--line)", borderTopLeftRadius: 0, borderTopRightRadius: 14,
      borderBottomLeftRadius: 14, borderBottomRightRadius: 14,
    }}>
      <div style={{ marginBottom: 18 }}>
        <AvatarUpload userId={user.id} initialUrl={profile?.avatar_url ?? null} />
      </div>

      <form action={savePersonal} className="wizard" style={{ display: "grid", gap: 14 }}>
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
        <div>
          <label htmlFor="address_line">{t.field_address}</label>
          <input id="address_line" name="address_line" defaultValue={profile?.address_line ?? ""}
                 autoComplete="street-address" />
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
  );

  const billingForm = (
    <section style={{
      marginTop: 0, padding: 24, background: "#fff",
      border: "1px solid var(--line)", borderTopLeftRadius: 0, borderTopRightRadius: 14,
      borderBottomLeftRadius: 14, borderBottomRightRadius: 14,
    }}>
      <form action={saveBilling} className="wizard" style={{ display: "grid", gap: 14 }}>
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
        <div>
          <label htmlFor="billing_address_line">{t.field_billing_address}</label>
          <input id="billing_address_line" name="billing_address_line"
                 defaultValue={profile?.billing_address_line ?? ""} />
        </div>
        <div style={{ display: "flex", justifyContent: "flex-end", marginTop: 14 }}>
          <button type="submit" className="btn-pill">{t.save_button}</button>
        </div>
      </form>
    </section>
  );

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

      <ProfileTabs personal={personalForm} billing={billingForm} initial={initialTab} />
    </div>
  );
}
