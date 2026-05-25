import Link from "next/link";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { getDictionary, getLocale } from "@/lib/i18n";
import type { Dictionary } from "@/lib/i18n";

function format(template: string, vars: Record<string, string | number>): string {
  return template.replace(/\{(\w+)\}/g, (_, k) => String(vars[k] ?? `{${k}}`));
}

export default async function NotificacoesPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/notificacoes");

  const dict = await getDictionary();
  const t = dict.dashboard.shared_notifications;
  const locale = await getLocale();
  const dateLocale = locale === "en" ? "en-US" : "pt-PT";

  const { data: notifData } = await (supa as any)
    .from("airfnb_notifications")
    .select("*")
    .eq("user_id", user.id)
    .order("created_at", { ascending: false })
    .limit(40);
  const notifications = notifData ?? [];

  async function markRead(formData: FormData) {
    "use server";
    const dict = await getDictionary();
    const t = dict.dashboard.shared_notifications;
    const id = String(formData.get("id"));
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error(t.err_auth);
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
    const dict = await getDictionary();
    const t = dict.dashboard.shared_notifications;
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error(t.err_auth);
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
        <h1 style={{ margin: 0 }}>{t.title}</h1>
        {unreadCount > 0 && (
          <form action={markAllRead}>
            <button type="submit" className="btn-pill outline"
                    style={{ padding: "8px 18px", borderColor: "var(--teal)", color: "var(--teal)" }}>
              {format(t.mark_all_read, { count: unreadCount })}
            </button>
          </form>
        )}
      </div>
      {notifications.length === 0 ? (
        <div className="empty" style={{ marginTop: 16 }}>{t.empty}</div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 10, marginTop: 16 }}>
          {notifications.map((n: any) => {
            const isAccepted = n.kind === "application.accepted";
            return (
              <div key={n.id} className="request-card" style={{ borderLeftColor: n.read_at ? "var(--line)" : "var(--orange)" }}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
                  <div>
                    <strong>{labelFor(n.kind, dict)}</strong>
                    <div style={{ fontSize: 13, color: "var(--muted)" }}>
                      {new Date(n.created_at).toLocaleString(dateLocale)}
                    </div>
                  </div>
                  {!n.read_at && (
                    <form action={markRead}>
                      <input type="hidden" name="id" value={n.id} />
                      <button type="submit" className="btn-pill outline" style={{ padding: "6px 14px", fontSize: 12, borderColor: "var(--teal)", color: "var(--teal)" }}>
                        {t.mark_read}
                      </button>
                    </form>
                  )}
                </div>
                {isAccepted && n.payload?.application_id && (
                  <Link href={`/dashboard/truck/lock/${n.payload.application_id}`} className="btn-pill" style={{ marginTop: 10, padding: "8px 18px" }}>
                    {format(t.pay_lock_cta, { total: n.payload.total })}
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

function labelFor(kind: string, dict: Dictionary) {
  const t = dict.dashboard.shared_notifications;
  switch (kind) {
    case "application.received":     return t.notif_application_received;
    case "application.shortlisted":  return t.notif_application_shortlisted;
    case "application.accepted":     return t.notif_application_accepted;
    case "application.rejected":     return t.notif_application_rejected;
    case "booking.confirmed":        return t.notif_booking_confirmed;
    case "booking.cancelled":        return t.notif_booking_cancelled;
    default: return kind;
  }
}
