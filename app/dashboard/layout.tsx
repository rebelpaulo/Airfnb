import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { getDictionary } from "@/lib/i18n";
import { DashboardSidebar, type DashboardRole } from "@/components/DashboardSidebar";

export const dynamic = "force-dynamic";

function toDashboardRole(role: unknown): DashboardRole {
  if (
    role === "organizer" ||
    role === "owner" ||
    role === "admin" ||
    role === "staff"
  ) {
    return role;
  }
  return null;
}

/**
 * Shared dashboard chrome — a sidebar with role-aware items + the page
 * content. Top-level pages directly under /dashboard (/conta, /perfil,
 * /favoritos, /conversas, /notificacoes, /convidar) live in the sidebar
 * for all roles; role-specific sub-areas (/dashboard/truck/*,
 * /dashboard/organizer/*, /admin/*) only show for the matching role.
 *
 * Role resolution happens server-side here so the sidebar doesn't flash
 * the wrong set on hydration. Children pages get a clean main area and
 * don't need to repeat the auth check (still safe to — defence in depth).
 */
export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  // Layout-level redirect catches the case where a child page forgets — the
  // child's own auth check is the actual permission gate.
  if (!user) redirect("/login?next=/dashboard");

  const { data: profile } = await (supa as any)
    .from("airfnb_profiles")
    .select("role, display_name, full_name")
    .eq("id", user.id)
    .maybeSingle();

  const role = toDashboardRole(profile?.role);
  const name = profile?.display_name ?? profile?.full_name ?? user.email ?? "";
  const dict = await getDictionary();

  return (
    <div className="dashboard-shell">
      <DashboardSidebar role={role} name={name} dict={dict.dashboard_sidebar} />
      <main className="dashboard-main">{children}</main>
    </div>
  );
}
