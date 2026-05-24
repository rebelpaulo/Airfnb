import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { AvatarUpload } from "@/components/AvatarUpload";

export default async function OnboardingOrganizerPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/onboarding/organizer");

  const { data: profile } = await (supa as any)
    .from("airfnb_profiles")
    .select("full_name, phone, company_name, vat_number, avatar_url, onboarding_completed")
    .eq("id", user.id)
    .maybeSingle();

  if (profile?.onboarding_completed) redirect("/dashboard/organizer");

  async function save(formData: FormData) {
    "use server";
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error("auth required");

    const full_name    = String(formData.get("full_name") ?? "").trim() || null;
    const phone        = String(formData.get("phone") ?? "").trim() || null;
    const company_name = String(formData.get("company_name") ?? "").trim() || null;
    const vat_number   = String(formData.get("vat_number") ?? "").trim() || null;
    const marketing    = formData.get("marketing") === "on";

    const { error } = await (supa as any)
      .from("airfnb_profiles")
      .update({
        full_name, phone, company_name, vat_number,
        role: "organizer",
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
      <h1>Bem-vindo 👋</h1>
      <p style={{ color: "var(--muted)", margin: 0 }}>
        Conta-nos um pouco sobre ti para personalizarmos a experiência. Demora 30 segundos.
      </p>

      <div style={{ margin: "26px 0 18px" }}>
        <AvatarUpload userId={user.id} initialUrl={profile?.avatar_url ?? null} />
      </div>

      <label htmlFor="full_name">Nome completo</label>
      <input id="full_name" name="full_name" required defaultValue={profile?.full_name ?? ""} />

      <label htmlFor="phone">Telemóvel</label>
      <input id="phone" name="phone" type="tel" defaultValue={profile?.phone ?? ""}
             placeholder="+351 9XX XXX XXX" autoComplete="tel" />

      <div style={{ display: "grid", gridTemplateColumns: "2fr 1fr", gap: 14 }}>
        <div>
          <label htmlFor="company_name">Empresa (opcional)</label>
          <input id="company_name" name="company_name" defaultValue={profile?.company_name ?? ""} />
        </div>
        <div>
          <label htmlFor="vat_number">NIF (opcional)</label>
          <input id="vat_number" name="vat_number" defaultValue={profile?.vat_number ?? ""}
                 inputMode="numeric" pattern="[0-9]{9}" />
        </div>
      </div>

      <label style={{ display: "flex", alignItems: "center", gap: 10, marginTop: 18, fontSize: 14 }}>
        {/* opt-in only — leave unchecked by default per GDPR consent rules */}
        <input type="checkbox" name="marketing" />
        Quero receber novidades e dicas para organizar eventos.
      </label>

      <div className="actions">
        <span />
        <button className="btn-pill" type="submit">Concluir</button>
      </div>
    </form>
  );
}
