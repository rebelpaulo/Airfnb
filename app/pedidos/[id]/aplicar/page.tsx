import { notFound, redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { money } from "@/lib/money";

export default async function AplicarPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect(`/login?next=/pedidos/${id}/aplicar`);

  const { data: req } = await supa
    .from("airfnb_event_requests")
    .select("*")
    .eq("id", id)
    .maybeSingle();
  if (!req) notFound();

  const { data: myTruck } = await supa
    .from("airfnb_trucks")
    .select("id, name")
    .eq("owner_id", user.id)
    .maybeSingle();
  if (!myTruck) redirect("/signup?as=truck");

  async function submit(formData: FormData) {
    "use server";
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error("auth required");

    const truckId = String(formData.get("truck_id"));
    const dealType = String(formData.get("deal_type")) as "fixed" | "percent" | "mixed";
    const fixedTo = Number(formData.get("fixed_to_organizer") ?? 0);
    const sharePct = Number(formData.get("revenue_share_pct") ?? 0);
    const proposedPrice = Number(formData.get("proposed_price"));
    const cover = String(formData.get("cover_message") ?? "").trim();

    if (cover.length < 50) throw new Error("A mensagem de apresentação deve ter pelo menos 50 caracteres.");

    const { error } = await supa.from("airfnb_applications").insert({
      request_id: id,
      truck_id: truckId,
      proposed_price: proposedPrice,
      cover_message: cover,
      deal_type: dealType,
      proposed_fixed_to_organizer: dealType === "percent" ? 0 : fixedTo,
      proposed_revenue_share_pct:  dealType === "fixed"   ? 0 : sharePct,
    });
    if (error) throw new Error(error.message);

    revalidatePath(`/pedidos/${id}`);
    redirect(`/pedidos/${id}?applied=1`);
  }

  return (
    <form action={submit} className="apply-form">
      <h1 className="section-title" style={{ marginBottom: 4 }}>Candidatar com {myTruck.name}</h1>
      <p style={{ color: "var(--muted)", marginTop: 0 }}>
        Pedido: <strong>{req.title}</strong> · {req.expected_pax} convidados ·
        orçamento {req.budget_min ? money(req.budget_min) : "?"} – {req.budget_max ? money(req.budget_max) : "?"}
      </p>

      <input type="hidden" name="truck_id" value={myTruck.id} />

      <label className="wizard" style={{ margin: 0 }}>Tipo de combinação</label>
      <div className="deal-types">
        {(["fixed","percent","mixed"] as const).map((dt) => (
          <span key={dt}>
            <input type="radio" id={`dt-${dt}`} name="deal_type" value={dt} defaultChecked={dt === "fixed"} required />
            <label htmlFor={`dt-${dt}`}>
              {dt === "fixed"   && "Pago fixo ao organizer"}
              {dt === "percent" && "% da facturação"}
              {dt === "mixed"   && "Fixo + %"}
            </label>
          </span>
        ))}
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14, marginTop: 12 }}>
        <div>
          <label>Fixo ao organizer (€)</label>
          <input name="fixed_to_organizer" type="number" step="0.01" min={0} defaultValue={req.min_fixed_fee ?? 0}
            className="filters-btn" style={{ width: "100%", padding: "12px 14px" }} />
        </div>
        <div>
          <label>% facturação ao organizer</label>
          <input name="revenue_share_pct" type="number" step="0.1" min={0} max={100} defaultValue={req.min_revenue_share_pct ?? 0}
            className="filters-btn" style={{ width: "100%", padding: "12px 14px" }} />
        </div>
      </div>

      <label>Valor total esperado pelo truck (€)</label>
      <input name="proposed_price" type="number" step="0.01" min={0} required
        className="filters-btn" style={{ width: "100%", padding: "12px 14px" }}
        placeholder="O que prevês facturar no evento" />

      <label>Mensagem de apresentação</label>
      <textarea name="cover_message" required minLength={50} rows={6}
        className="filters-btn"
        style={{ width: "100%", padding: "12px 14px", textAlign: "left" }}
        placeholder="Conta ao organizer porque o teu truck é a escolha certa para este evento (mínimo 50 caracteres)..." />

      <div style={{ background: "#FFF6F2", padding: 14, borderRadius: 12, marginTop: 16, fontSize: 13 }}>
        Se fores aceite, pagas <strong>€50</strong> de lock-fee à plataforma para confirmares. €25 ficam connosco;
        €25 são adiantados ao organizer e descontados no que lhe pagas.
      </div>

      <div style={{ display: "flex", gap: 12, marginTop: 24 }}>
        <button className="btn-pill" type="submit">Submeter candidatura</button>
      </div>
    </form>
  );
}
