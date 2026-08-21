import Link from "next/link";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";

export default async function TruckPerfilPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/truck/perfil");

  const { data: truck } = await (supa as any)
    .rpc("airfnb_supplier_services", { p_truck: null })
    .limit(1)
    .maybeSingle();
  if (!truck) redirect("/dashboard/truck/novo");

  async function save(formData: FormData) {
    "use server";
    const supa = await supabaseServer();
    const patch = {
      name:        String(formData.get("name") ?? truck!.name),
      tagline:     String(formData.get("tagline") ?? "") || null,
      description: String(formData.get("description") ?? "") || null,
      base_city:   String(formData.get("base_city") ?? "") || null,
      capacity:    Number(formData.get("capacity") ?? truck!.capacity) || null,
      base_price:  Number(formData.get("base_price") ?? 0) || null,
      price_per_pax: Number(formData.get("price_per_pax") ?? 0) || null,
      service_radius_km: Number(formData.get("service_radius_km") ?? 50) || 50,
    };
    await (supa as any).from("airfnb_trucks").update(patch).eq("id", truck!.id);
    revalidatePath("/dashboard/truck/perfil");
  }

  return (
    <form action={save} className="wizard">
      <nav className="breadcrumb">
        <Link href="/dashboard/truck">Dashboard</Link> &nbsp;/&nbsp; <span>Perfil do serviço</span>
      </nav>
      <h1>Perfil do serviço</h1>
      <p style={{ color: "var(--muted)", margin: 0 }}>Editar os dados públicos de {truck.name}.</p>

      <label>Nome</label>
      <input name="name" required defaultValue={truck.name} />

      <label>Tagline</label>
      <input name="tagline" defaultValue={truck.tagline ?? ""} />

      <label>Descrição</label>
      <textarea name="description" defaultValue={truck.description ?? ""} />

      <div style={{ display: "grid", gridTemplateColumns: "2fr 1fr 1fr", gap: 14 }}>
        <div><label>Cidade base</label><input name="base_city" defaultValue={truck.base_city ?? ""} /></div>
        <div><label>Raio (km)</label><input name="service_radius_km" type="number" defaultValue={truck.service_radius_km ?? 50} /></div>
        <div><label>Capacidade (pax)</label><input name="capacity" type="number" defaultValue={truck.capacity ?? 100} /></div>
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
        <div><label>Preço base (€)</label><input name="base_price" type="number" defaultValue={truck.base_price ?? ""} /></div>
        <div><label>Preço por pax (€)</label><input name="price_per_pax" type="number" defaultValue={truck.price_per_pax ?? ""} /></div>
      </div>

      <div className="actions">
        <Link href="/dashboard/truck" className="btn-pill outline" style={{ borderColor: "var(--muted)", color: "var(--muted)" }}>Voltar</Link>
        <button className="btn-pill" type="submit">Guardar</button>
      </div>
    </form>
  );
}
