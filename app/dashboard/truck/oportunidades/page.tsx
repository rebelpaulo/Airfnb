import Link from "next/link";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { money } from "@/lib/money";

export const dynamic = "force-dynamic";

/**
 * Truck-side feed of OPEN event requests the owner could apply to.
 *
 * An owner may have several trucks — we show one merged feed deduped on
 * request_id and surface the best-matching truck per request so the same
 * brief doesn't appear N times. The `airfnb_match_score` SQL helper does
 * the heavy lifting.
 */
export default async function OportunidadesPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/truck/oportunidades");

  const { data: myTrucks } = await (supa as any)
    .from("airfnb_trucks")
    .select("id, name, base_city, status")
    .eq("owner_id", user.id)
    .in("status", ["active", "paused"]);
  if (!myTrucks?.length) redirect("/dashboard/truck/novo");

  const { data: requests } = await (supa as any)
    .from("airfnb_event_requests")
    .select("id, title, kind, start_at, end_at, city, expected_pax, slots_needed, budget_min, budget_max, status, applications_deadline")
    .eq("status", "open")
    .gte("start_at", new Date().toISOString())
    .order("start_at", { ascending: true })
    .limit(80);
  const reqs: any[] = requests ?? [];

  // Per (request, truck) match score so we can pick the best truck for each.
  // The RPC is per-pair; we don't have a batch flavor yet, so call it once
  // per truck (≤ ~10 in practice) and merge results.
  const allScores: Array<{ request_id: string; truck_id: string; match_score: number; truck_name: string }> = [];
  for (const truck of myTrucks) {
    for (const r of reqs) {
      const { data } = await (supa as any).rpc("airfnb_match_score", {
        p_truck:   truck.id,
        p_request: r.id,
      });
      const score = Number(data) || 0;
      if (score > 0) {
        allScores.push({ request_id: r.id, truck_id: truck.id, match_score: score, truck_name: truck.name });
      }
    }
  }

  // Best-truck-per-request dedup (keep highest score)
  const best = new Map<string, { match_score: number; truck_name: string; truck_id: string }>();
  for (const s of allScores) {
    const cur = best.get(s.request_id);
    if (!cur || cur.match_score < s.match_score) {
      best.set(s.request_id, { match_score: s.match_score, truck_name: s.truck_name, truck_id: s.truck_id });
    }
  }

  // Already-applied check — hide brieves the owner already chased
  const { data: existingApps } = await (supa as any)
    .from("airfnb_applications")
    .select("request_id, truck_id")
    .in("truck_id", myTrucks.map((t: any) => t.id));
  const appliedByRequest = new Set(((existingApps as any[]) ?? []).map((a) => a.request_id));

  const opportunities = reqs
    .map((r) => ({ req: r, match: best.get(r.id), applied: appliedByRequest.has(r.id) }))
    .filter((x) => x.match)
    .sort((a, b) => (b.match!.match_score) - (a.match!.match_score));

  return (
    <div className="dash">
      <nav className="breadcrumb">
        <Link href="/dashboard/truck">Dashboard</Link> &nbsp;/&nbsp; <span>Oportunidades</span>
      </nav>
      <h1 style={{ margin: 0 }}>Pedidos abertos para ti</h1>
      <p style={{ color: "var(--muted)", marginTop: 6 }}>
        Ordenado pelo score de match — quanto mais alto, melhor o pedido encaixa no perfil dos teus trucks.
      </p>

      {opportunities.length === 0 ? (
        <div className="dash empty" style={{ marginTop: 24 }}>
          De momento não há pedidos abertos que dêem match com os teus trucks. Volta mais tarde.
        </div>
      ) : (
        <ul style={{ listStyle: "none", padding: 0, marginTop: 22, display: "grid", gap: 12 }}>
          {opportunities.map(({ req, match, applied }) => (
            <li key={req.id} style={{ border: "1px solid var(--line)", borderRadius: 14, padding: 18, background: "#fff", display: "grid", gridTemplateColumns: "1fr auto", gap: 14, alignItems: "center" }}>
              <div>
                <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
                  <h3 style={{ margin: 0 }}>{req.title}</h3>
                  <span style={{ background: scoreColor(match!.match_score), color: "#fff", padding: "2px 10px", borderRadius: 999, fontSize: 12, fontWeight: 700, letterSpacing: 0.4 }}>
                    {Math.round(match!.match_score)}% match
                  </span>
                  {applied && (
                    <span style={{ background: "#888", color: "#fff", padding: "2px 10px", borderRadius: 999, fontSize: 12, fontWeight: 700 }}>
                      Já candidataste
                    </span>
                  )}
                </div>
                <div style={{ color: "var(--muted)", fontSize: 13, marginTop: 4 }}>
                  {fmtDate(req.start_at)} · {req.city ?? "—"} · {req.expected_pax} pax · {req.slots_needed ?? 1} {req.slots_needed === 1 ? "truck" : "trucks"}
                  {req.budget_min || req.budget_max
                    ? ` · orçamento ${money(req.budget_min ?? 0)} – ${money(req.budget_max ?? 0)}`
                    : ""}
                </div>
                <div style={{ color: "var(--muted)", fontSize: 12, marginTop: 2 }}>
                  Melhor encaixe: <strong style={{ color: "var(--ink)" }}>{match!.truck_name}</strong>
                  {req.applications_deadline && ` · candidaturas até ${fmtDate(req.applications_deadline)}`}
                </div>
              </div>
              <Link
                href={`/dashboard/truck/oportunidades/${req.id}?truck=${match!.truck_id}`}
                className="btn-pill"
                style={{ padding: "10px 22px" }}
              >
                {applied ? "Ver candidatura" : "Candidatar"}
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function scoreColor(s: number): string {
  if (s >= 70) return "#10A37F";
  if (s >= 40) return "var(--orange)";
  return "#888";
}

function fmtDate(iso: string): string {
  return new Date(iso).toLocaleDateString("pt-PT", { day: "2-digit", month: "short", year: "numeric" });
}
