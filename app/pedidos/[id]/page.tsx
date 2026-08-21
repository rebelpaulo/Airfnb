import Link from "next/link";
import { notFound } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { money } from "@/lib/money";

export default async function RequestDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supa = await supabaseServer();

  const { data: req } = await (supa as any)
    .from("airfnb_event_requests")
    .select("id, title, description, start_at, city, expected_pax, slots_needed, budget_min, budget_max, accepted_deal_types, min_fixed_fee, min_revenue_share_pct")
    .eq("id", id)
    .maybeSingle();

  if (!req) notFound();

  const { data: { user } } = await supa.auth.getUser();
  const { count: applicationCount } = await (supa as any)
    .from("airfnb_applications")
    .select("id", { count: "exact", head: true })
    .eq("request_id", id);

  // is the current user a truck owner? show "Apply" if yes.
  let myTruckId: string | null = null;
  let alreadyApplied = false;
  let canApply = false;
  if (user) {
    const { data: myTruck, error: myTruckError } = await (supa as any)
      .rpc("airfnb_own_application_truck")
      .maybeSingle();
    if (myTruckError) throw new Error(myTruckError.message);
    if (myTruck) {
      myTruckId = myTruck.truck_id;
      const { count } = await (supa as any)
        .from("airfnb_applications")
        .select("id", { count: "exact", head: true })
        .eq("request_id", id)
        .eq("truck_id", myTruck.truck_id);
      alreadyApplied = (count ?? 0) > 0;
      if (!alreadyApplied) {
        const { data: eligible, error: eligibleError } = await (supa as any)
          .rpc("airfnb_can_submit_application", {
            p_request: id,
            p_truck: myTruck.truck_id,
          });
        if (eligibleError) throw new Error(eligibleError.message);
        canApply = eligible === true;
      }
    }
  }

  const fmtDate = (d: string) =>
    new Date(d).toLocaleString("pt-PT", { weekday: "short", day: "2-digit", month: "long", hour: "2-digit", minute: "2-digit" });

  return (
    <div className="container" style={{ paddingTop: 120, paddingBottom: 80, maxWidth: 900 }}>
      <nav className="breadcrumb">
        <Link href="/">Início</Link> &nbsp;/&nbsp; <Link href="/pedidos">Pedidos</Link> &nbsp;/&nbsp; <span>{req.title}</span>
      </nav>

      <h1 className="section-title" style={{ marginBottom: 8 }}>{req.title}</h1>
      <p style={{ color: "var(--muted)", marginTop: 0 }}>
        Publicado para {req.expected_pax} convidados · {req.slots_needed} {req.slots_needed === 1 ? "fornecedor pretendido" : "fornecedores pretendidos"}
      </p>

      <div className="dash stat-strip" style={{ marginTop: 26, marginBottom: 26 }}>
        <div className="stat"><div className="label">Quando</div><div className="value" style={{ fontSize: 18 }}>{fmtDate(req.start_at)}</div></div>
        <div className="stat"><div className="label">Onde</div><div className="value" style={{ fontSize: 22 }}>{req.city ?? "—"}</div></div>
        <div className="stat"><div className="label">Orçamento</div><div className="value" style={{ fontSize: 22 }}>{req.budget_min ? money(req.budget_min) : "?"} – {req.budget_max ? money(req.budget_max) : "?"}</div></div>
        <div className="stat"><div className="label">Candidaturas</div><div className="value">{applicationCount ?? 0}</div></div>
      </div>

      {req.description && (
        <>
          <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 30 }}>Descrição</h2>
          <p style={{ lineHeight: 1.65 }}>{req.description}</p>
        </>
      )}

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 30 }}>Modalidades aceites</h2>
      <ul>
        {req.accepted_deal_types?.map((dt: string) => (
          <li key={dt}>
            {dt === "fixed" && "Fornecedor paga fixo ao organizador"}
            {dt === "percent" && "Fornecedor paga % da faturação"}
            {dt === "mixed" && "Misto: fixo + % faturação"}
          </li>
        ))}
      </ul>
      {(req.min_fixed_fee || req.min_revenue_share_pct) && (
        <p style={{ fontSize: 14, color: "var(--muted)" }}>
          {req.min_fixed_fee ? `Fixo mínimo aceite: ${money(req.min_fixed_fee)}. ` : ""}
          {req.min_revenue_share_pct ? `% mínima aceite: ${req.min_revenue_share_pct}%. ` : ""}
        </p>
      )}

      <div style={{ marginTop: 40, display: "flex", gap: 12 }}>
        {!user && (
          <Link className="btn-pill" href={`/login?next=/pedidos/${id}`}>Entrar para aplicar</Link>
        )}
        {user && myTruckId && !alreadyApplied && canApply && (
          <Link className="btn-pill" href={`/pedidos/${id}/aplicar`}>Aplicar a este pedido</Link>
        )}
        {user && myTruckId && alreadyApplied && (
          <span className="btn-pill outline" style={{ borderColor: "var(--teal)", color: "var(--teal)" }}>Já aplicaste a este pedido</span>
        )}
        {user && !myTruckId && (
          <Link className="btn-pill outline" href="/signup?as=truck">Adicionar o teu serviço primeiro</Link>
        )}
      </div>
    </div>
  );
}
