import Link from "next/link";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { money } from "@/lib/money";

export default async function MinhasCandidaturasPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/truck/aplicacoes");

  const { data: myTruck } = await supa
    .from("airfnb_trucks")
    .select("id, name")
    .eq("owner_id", user.id)
    .maybeSingle();
  if (!myTruck) redirect("/dashboard/truck/novo");

  const { data: appsData } = await supa
    .from("airfnb_applications")
    .select(`id, status, proposed_price, created_at,
             airfnb_event_requests ( id, title, start_at, city, status )`)
    .eq("truck_id", myTruck.id)
    .order("created_at", { ascending: false });
  const apps = appsData ?? [];

  return (
    <div className="dash">
      <nav className="breadcrumb">
        <Link href="/dashboard/truck">Dashboard</Link> &nbsp;/&nbsp; <span>Candidaturas</span>
      </nav>
      <h1>As minhas candidaturas</h1>

      {apps.length === 0 ? (
        <div className="empty">Ainda não submeteste nenhuma candidatura. <Link href="/pedidos" style={{ color: "var(--orange)" }}>Ver pedidos abertos</Link>.</div>
      ) : (
        <div className="request-grid">
          {apps.map((a: any) => (
            <div key={a.id} className="request-card">
              <h3>{a.airfnb_event_requests?.title ?? "—"}</h3>
              <div className="row">
                <span><span className="material-symbols-outlined">event</span>
                  {a.airfnb_event_requests?.start_at && new Date(a.airfnb_event_requests.start_at).toLocaleDateString("pt-PT", { day: "2-digit", month: "short" })}
                </span>
                <span><span className="material-symbols-outlined">location_on</span>{a.airfnb_event_requests?.city ?? "—"}</span>
                <span>Proposta: {money(a.proposed_price)}</span>
              </div>
              <div className="row" style={{ justifyContent: "space-between" }}>
                <span className="match-badge">{a.status}</span>
                {a.status === "accepted" ? (
                  <Link href={`/dashboard/truck/lock/${a.id}`} style={{ color: "var(--orange)", fontWeight: 600 }}>
                    ⏰ Pagar lock-fee →
                  </Link>
                ) : (
                  <Link href={`/pedidos/${a.airfnb_event_requests?.id}`} style={{ color: "var(--teal)", fontWeight: 600 }}>
                    Ver pedido →
                  </Link>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
