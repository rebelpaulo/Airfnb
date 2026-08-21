import { notFound, redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { money } from "@/lib/money";

export default async function AplicarPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect(`/login?next=/pedidos/${id}/aplicar`);

  const { data: req } = await (supa as any)
    .from("airfnb_event_requests")
    .select("id, title, expected_pax, budget_min, budget_max, min_fixed_fee, min_revenue_share_pct")
    .eq("id", id)
    .maybeSingle();
  if (!req) notFound();

  const { data: myTruck, error: myTruckError } = await (supa as any)
    .rpc("airfnb_own_application_truck")
    .maybeSingle();
  if (myTruckError) throw new Error(myTruckError.message);
  if (!myTruck) redirect("/signup?as=truck");

  const { data: canSubmit, error: canSubmitError } = await (supa as any)
    .rpc("airfnb_can_submit_application", {
      p_request: id,
      p_truck: myTruck.truck_id,
    });
  if (canSubmitError) throw new Error(canSubmitError.message);
  if (!canSubmit) redirect(`/pedidos/${id}`);

  async function submit(formData: FormData) {
    "use server";
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error("auth required");

    // Resolve the caller's own service through the owner-scoped RPC. The browser
    // never supplies a truck_id, so it cannot submit an application as another owner.
    const { data: myTruck, error: myTruckError } = await (supa as any)
      .rpc("airfnb_own_application_truck")
      .maybeSingle();
    if (myTruckError) throw new Error(myTruckError.message);
    if (!myTruck) throw new Error("Sem fornecedor registado nesta conta.");

    const { data: canSubmit, error: canSubmitError } = await (supa as any)
      .rpc("airfnb_can_submit_application", {
        p_request: id,
        p_truck: myTruck.truck_id,
      });
    if (canSubmitError) throw new Error(canSubmitError.message);
    if (!canSubmit) throw new Error("Este serviço não pode candidatar-se a este pedido.");

    const dealType = String(formData.get("deal_type")) as "fixed" | "percent" | "mixed";
    if (!["fixed", "percent", "mixed"].includes(dealType)) throw new Error("Tipo de combinação inválido.");

    const fixedTo = Number(formData.get("fixed_to_organizer") ?? 0);
    const sharePct = Number(formData.get("revenue_share_pct") ?? 0);
    const proposedPrice = Number(formData.get("proposed_price"));
    const cover = String(formData.get("cover_message") ?? "").trim();

    if (!isFinite(proposedPrice) || proposedPrice < 0) throw new Error("Preço proposto inválido.");
    if (cover.length < 50) throw new Error("A mensagem de apresentação deve ter pelo menos 50 caracteres.");
    if (sharePct < 0 || sharePct > 100) throw new Error("Percentagem inválida (0-100).");
    if (fixedTo < 0) throw new Error("Fixo inválido.");

    const { error } = await (supa as any).from("airfnb_applications").insert({
      request_id: id,
      truck_id: myTruck.truck_id,
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
      <h1 className="section-title" style={{ marginBottom: 4 }}>Candidatar o serviço {myTruck.truck_name}</h1>
      <p style={{ color: "var(--muted)", marginTop: 0 }}>
        Pedido: <strong>{req.title}</strong> · {req.expected_pax} convidados ·
        orçamento {req.budget_min ? money(req.budget_min) : "?"} – {req.budget_max ? money(req.budget_max) : "?"}
      </p>

      <label className="wizard" style={{ margin: 0 }}>Tipo de combinação</label>
      <div className="deal-types">
        {(["fixed","percent","mixed"] as const).map((dt) => (
          <span key={dt}>
            <input type="radio" id={`dt-${dt}`} name="deal_type" value={dt} defaultChecked={dt === "fixed"} required />
            <label htmlFor={`dt-${dt}`}>
              {dt === "fixed"   && "Pago fixo ao organizador"}
              {dt === "percent" && "% da faturação"}
              {dt === "mixed"   && "Fixo + %"}
            </label>
          </span>
        ))}
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14, marginTop: 12 }}>
        <div>
          <label>Fixo ao organizador (€)</label>
          <input name="fixed_to_organizer" type="number" step="0.01" min={0} defaultValue={req.min_fixed_fee ?? 0}
            className="filters-btn" style={{ width: "100%", padding: "12px 14px" }} />
        </div>
        <div>
          <label>% faturação ao organizador</label>
          <input name="revenue_share_pct" type="number" step="0.1" min={0} max={100} defaultValue={req.min_revenue_share_pct ?? 0}
            className="filters-btn" style={{ width: "100%", padding: "12px 14px" }} />
        </div>
      </div>

      <label>Valor total esperado pelo fornecedor (€)</label>
      <input name="proposed_price" type="number" step="0.01" min={0} required
        className="filters-btn" style={{ width: "100%", padding: "12px 14px" }}
        placeholder="O que prevês faturar no evento" />

      <label>Mensagem de apresentação</label>
      <textarea name="cover_message" required minLength={50} rows={6}
        className="filters-btn"
        style={{ width: "100%", padding: "12px 14px", textAlign: "left" }}
        placeholder="Conta ao organizador por que motivo o teu serviço é a escolha certa para este evento (mínimo 50 caracteres)..." />

      <div style={{ background: "#FFF6F2", padding: 14, borderRadius: 12, marginTop: 16, fontSize: 13 }}>
        Se fores aceite, a taxa de confirmação aplicável e a respetiva repartição serão mostradas antes do pagamento.
      </div>

      <div style={{ display: "flex", gap: 12, marginTop: 24 }}>
        <button className="btn-pill" type="submit">Submeter candidatura</button>
      </div>
    </form>
  );
}
