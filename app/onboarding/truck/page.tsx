import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { ensureFbMembership } from "@/lib/auth/fb-membership";
import { AvatarUpload } from "@/components/AvatarUpload";
import { WrongAccountType } from "@/components/WrongAccountType";
import { getDictionary } from "@/lib/i18n";

export default async function OnboardingTruckPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/onboarding/truck");

  const dict = await getDictionary();
  const t = dict.onboarding.truck;

  const { data: profile } = await (supa as any)
    .from("airfnb_profiles")
    .select("full_name, phone, company_name, vat_number, avatar_url, role, onboarding_completed")
    .eq("id", user.id)
    .maybeSingle();

  // Roles are exclusive — block organizers before the wizard silently flips
  // them to "owner". They have to create a separate account.
  if (profile?.role === "organizer") {
    return <WrongAccountType intent="add_truck" currentRole="organizer" />;
  }

  if (profile?.onboarding_completed) {
    // already onboarded; skip wizard but make sure they have a truck row
    const { data: existing } = await (supa as any)
      .rpc("airfnb_supplier_services", { p_truck: null })
      .limit(1)
      .maybeSingle();
    redirect(existing ? "/dashboard/truck" : "/dashboard/truck/novo");
  }

  async function save(formData: FormData) {
    "use server";
    // Re-resolve the dictionary inside the action — the closure captures
    // values at render time, but server actions run as a separate request
    // where we want the current locale anyway.
    const dict = await getDictionary();
    const t = dict.onboarding.truck;
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error(t.err_auth_required);

    const full_name    = String(formData.get("full_name") ?? "").trim();
    const phone        = String(formData.get("phone") ?? "").trim();
    const company_name = String(formData.get("company_name") ?? "").trim();
    const vat_number   = String(formData.get("vat_number") ?? "").trim();
    const marketing    = formData.get("marketing") === "on";

    // Server-side validation — never trust the browser's `required` attribute.
    if (!full_name)    throw new Error(t.err_full_name);
    if (!phone)        throw new Error(t.err_phone);
    if (!company_name) throw new Error(t.err_company);
    if (!/^[0-9]{9}$/.test(vat_number)) {
      throw new Error(t.err_vat);
    }

    await ensureFbMembership(supa, { role: "owner", fullName: full_name, locale: "pt-PT" });

    const { error: profErr } = await (supa as any)
      .from("airfnb_profiles")
      .update({
        full_name, phone,
        company_name,
        vat_number,
        marketing_opt_in: marketing,
        onboarding_completed: true,
      })
      .eq("id", user.id);
    if (profErr) throw new Error(profErr.message);

    revalidatePath("/dashboard/truck");
    redirect("/dashboard/truck/novo");
  }

  return (
    <form action={save} className="wizard">
      <div className="steps-pills">
        <span className="on" /><span className="on" /><span /><span /><span />
      </div>
      <h1>{t.page_title}</h1>
      <p style={{ color: "var(--muted)", margin: 0 }}>
        {t.intro}
      </p>

      <div style={{ margin: "26px 0 18px" }}>
        <AvatarUpload userId={user.id} initialUrl={profile?.avatar_url ?? null} />
      </div>

      <label htmlFor="full_name">{t.full_name_label}</label>
      <input id="full_name" name="full_name" required defaultValue={profile?.full_name ?? ""} />

      <label htmlFor="phone">{t.phone_label}</label>
      <input id="phone" name="phone" type="tel" required defaultValue={profile?.phone ?? ""}
             placeholder="+351 9XX XXX XXX" autoComplete="tel" />
      <small style={{ color: "var(--muted)" }}>{t.phone_hint}</small>

      <div style={{ display: "grid", gridTemplateColumns: "2fr 1fr", gap: 14 }}>
        <div>
          <label htmlFor="company_name">{t.company_label}</label>
          <input id="company_name" name="company_name" required defaultValue={profile?.company_name ?? ""} />
        </div>
        <div>
          <label htmlFor="vat_number">{t.vat_label}</label>
          <input id="vat_number" name="vat_number" required defaultValue={profile?.vat_number ?? ""}
                 inputMode="numeric" pattern="[0-9]{9}" />
        </div>
      </div>

      <label style={{ display: "flex", alignItems: "center", gap: 10, marginTop: 18, fontSize: 14 }}>
        {/* opt-in only — leave unchecked by default per GDPR consent rules */}
        <input type="checkbox" name="marketing" />
        {t.marketing_label}
      </label>

      <div className="actions">
        <span />
        <button className="btn-pill" type="submit">{t.button_next}</button>
      </div>
    </form>
  );
}
