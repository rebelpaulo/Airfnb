import Link from "next/link";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";

export default async function NotificacoesPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/notificacoes");

  const { data: notifData } = await (supa as any)
    .from("airfnb_notifications")
    .select("*")
    .eq("user_id", user.id)
    .order("created_at", { ascending: false })
    .limit(40);
  const notifications = notifData ?? [];

  async function markRead(formData: FormData) {
    "use server";
    const id = String(formData.get("id"));
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error("auth required");
    const { error } = await (supa as any)
      .from("airfnb_notifications")
      .update({ read_at: new Date().toISOString() })
      .eq("id", id)
      .eq("user_id", user.id);     // belt + suspenders: RLS already enforces this
    if (error) throw new Error(error.message);
    revalidatePath("/dashboard/notificacoes");
  }

  async function markAllRead() {
    "use server";
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error("auth required");
    const { error } = await (supa as any)
      .from("airfnb_notifications")
      .update({ read_at: new Date().toISOString() })
      .eq("user_id", user.id)
      .is("read_at", null);
    if (error) throw new Error(error.message);
    revalidatePath("/dashboard/notificacoes");
  }

  const unreadCount = notifications.filter((n: any) => !n.read_at).length;

  return (
    <div className="dash">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: 12 }}>
        <h1 style={{ margin: 0 }}>Notificações</h1>
        {unreadCount > 0 && (
          <form action={markAllRead}>
            <button type="submit" className="btn-pill outline"
                    style={{ padding: "8px 18px", borderColor: "var(--teal)", color: "var(--teal)" }}>
              Marcar todas lidas ({unreadCount})
            </button>
          </form>
        )}
      </div>
      {notifications.length === 0 ? (
        <div className="empty" style={{ marginTop: 16 }}>Sem notificações por aqui ainda.</div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 10, marginTop: 16 }}>
          {notifications.map((n: any) => {
            const isAccepted = n.kind === "application.accepted";
            return (
              <div key={n.id} className="request-card" style={{ borderLeftColor: n.read_at ? "var(--line)" : "var(--orange)" }}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
                  <div>
                    <strong>{labelFor(n.kind)}</strong>
                    <div style={{ fontSize: 13, color: "var(--muted)" }}>
                      {new Date(n.created_at).toLocaleString("pt-PT")}
                    </div>
                  </div>
                  {!n.read_at && (
                    <form action={markRead}>
                      <input type="hidden" name="id" value={n.id} />
                      <button type="submit" className="btn-pill outline" style={{ padding: "6px 14px", fontSize: 12, borderColor: "var(--teal)", color: "var(--teal)" }}>
                        Marcar lida
                      </button>
                    </form>
                  )}
                </div>
                {isAccepted && n.payload?.application_id && (
                  <Link href={`/dashboard/truck/lock/${n.payload.application_id}`} className="btn-pill" style={{ marginTop: 10, padding: "8px 18px" }}>
                    Pagar lock-fee €{n.payload.total} →
                  </Link>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

function labelFor(kind: string) {
  switch (kind) {
    case "application.received":     return "Nova candidatura ao teu evento.";
    case "application.shortlisted":  return "A tua candidatura está em shortlist.";
    case "application.accepted":     return "🎉 A tua candidatura foi aceite!";
    case "application.rejected":     return "Candidatura não selecionada.";
    case "booking.confirmed":        return "Reserva confirmada.";
    case "booking.cancelled":        return "Reserva cancelada.";
    default: return kind;
  }
}
