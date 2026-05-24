import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { money } from "@/lib/money";
import { truckCover } from "@/lib/img";

/**
 * Per-truck management screen.
 *
 * Shows a completion meter computed from the fields the truck needs to fill
 * before it can be submitted for admin review. Reaching 100% reveals the
 * "Submeter para revisão" button which flips the status to `pending_review`.
 */
type Checklist = {
  key: string;
  label: string;
  weight: number;        // %
  done: boolean;
  href?: string;         // where to go to fix it
};

export default async function TruckManagePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect(`/login?next=/dashboard/truck/${id}`);

  const { data: truck } = await (supa as any)
    .from("airfnb_trucks")
    .select(`
      id, owner_id, slug, name, tagline, description, base_city, capacity,
      base_price, price_per_pax, service_radius_km,
      status, rating_avg, rating_count, homologation_expires_at, insurance_expires_at
    `)
    .eq("id", id)
    .maybeSingle();
  if (!truck) notFound();
  if (truck.owner_id !== user.id) redirect("/dashboard/truck");

  const [imgsRes, menuRes, catsRes, docsRes] = await Promise.all([
    (supa as any).from("airfnb_truck_images").select("id, url, is_cover").eq("truck_id", id),
    (supa as any).from("airfnb_menu_items").select("id, name, price").eq("truck_id", id),
    (supa as any).from("airfnb_truck_categories").select("category_id").eq("truck_id", id),
    (supa as any).from("airfnb_truck_documents").select("id, kind, expires_at").eq("truck_id", id),
  ]);
  const images: any[] = imgsRes.data ?? [];
  const menu:   any[] = menuRes.data ?? [];
  const cats:   any[] = catsRes.data ?? [];
  const docs:   any[] = docsRes.data ?? [];

  const today = new Date();
  const docValid = (kind: string) =>
    docs.some((d) =>
      (d.kind ?? "").toLowerCase().includes(kind) &&
      (!d.expires_at || new Date(d.expires_at) > today),
    );

  const checklist: Checklist[] = [
    { key: "name",        label: "Nome",                         weight: 5,  done: !!truck.name?.trim() },
    { key: "tagline",     label: "Tagline",                      weight: 5,  done: !!truck.tagline?.trim() },
    { key: "description", label: "Descrição",                    weight: 10, done: (truck.description ?? "").trim().length >= 80 },
    { key: "city",        label: "Cidade base",                  weight: 5,  done: !!truck.base_city?.trim() },
    { key: "capacity",    label: "Capacidade (pax)",             weight: 5,  done: !!truck.capacity },
    { key: "price",       label: "Preço base + preço por pax",   weight: 10, done: !!truck.base_price && !!truck.price_per_pax },
    { key: "categories",  label: "Categorias (≥ 1)",             weight: 10, done: cats.length >= 1 },
    { key: "cover",       label: "Foto de capa",                 weight: 10, done: images.some((i) => i.is_cover) },
    { key: "gallery",     label: "Fotos extra (≥ 3 no total)",   weight: 10, done: images.length >= 3 },
    { key: "menu",        label: "Itens de menu (≥ 5)",          weight: 15, done: menu.length >= 5 },
    { key: "haccp",       label: "Documento HACCP válido",       weight: 7,  done: docValid("haccp") },
    { key: "insurance",   label: "Seguro válido",                weight: 8,  done: docValid("seguro") || docValid("insur") },
  ];
  const progress = checklist.reduce((sum, c) => sum + (c.done ? c.weight : 0), 0);
  const canSubmit = progress >= 100 && truck.status === "draft";

  // Cover URL
  const coverImg = images.find((i) => i.is_cover) ?? images[0];

  // ---- server actions ----
  async function submitForReview() {
    "use server";
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error("auth required");

    // Re-fetch everything server-side and recompute the checklist — never
    // trust the UI's `canSubmit` boolean. A user could craft a request
    // bypassing the button.
    const [tRes, iRes, mRes, cRes, dRes] = await Promise.all([
      (supa as any).from("airfnb_trucks")
        .select("id, owner_id, status, name, tagline, description, base_city, capacity, base_price, price_per_pax")
        .eq("id", id).maybeSingle(),
      (supa as any).from("airfnb_truck_images").select("id, is_cover").eq("truck_id", id),
      (supa as any).from("airfnb_menu_items").select("id").eq("truck_id", id),
      (supa as any).from("airfnb_truck_categories").select("category_id").eq("truck_id", id),
      (supa as any).from("airfnb_truck_documents").select("id, kind, expires_at").eq("truck_id", id),
    ]);
    const t = tRes.data;
    if (!t) throw new Error("Truck não encontrado.");
    if (t.owner_id !== user.id) throw new Error("Sem permissão.");
    if (t.status !== "draft") throw new Error("Só trucks em rascunho podem ser submetidos.");

    const imgs = (iRes.data as any[]) ?? [];
    const items = (mRes.data as any[]) ?? [];
    const cats  = (cRes.data as any[]) ?? [];
    const ds    = (dRes.data as any[]) ?? [];
    const now = new Date();
    const docOk = (kind: string) =>
      ds.some((d) =>
        (d.kind ?? "").toLowerCase().includes(kind) &&
        (!d.expires_at || new Date(d.expires_at) > now),
      );

    const score = [
      [5,  !!t.name?.trim()],
      [5,  !!t.tagline?.trim()],
      [10, (t.description ?? "").trim().length >= 80],
      [5,  !!t.base_city?.trim()],
      [5,  !!t.capacity],
      [10, !!t.base_price && !!t.price_per_pax],
      [10, cats.length >= 1],
      [10, imgs.some((i) => i.is_cover)],
      [10, imgs.length >= 3],
      [15, items.length >= 5],
      [7,  docOk("haccp")],
      [8,  docOk("seguro") || docOk("insur")],
    ].reduce((s, [w, ok]) => s + ((ok as boolean) ? (w as number) : 0), 0);

    if (score < 100) {
      throw new Error(`Faltam dados (${score}% completo). Completa o checklist antes de submeter.`);
    }

    const { error } = await (supa as any)
      .from("airfnb_trucks")
      .update({ status: "pending_review" })
      .eq("id", id)
      .eq("owner_id", user.id)
      .eq("status", "draft");
    if (error) throw new Error(error.message);
    revalidatePath(`/dashboard/truck/${id}`);
    revalidatePath(`/dashboard/truck`);
  }

  async function pause() {
    "use server";
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error("auth required");
    const { error } = await (supa as any).from("airfnb_trucks")
      .update({ status: "paused" })
      .eq("id", id).eq("owner_id", user.id).eq("status", "active");
    if (error) throw new Error(error.message);
    revalidatePath(`/dashboard/truck/${id}`);
  }
  async function resume() {
    "use server";
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error("auth required");
    const { error } = await (supa as any).from("airfnb_trucks")
      .update({ status: "active" })
      .eq("id", id).eq("owner_id", user.id).eq("status", "paused");
    if (error) throw new Error(error.message);
    revalidatePath(`/dashboard/truck/${id}`);
  }

  return (
    <div className="dash" style={{ maxWidth: 1100 }}>
      <nav className="breadcrumb">
        <Link href="/dashboard/truck">Os meus trucks</Link> &nbsp;/&nbsp; <span>{truck.name}</span>
      </nav>

      <div style={{ display: "grid", gridTemplateColumns: "200px 1fr", gap: 24, alignItems: "center" }}>
        <div className="thumb" style={{ aspectRatio: "4/3", borderRadius: 14, overflow: "hidden" }}>
          <img src={truckCover(coverImg?.url)} alt={truck.name} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
        </div>
        <div>
          <h1 style={{ margin: 0 }}>{truck.name}</h1>
          <div style={{ marginTop: 8, display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
            <StatusBadge status={truck.status} />
            <span style={{ color: "var(--muted)" }}>★ {Number(truck.rating_avg).toFixed(1)} ({truck.rating_count})</span>
            <span style={{ color: "var(--muted)" }}>·</span>
            <span style={{ color: "var(--muted)" }}>{truck.base_city ?? "—"}</span>
          </div>
          {truck.tagline && <p style={{ marginTop: 8, color: "var(--ink)" }}>{truck.tagline}</p>}
        </div>
      </div>

      {/* ----- Progress meter ----- */}
      <section style={{ marginTop: 26, background: "#fff", border: "1px solid var(--line)", borderRadius: 14, padding: 22 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end", gap: 14, flexWrap: "wrap" }}>
          <div>
            <div style={{ fontSize: 13, color: "var(--muted)", letterSpacing: 0.4, textTransform: "uppercase", fontWeight: 700 }}>
              Completude do perfil
            </div>
            <div style={{ fontFamily: "Bebas Neue, sans-serif", fontSize: 44, color: "var(--orange)", lineHeight: 1 }}>
              {progress}%
            </div>
          </div>
          <div style={{ flex: 1, minWidth: 220 }}>
            <div style={{ height: 12, background: "#F2F2F2", borderRadius: 999, overflow: "hidden" }}>
              <div style={{
                width: `${progress}%`, height: "100%",
                background: progress >= 100 ? "#10A37F" : "linear-gradient(90deg,#FF4919,#FF6133)",
                transition: "width .25s ease",
              }} />
            </div>
            <div style={{ marginTop: 8, fontSize: 13, color: "var(--muted)" }}>
              {progress < 100
                ? "Completa todos os campos para submeteres o truck para revisão da equipa."
                : truck.status === "draft"
                  ? "Tudo pronto! Submete para revisão e a equipa valida em 24-48h."
                  : truck.status === "pending_review"
                    ? "Em análise pela equipa Air F&B. Notificamos-te quando for aprovado."
                    : "Tudo em ordem."}
            </div>
          </div>
          <div style={{ display: "flex", gap: 10 }}>
            {canSubmit && (
              <form action={submitForReview}>
                <button className="btn-pill" type="submit">Submeter para revisão</button>
              </form>
            )}
            {truck.status === "active" && (
              <form action={pause}>
                <button className="btn-pill" type="submit" style={{ background: "#888" }}>Pausar</button>
              </form>
            )}
            {truck.status === "paused" && (
              <form action={resume}>
                <button className="btn-pill" type="submit">Retomar</button>
              </form>
            )}
          </div>
        </div>

        <ul style={{ listStyle: "none", padding: 0, marginTop: 18, display: "grid", gap: 6 }}>
          {checklist.map((c) => (
            <li key={c.key} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "8px 0", borderBottom: "1px solid var(--line)" }}>
              <span style={{ display: "inline-flex", gap: 8, alignItems: "center" }}>
                <span className="material-symbols-outlined" style={{ fontSize: 18, color: c.done ? "#10A37F" : "#C8C8C8" }}>
                  {c.done ? "check_circle" : "radio_button_unchecked"}
                </span>
                <span style={{ color: c.done ? "var(--ink)" : "var(--muted)" }}>{c.label}</span>
              </span>
              <span style={{ fontSize: 12, color: "var(--muted)" }}>{c.weight}%</span>
            </li>
          ))}
        </ul>
      </section>

      <section style={{ marginTop: 30 }}>
        <div style={{ display: "flex", gap: 12, flexWrap: "wrap" }}>
          <Link className="btn-pill outline" href={`/dashboard/truck/${id}/editar`}
                style={{ borderColor: "var(--teal)", color: "var(--teal)" }}>
            Editar dados básicos
          </Link>
          <Link className="btn-pill outline" href={`/dashboard/truck/${id}/fotos`}
                style={{ borderColor: "var(--teal)", color: "var(--teal)" }}>
            Galeria de fotos ({images.length})
          </Link>
          <Link className="btn-pill outline" href={`/dashboard/truck/${id}/menu`}
                style={{ borderColor: "var(--teal)", color: "var(--teal)" }}>
            Menu ({menu.length})
          </Link>
          <Link className="btn-pill outline" href={`/dashboard/truck/${id}/documentos`}
                style={{ borderColor: "var(--teal)", color: "var(--teal)" }}>
            Documentos ({docs.length})
          </Link>
        </div>
        <p style={{ color: "var(--muted)", marginTop: 14, fontSize: 13 }}>
          Os ecrãs detalhados (fotos, menu, documentos) chegam no próximo bloco — por enquanto,
          o essencial vive em "Editar dados básicos" e tu acompanhas a percentagem aqui.
        </p>
      </section>

      {truck.base_price && (
        <p style={{ marginTop: 20, color: "var(--muted)" }}>
          Preço base: {money(truck.base_price)} · Por pax: {money(truck.price_per_pax)}
        </p>
      )}
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  const map: Record<string, { label: string; bg: string }> = {
    draft:          { label: "Rascunho",   bg: "#888" },
    pending_review: { label: "Em revisão", bg: "var(--teal)" },
    active:         { label: "Activo",     bg: "#10A37F" },
    paused:         { label: "Pausado",    bg: "#B85C00" },
    archived:       { label: "Arquivado",  bg: "#444" },
  };
  const v = map[status] ?? { label: status, bg: "#444" };
  return (
    <span style={{
      background: v.bg, color: "#fff", fontWeight: 700, fontSize: 12,
      padding: "4px 12px", borderRadius: 999, letterSpacing: 0.5, textTransform: "uppercase",
    }}>{v.label}</span>
  );
}
