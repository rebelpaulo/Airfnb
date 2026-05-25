import Link from "next/link";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { WrongAccountType } from "@/components/WrongAccountType";
import { getDictionary, getLocale } from "@/lib/i18n";

export default async function OrganizerDashboard() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/organizer");

  // Roles are exclusive — a truck owner landing here would see an empty
  // organizer dashboard with no recovery path. Block early. Treat a
  // lookup error as deny-by-default: better to render the block-page
  // than to silently let a possibly-wrong-role user through.
  const { data: profile, error: profileError } = await (supa as any)
    .from("airfnb_profiles")
    .select("role")
    .eq("id", user.id)
    .maybeSingle();
  if (profileError || profile?.role === "owner") {
    return <WrongAccountType intent="organize_event" currentRole="owner" />;
  }

  const { data: requestsData } = await (supa as any)
    .from("airfnb_event_requests")
    .select("id, title, status, start_at, city, expected_pax")
    .eq("organizer_id", user.id)
    .order("created_at", { ascending: false });
  const requests = requestsData ?? [];

  const open = requests.filter((r: any) => r.status === "open" || r.status === "reviewing").length;
  const awarded = requests.filter((r: any) => r.status === "awarded").length;
  const total = requests.length;

  const dict = await getDictionary();
  const locale = await getLocale();
  const t = dict.dashboard.organizer;
  const statusMap = dict.vocab.request_status as Record<string, string>;
  const dateLocale = locale === "pt" ? "pt-PT" : "en-GB";

  return (
    <div className="dash">
      <h1>{t.heading}</h1>
      <div className="stat-strip">
        <div className="stat"><div className="label">{t.stat_total}</div><div className="value">{total}</div></div>
        <div className="stat"><div className="label">{t.stat_open}</div><div className="value">{open}</div></div>
        <div className="stat"><div className="label">{t.stat_awarded}</div><div className="value">{awarded}</div></div>
        <div className="stat"><div className="label">{t.stat_next_action}</div><div className="value" style={{ fontSize: 18 }}>
          <Link href="/publicar" style={{ color: "var(--orange)" }}>{t.publish_new}</Link>
        </div></div>
      </div>

      {requests.length === 0 ? (
        <div className="empty">
          {t.empty_pre}<Link href="/publicar" style={{ color: "var(--orange)" }}>{t.empty_link}</Link>{t.empty_post}
        </div>
      ) : (
        <div className="request-grid">
          {requests.map((r: any) => (
            <Link key={r.id} href={`/dashboard/organizer/pedidos/${r.id}`} className="request-card">
              <h3>{r.title}</h3>
              <div className="row">
                <span><span className="material-symbols-outlined">event</span>
                  {new Date(r.start_at).toLocaleDateString(dateLocale, { day: "2-digit", month: "short" })}
                </span>
                <span><span className="material-symbols-outlined">location_on</span>{r.city ?? t.city_dash}</span>
                <span><span className="material-symbols-outlined">group</span>{r.expected_pax}</span>
              </div>
              <div className="row" style={{ justifyContent: "space-between" }}>
                <span className="match-badge">{statusMap[r.status] ?? r.status}</span>
                <span style={{ color: "var(--orange)", fontWeight: 600 }}>{t.manage_cta}</span>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
