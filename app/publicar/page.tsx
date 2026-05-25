import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { OrganizerWizard } from "./OrganizerWizard";
import { WrongAccountType } from "@/components/WrongAccountType";

export const dynamic = "force-dynamic";

export default async function PublicarPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/publicar&as=organizer");

  const { data: profile } = await (supa as any)
    .from("airfnb_profiles")
    .select("display_name, email, phone, role")
    .eq("id", user.id)
    .maybeSingle();

  // Roles are exclusive — a truck owner can't pivot into organizing events.
  // They have to use a different email.
  if (profile?.role === "owner") {
    return <WrongAccountType intent="organize_event" currentRole="owner" />;
  }

  const { data: categoriesData } = await (supa as any)
    .from("airfnb_categories")
    .select("id, slug, name_pt, icon")
    .order("name_pt");

  return (
    <div className="dash" style={{ maxWidth: 920 }}>
      <h1 style={{ margin: 0 }}>Organizar Evento</h1>
      <p style={{ color: "var(--muted)", margin: "6px 0 22px" }}>
        5 passos rápidos. A informação que partilhares aqui serve para encontrarmos
        os trucks certos para o teu evento — privada por defeito.
      </p>
      <OrganizerWizard
        userId={user.id}
        defaultName={profile?.display_name ?? ""}
        defaultEmail={profile?.email ?? user.email ?? ""}
        defaultPhone={profile?.phone ?? ""}
        categories={categoriesData ?? []}
      />
    </div>
  );
}
