import Link from "next/link";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";

export default async function NotificacoesPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/notificacoes");

  const { data: notifData } = await supa
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
    await supa.from("airfnb_notifications").update({ read_at: new Date().toISOString() }).eq("id", id);
    revalidatePath("/dashboard/notificacoes");
  }

  return (
    <div className="dash">
      <h1>Notificações</h1>
      {notifications.length === 0 ? (
        <div className="empty">Sem notificações por aqui ainda.</div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
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
    case "application.accepted": return "🎉 A tua candidatura foi aceite!";
    case "application.rejected": return "Candidatura não selecionada.";
    case "booking.confirmed":    return "Reserva confirmada.";
    case "booking.cancelled":    return "Reserva cancelada.";
    default: return kind;
  }
}
