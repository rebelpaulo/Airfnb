// Gateway page for the truck-owner registration funnel.
// Routes the user through the right step depending on their state:
//   - not logged in → /signup?as=truck
//   - logged in, role != owner → /onboarding/truck (company info + role upgrade)
//   - logged in, role = owner, no trucks → /dashboard/truck/novo (add first truck)
//   - logged in, role = owner, has trucks → /dashboard/truck (manage)
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";

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

  // Need to upgrade to owner + collect company info first
  if (!profile || profile.role !== "owner" || !profile.onboarding_completed) {
    redirect("/onboarding/truck");
  }

  // Already an owner — check if they have any trucks yet
  const { count } = await (supa as any)
    .from("airfnb_trucks")
    .select("id", { count: "exact", head: true })
    .eq("owner_id", user.id);

  redirect((count ?? 0) > 0 ? "/dashboard/truck" : "/dashboard/truck/novo");
}
