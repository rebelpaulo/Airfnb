import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { AvatarUpload } from "@/components/AvatarUpload";

export default async function OnboardingTruckPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/onboarding/truck");

  const { data: profile } = await (supa as any)
    .from("airfnb_profiles")
    .select("full_name, phone, company_name, vat_number, avatar_url, onboarding_completed")
    .eq("id", user.id)
    .maybeSingle();
  if (profile?.onboarding_completed) {
    // already onboarded; skip wizard but make sure they have a truck row
    const { data: existing } = await (supa as any)
      .from("airfnb_trucks").select("id").eq("owner_id", user.id).maybeSingle();
    redirect(existing ? "/dashboard/truck" : "/dashboard/truck/novo");
  }

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

    const { error: profErr } = await (supa as any)
      .from("airfnb_profiles")
      .update({
        full_name, phone, company_name, vat_number,
        role: "owner",
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
      <h1>Vamos preparar o teu truck 🚚</h1>
      <p style={{ color: "var(--muted)", margin: 0 }}>
        Começa pelos teus dados de contacto. No próximo passo crias o perfil do truck.
      </p>

      <div style={{ margin: "26px 0 18px" }}>
        <AvatarUpload userId={user.id} initialUrl={profile?.avatar_url ?? null} />
      </div>

      <label htmlFor="full_name">Nome do responsável</label>
      <input id="full_name" name="full_name" required defaultValue={profile?.full_name ?? ""} />

      <label htmlFor="phone">Telemóvel</label>
      <input id="phone" name="phone" type="tel" required defaultValue={profile?.phone ?? ""}
             placeholder="+351 9XX XXX XXX" autoComplete="tel" />
      <small style={{ color: "var(--muted)" }}>Os organizers podem precisar de te contactar rapidamente.</small>

      <div style={{ display: "grid", gridTemplateColumns: "2fr 1fr", gap: 14 }}>
        <div>
          <label htmlFor="company_name">Empresa</label>
          <input id="company_name" name="company_name" required defaultValue={profile?.company_name ?? ""} />
        </div>
        <div>
          <label htmlFor="vat_number">NIF</label>
          <input id="vat_number" name="vat_number" required defaultValue={profile?.vat_number ?? ""}
                 inputMode="numeric" pattern="[0-9]{9}" />
        </div>
      </div>

      <label style={{ display: "flex", alignItems: "center", gap: 10, marginTop: 18, fontSize: 14 }}>
        <input type="checkbox" name="marketing" defaultChecked />
        Quero receber alertas de pedidos relevantes para o meu truck.
      </label>

      <div className="actions">
        <span />
        <button className="btn-pill" type="submit">Próximo: criar truck</button>
      </div>
    </form>
  );
}
