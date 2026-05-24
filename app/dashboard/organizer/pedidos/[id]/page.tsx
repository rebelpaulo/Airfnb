import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { money } from "@/lib/money";

export default async function ManageRequestPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect(`/login?next=/dashboard/organizer/pedidos/${id}`);

  const { data: req } = await (supa as any)
    .from("airfnb_event_requests")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (!req) notFound();
  if (req.organizer_id !== user.id) redirect("/dashboard/organizer");

  const { data: applicationsData } = await (supa as any)
    .from("airfnb_applications")
    .select(`
      id, status, proposed_price, cover_message, deal_type,
      proposed_fixed_to_organizer, proposed_revenue_share_pct, created_at,
      airfnb_trucks ( id, name, slug, base_city, rating_avg, rating_count )
    `)
    .eq("request_id", id)
    .order("created_at", { ascending: false });
  const applications = applicationsData ?? [];

  // Map applications → conversations so accepted apps deep-link straight
  // into the chat without a separate round-trip per card.
  const appIds = applications.map((a: any) => a.id);
  const { data: convs } = appIds.length
    ? await (supa as any).from("airfnb_conversations").select("id, application_id").in("application_id", appIds)
    : { data: [] };
  const convByApp = new Map<string, string>(((convs as any[]) ?? []).map((c) => [c.application_id, c.id]));

  async function shortlist(formData: FormData) {
    "use server";
    const aid = String(formData.get("application_id"));
    const supa = await supabaseServer();
    await (supa as any).rpc("airfnb_shortlist_application" as any, { p_application: aid });
    revalidatePath(`/dashboard/organizer/pedidos/${id}`);
  }
  async function accept(formData: FormData) {
    "use server";
    const aid = String(formData.get("application_id"));
    const supa = await supabaseServer();
    const { error } = await (supa as any).rpc("airfnb_accept_application" as any, { p_application: aid });
    if (error) throw new Error(error.message);
    revalidatePath(`/dashboard/organizer/pedidos/${id}`);
  }
  async function reject(formData: FormData) {
    "use server";
    const aid = String(formData.get("application_id"));
    const reason = String(formData.get("reason") ?? "");
    const supa = await supabaseServer();
    await (supa as any).rpc("airfnb_reject_application" as any, { p_application: aid, p_reason: reason });
    revalidatePath(`/dashboard/organizer/pedidos/${id}`);
  }

  return (
    <div className="dash">
      <nav className="breadcrumb">
        <Link href="/dashboard/organizer">Dashboard</Link> &nbsp;/&nbsp; <span>{req.title}</span>
      </nav>
      <h1>{req.title}</h1>
      <div className="stat-strip">
        <div className="stat"><div className="label">Estado</div><div className="value" style={{ fontSize: 22 }}>{req.status}</div></div>
        <div className="stat"><div className="label">Quando</div><div className="value" style={{ fontSize: 18 }}>
          {new Date(req.start_at).toLocaleString("pt-PT", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" })}
        </div></div>
        <div className="stat"><div className="label">Slots</div><div className="value">{req.slots_needed}</div></div>
        <div className="stat"><div className="label">Candidaturas</div><div className="value">{applications.length}</div></div>
      </div>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)" }}>Propostas recebidas</h2>

      {applications.length === 0 ? (
        <div className="empty">Ainda sem candidaturas. Os trucks vão receber o teu pedido em minutos.</div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
          {applications.map((a: any) => (
            <div key={a.id} className="request-card" style={{ borderLeftColor:
              a.status === "accepted" ? "#10A37F" : a.status === "rejected" ? "#888" : a.status === "shortlisted" ? "#1F5B65" : "var(--orange)" }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
                <div>
                  <h3>{a.airfnb_trucks?.name ?? "—"}</h3>
                  <div className="row">
                    <span><span className="material-symbols-outlined">location_on</span>{a.airfnb_trucks?.base_city}</span>
                    <span>★ {Number(a.airfnb_trucks?.rating_avg ?? 0).toFixed(1)} ({a.airfnb_trucks?.rating_count ?? 0})</span>
                  </div>
                </div>
                <span className="match-badge">{a.status}</span>
              </div>

              <p style={{ marginTop: 8, fontSize: 14, lineHeight: 1.55 }}>{a.cover_message}</p>

              <div className="row" style={{ gap: 14, fontSize: 13 }}>
                <span><strong>Total esperado:</strong> {money(a.proposed_price)}</span>
                <span><strong>Deal:</strong> {a.deal_type}</span>
                {a.proposed_fixed_to_organizer > 0 && <span><strong>Fixo:</strong> {money(a.proposed_fixed_to_organizer)}</span>}
                {a.proposed_revenue_share_pct > 0 && <span><strong>%:</strong> {a.proposed_revenue_share_pct}%</span>}
              </div>

              {a.status === "accepted" && convByApp.has(a.id) && (
                <div style={{ marginTop: 10 }}>
                  <Link href={`/dashboard/conversa/${convByApp.get(a.id)}`} className="btn-pill outline"
                        style={{ padding: "8px 18px", borderColor: "var(--teal)", color: "var(--teal)", display: "inline-flex", alignItems: "center", gap: 6 }}>
                    <span className="material-symbols-outlined" style={{ fontSize: 16 }}>chat_bubble</span>
                    Abrir conversa
                  </Link>
                </div>
              )}

              {(a.status === "submitted" || a.status === "shortlisted") && (
                <div style={{ display: "flex", gap: 8, marginTop: 8 }}>
                  {a.status === "submitted" && (
                    <form action={shortlist}>
                      <input type="hidden" name="application_id" value={a.id} />
                      <button className="btn-pill outline" type="submit" style={{ padding: "8px 18px" }}>Shortlist</button>
                    </form>
                  )}
                  <form action={accept}>
                    <input type="hidden" name="application_id" value={a.id} />
                    <button className="btn-pill" type="submit" style={{ padding: "8px 18px" }}>Aceitar</button>
                  </form>
                  <form action={reject}>
                    <input type="hidden" name="application_id" value={a.id} />
                    <input type="hidden" name="reason" value="rejected_by_organizer" />
                    <button className="btn-pill" type="submit" style={{ padding: "8px 18px", background: "#888" }}>Rejeitar</button>
                  </form>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
