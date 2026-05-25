import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { OrganizerWizard } from "./OrganizerWizard";
import { WrongAccountType } from "@/components/WrongAccountType";
import { getDictionary } from "@/lib/i18n";

// TODO(i18n): metadata is rendered before locale resolution; kept in PT for now.
// Migrate to generateMetadata async + getDictionary() once we accept the
// extra dynamic render.
export const metadata: Metadata = {
  title: "Publicar pedido",
  description:
    "Publica o teu evento grátis e recebe propostas dos melhores food trucks do país em poucas horas.",
  alternates: { canonical: "/publicar" },
};

export const dynamic = "force-dynamic";

export default async function PublicarPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/publicar&as=organizer");

  const dict = await getDictionary();
  const t = dict.gates.publicar;

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
      <h1 style={{ margin: 0 }}>{t.page_title}</h1>
      <p style={{ color: "var(--muted)", margin: "6px 0 22px" }}>
        {t.intro}
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
