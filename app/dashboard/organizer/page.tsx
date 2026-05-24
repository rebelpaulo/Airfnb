import Link from "next/link";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";

export default async function OrganizerDashboard() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/organizer");

  const { data: requestsData } = await supa
    .from("airfnb_event_requests")
    .select("id, title, status, start_at, city, expected_pax")
    .eq("organizer_id", user.id)
    .order("created_at", { ascending: false });
  const requests = requestsData ?? [];

  const open = requests.filter((r) => r.status === "open" || r.status === "reviewing").length;
  const awarded = requests.filter((r) => r.status === "awarded").length;
  const total = requests.length;

  return (
    <div className="dash">
      <h1>Olá 👋 Os teus pedidos</h1>
      <div className="stat-strip">
        <div className="stat"><div className="label">Total publicados</div><div className="value">{total}</div></div>
        <div className="stat"><div className="label">Abertos / em revisão</div><div className="value">{open}</div></div>
        <div className="stat"><div className="label">Awarded</div><div className="value">{awarded}</div></div>
        <div className="stat"><div className="label">Próxima ação</div><div className="value" style={{ fontSize: 18 }}>
          <Link href="/publicar" style={{ color: "var(--orange)" }}>Publicar novo</Link>
        </div></div>
      </div>

      {requests.length === 0 ? (
        <div className="empty">
          Ainda não tens nenhum pedido publicado. <Link href="/publicar" style={{ color: "var(--orange)" }}>Publica o primeiro</Link>.
        </div>
      ) : (
        <div className="request-grid">
          {requests.map((r) => (
            <Link key={r.id} href={`/dashboard/organizer/pedidos/${r.id}`} className="request-card">
              <h3>{r.title}</h3>
              <div className="row">
                <span><span className="material-symbols-outlined">event</span>
                  {new Date(r.start_at).toLocaleDateString("pt-PT", { day: "2-digit", month: "short" })}
                </span>
                <span><span className="material-symbols-outlined">location_on</span>{r.city ?? "—"}</span>
                <span><span className="material-symbols-outlined">group</span>{r.expected_pax}</span>
              </div>
              <div className="row" style={{ justifyContent: "space-between" }}>
                <span className="match-badge">{r.status}</span>
                <span style={{ color: "var(--orange)", fontWeight: 600 }}>Gerir →</span>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
