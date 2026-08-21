import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { ensureFbMembership } from "@/lib/auth/fb-membership";
import { AvatarUpload } from "@/components/AvatarUpload";
import { getDictionary } from "@/lib/i18n";

export default async function OnboardingOrganizerPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/onboarding/organizer");

  const dict = await getDictionary();
  const t = dict.onboarding.organizer;

  const { data: profile } = await (supa as any)
    .from("airfnb_profiles")
    .select("full_name, phone, company_name, vat_number, avatar_url, onboarding_completed")
    .eq("id", user.id)
    .maybeSingle();

  if (profile?.onboarding_completed) redirect("/dashboard/organizer");

  async function save(formData: FormData) {
    "use server";
    const dict = await getDictionary();
    const t = dict.onboarding.organizer;
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error(t.err_auth_required);

    const full_name    = String(formData.get("full_name") ?? "").trim() || null;
    const phone        = String(formData.get("phone") ?? "").trim() || null;
    const company_name = String(formData.get("company_name") ?? "").trim() || null;
    const vat_number   = String(formData.get("vat_number") ?? "").trim() || null;
    const marketing    = formData.get("marketing") === "on";

    await ensureFbMembership(supa, { role: "organizer", fullName: full_name, locale: "pt-PT" });

    const { error } = await (supa as any)
      .from("airfnb_profiles")
      .update({
        full_name, phone, company_name, vat_number,
        marketing_opt_in: marketing,
        onboarding_completed: true,
      })
      .eq("id", user.id);
    if (error) throw new Error(error.message);

    revalidatePath("/dashboard/organizer");
    redirect("/dashboard/organizer");
  }

  return (
    <form action={save} className="wizard">
      <div className="steps-pills">
        <span className="on" /><span className="on" /><span className="on" /><span /><span />
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
      <input id="phone" name="phone" type="tel" defaultValue={profile?.phone ?? ""}
             placeholder="+351 9XX XXX XXX" autoComplete="tel" />

      <div style={{ display: "grid", gridTemplateColumns: "2fr 1fr", gap: 14 }}>
        <div>
          <label htmlFor="company_name">{t.company_label}</label>
          <input id="company_name" name="company_name" defaultValue={profile?.company_name ?? ""} />
        </div>
        <div>
          <label htmlFor="vat_number">{t.vat_label}</label>
          <input id="vat_number" name="vat_number" defaultValue={profile?.vat_number ?? ""}
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
        <button className="btn-pill" type="submit">{t.button_finish}</button>
      </div>
    </form>
  );
}
