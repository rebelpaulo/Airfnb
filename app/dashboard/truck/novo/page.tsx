import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";

export default async function NovoTruckPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/truck/novo");

  const { data: existing } = await (supa as any)
    .from("airfnb_trucks")
    .select("id")
    .eq("owner_id", user.id)
    .maybeSingle();
  if (existing) redirect("/dashboard/truck/perfil");

  const { data: categoriesData } = await (supa as any)
    .from("airfnb_categories")
    .select("id, slug, name_pt, icon")
    .order("name_pt");
  const categories = categoriesData ?? [];

  async function create(formData: FormData) {
    "use server";
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error("auth required");

    const name = String(formData.get("name") ?? "").trim();
    const slug = slugify(String(formData.get("slug") ?? name));
    const tagline = String(formData.get("tagline") ?? "").trim() || null;
    const description = String(formData.get("description") ?? "").trim() || null;
    const baseCity = String(formData.get("base_city") ?? "").trim() || null;
    const capacity = Number(formData.get("capacity") ?? 100) || 100;
    const basePrice = Number(formData.get("base_price") ?? 0) || null;
    const pricePerPax = Number(formData.get("price_per_pax") ?? 0) || null;
    const radius = Number(formData.get("service_radius_km") ?? 50) || 50;
    const coverUrl = String(formData.get("cover_url") ?? "").trim() || null;
    const catIds = formData.getAll("category_id").map((v) => Number(v));

    // ensure profile is upgraded to owner
    const { error: roleErr } = await (supa as any)
      .from("airfnb_profiles")
      .update({ role: "owner" })
      .eq("id", user.id);
    if (roleErr) {
      // log but don't block — owning a truck row is itself authoritative for owner-side flows
      console.warn("airfnb_profiles.role upgrade failed:", roleErr.message);
    }

    const { data: row, error } = await (supa as any)
      .from("airfnb_trucks")
      .insert({
        owner_id: user.id,
        slug,
        name,
        tagline,
        description,
        base_city: baseCity,
        capacity,
        base_price: basePrice,
        price_per_pax: pricePerPax,
        service_radius_km: radius,
        status: "active",
      })
      .select("id")
      .single();
    if (error) throw new Error(error.message);

    if (catIds.length) {
      await (supa as any).from("airfnb_truck_categories").insert(
        catIds.map((cid) => ({ truck_id: row.id, category_id: cid }))
      );
    }
    if (coverUrl) {
      await (supa as any).from("airfnb_truck_images").insert({
        truck_id: row.id,
        url: coverUrl,
        is_cover: true,
        sort_order: 0,
      });
    }
    redirect("/dashboard/truck");
  }

  return (
    <form action={create} className="wizard">
      <h1>Adicionar o teu Food Truck</h1>
      <p style={{ color: "var(--muted)", margin: 0 }}>
        Pronto em menos de 2 minutos. Podes editar depois.
      </p>

      <label>Nome do truck</label>
      <input name="name" required maxLength={120} placeholder="Ex: Divine Burguer's" />

      <label>Slug (URL — opcional)</label>
      <input name="slug" placeholder="divine-burguers" />

      <label>Tagline (1 frase)</label>
      <input name="tagline" maxLength={140} placeholder="Ex: O melhor estilo americano" />

      <label>Descrição</label>
      <textarea name="description" placeholder="Conta o que serves, o teu estilo, o que te distingue" />

      <div style={{ display: "grid", gridTemplateColumns: "2fr 1fr 1fr", gap: 14 }}>
        <div><label>Cidade base</label><input name="base_city" placeholder="Lisboa" /></div>
        <div><label>Raio serviço (km)</label><input name="service_radius_km" type="number" min={5} max={500} defaultValue={50} /></div>
        <div><label>Capacidade (pax)</label><input name="capacity" type="number" min={10} defaultValue={100} /></div>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
        <div><label>Preço base (€)</label><input name="base_price" type="number" step="10" min={0} placeholder="800" /></div>
        <div><label>Preço por pax (€)</label><input name="price_per_pax" type="number" step="0.5" min={0} placeholder="12" /></div>
      </div>

      <label>URL da foto de capa</label>
      <input name="cover_url" type="url" placeholder="https://..." />
      <small style={{ color: "var(--muted)" }}>Mais tarde podes carregar fotos do teu computador.</small>

      <label>Categorias</label>
      <div className="chips">
        {categories.map((c: any) => (
          <label key={c.id} className="chip" style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
            <input type="checkbox" name="category_id" value={c.id} style={{ margin: 0 }} />
            <span className="material-symbols-outlined" style={{ fontSize: 16 }}>{c.icon ?? "restaurant"}</span>
            {c.name_pt}
          </label>
        ))}
      </div>

      <div className="actions">
        <span />
        <button className="btn-pill" type="submit">Publicar truck</button>
      </div>
    </form>
  );
}

function slugify(s: string) {
  return s.toLowerCase()
    .normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60) || ("truck-" + Math.random().toString(36).slice(2, 8));
}
