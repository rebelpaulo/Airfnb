import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { TruckWizard } from "./TruckWizard";

export const dynamic = "force-dynamic";

export default async function NovoTruckPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/truck/novo");

  const { data: categoriesData } = await (supa as any)
    .from("airfnb_categories")
    .select("id, slug, name_pt, icon")
    .order("name_pt");

  return (
    <div className="dash" style={{ maxWidth: 920 }}>
      <h1 style={{ margin: 0 }}>Adicionar o teu serviço</h1>
      <p style={{ color: "var(--muted)", margin: "6px 0 22px" }}>
        Escolhe entre Food Truck, Catering ou Bar e completa os dados em 4 passos. Tudo o que ficar por preencher podes completar
        depois no painel — só submetes para revisão quando estiver a 100%.
      </p>
      <TruckWizard userId={user.id} categories={categoriesData ?? []} />
    </div>
  );
}
