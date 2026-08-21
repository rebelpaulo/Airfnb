// Gateway page for the truck-owner registration funnel.
// Routes the user through the right step depending on their state:
//   - not logged in → /signup?as=truck
//   - logged in, role = 'organizer' → block with WrongAccountType (roles are exclusive)
//   - logged in, role = 'owner', onboarding incomplete → /onboarding/truck
//   - logged in, role = 'owner', no trucks → /dashboard/truck/novo
//   - logged in, role = 'owner', has trucks → /dashboard/truck
//   - logged in, role = null → /onboarding/truck (first-time choice → owner)
import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { WrongAccountType } from "@/components/WrongAccountType";

// TODO(i18n): metadata is rendered before locale resolution; kept in PT for now.
// Migrate to generateMetadata async + getDictionary() once we accept the
// extra dynamic render.
export const metadata: Metadata = {
  title: "Registar fornecedor para eventos",
  description:
    "Regista o teu serviço de Food Truck, Catering ou Bar, apresenta-o a organizadores e começa a receber pedidos de eventos.",
  alternates: { canonical: "/registar" },
};

export const dynamic = "force-dynamic";

export default async function RegistarPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) {
    redirect("/signup?as=truck&next=/registar");
  }

  const { data: profile } = await (supa as any)
    .from("airfnb_profiles")
    .select("role, onboarding_completed")
    .eq("id", user.id)
    .maybeSingle();

  // Roles are exclusive — an organizer account can't pivot into a truck
  // operator. They have to use a different email. Block here instead of
  // silently flipping the role in /onboarding/truck.
  if (profile?.role === "organizer") {
    return <WrongAccountType intent="add_truck" currentRole="organizer" />;
  }

  // No profile / no role yet, or onboarding incomplete → run the wizard
  if (!profile || profile.role !== "owner" || !profile.onboarding_completed) {
    redirect("/onboarding/truck");
  }

  // Already an owner — check if they have any trucks yet
  const { data: services } = await (supa as any)
    .rpc("airfnb_supplier_services", { p_truck: null })
    .limit(1);

  redirect((services?.length ?? 0) > 0 ? "/dashboard/truck" : "/dashboard/truck/novo");
}
