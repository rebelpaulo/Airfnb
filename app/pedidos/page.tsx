import Link from "next/link";
import { supabaseServer } from "@/lib/supabase/server";
import { money } from "@/lib/money";

export const revalidate = 30;

type SearchParams = Promise<{ city?: string; kind?: string }>;

export default async function PedidosPage({ searchParams }: { searchParams: SearchParams }) {
  const sp = await searchParams;
  const supa = await supabaseServer();

  let q = (supa as any)
    .from("airfnb_event_requests")
    .select("id, title, kind, city, start_at, expected_pax, budget_min, budget_max, slots_needed")
    .eq("status", "open")
    .eq("visibility", "public")
    .order("start_at", { ascending: true });

  if (sp.city) q = q.ilike("city", `%${sp.city}%`);
  if (sp.kind) q = q.eq("kind", sp.kind as any);

  const { data } = await q;
  const requests = data ?? [];

  return (
    <div className="container" style={{ paddingTop: 120, paddingBottom: 80 }}>
      <h1 className="section-title">Pedidos abertos</h1>
      <p style={{ color: "var(--muted)", marginTop: -10 }}>
        Vê os eventos que estão à procura de fornecedores de Food Truck, Catering ou Bar neste momento.
      </p>

      <form className="filters-bar" style={{ marginTop: 24 }}>
        <input
          name="city"
          className="filters-btn"
          style={{ padding: "12px 18px", minWidth: 200 }}
          placeholder="Cidade"
          defaultValue={sp.city ?? ""}
        />
        <select name="kind" className="filters-btn" defaultValue={sp.kind ?? ""}>
          <option value="">Todos os tipos</option>
          <option value="wedding">Casamento</option>
          <option value="birthday">Aniversário</option>
          <option value="corporate">Corporativo</option>
          <option value="festival">Festival</option>
          <option value="conference">Conferência</option>
          <option value="private">Festa Privada</option>
          <option value="other">Outro</option>
        </select>
        <button className="btn-pill" type="submit">Filtrar</button>
      </form>

      {requests.length === 0 ? (
        <div className="dash empty" style={{ marginTop: 30 }}>
          Não há pedidos abertos com estes filtros agora.
        </div>
      ) : (
        <div className="request-grid">
          {requests.map((r: any) => (
            <Link key={r.id} href={`/pedidos/${r.id}`} className="request-card">
              <h3>{r.title}</h3>
              <div className="row">
                <span>
                  <span className="material-symbols-outlined">event</span>
                  {new Date(r.start_at).toLocaleString("pt-PT", {
                    day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit",
                  })}
                </span>
                <span>
                  <span className="material-symbols-outlined">location_on</span>
                  {r.city ?? "—"}
                </span>
              </div>
              <div className="row">
                <span>
                  <span className="material-symbols-outlined">group</span>
                  {r.expected_pax} convidados
                </span>
                <span>
                  <span className="material-symbols-outlined">local_shipping</span>
                  {r.slots_needed} {r.slots_needed === 1 ? "fornecedor" : "fornecedores"}
                </span>
              </div>
              <div className="row" style={{ justifyContent: "space-between" }}>
                <span className="match-badge">
                  Orçamento {r.budget_min ? money(r.budget_min) : "?"} – {r.budget_max ? money(r.budget_max) : "?"}
                </span>
                <span style={{ color: "var(--orange)", fontWeight: 600 }}>
                  Aplicar →
                </span>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
