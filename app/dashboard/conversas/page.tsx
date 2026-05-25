import Link from "next/link";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { getDictionary, getLocale } from "@/lib/i18n";

export const dynamic = "force-dynamic";

type ConvRow = {
  conversation_id: string;
  booking_id: string | null;
  application_id: string | null;
  last_read_at: string | null;
  request_title: string | null;
  start_at: string | null;
  city: string | null;
  other_name: string | null;
  last_message_body: string | null;
  last_message_at: string | null;
  last_message_sender: string | null;
  unread_count: number;
};

export default async function ConversasPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/conversas");

  const dict = await getDictionary();
  const t = dict.dashboard.shared_conversations;
  const locale = await getLocale();
  const dateLocale = locale === "en" ? "en-US" : "pt-PT";

  // Pull every conversation the user participates in, plus the metadata we
  // need for each row (last message preview, unread count, the "other side"
  // display name, and the request/event the conversation is anchored to).
  // We could turn this into a single SQL view; for now an inline JS join
  // keeps it readable and is fast enough for ≤ ~50 conversations per user.
  const { data: partsData } = await (supa as any)
    .from("airfnb_conversation_participants")
    .select("conversation_id, last_read_at")
    .eq("user_id", user.id);
  const parts = (partsData as any[]) ?? [];

  if (parts.length === 0) {
    return (
      <div className="dash">
        <h1>{t.title}</h1>
        <div className="empty">
          {t.empty}
        </div>
      </div>
    );
  }

  const convIds = parts.map((p) => p.conversation_id);
  const lastReadByConv = new Map<string, string | null>(
    parts.map((p) => [p.conversation_id, p.last_read_at]),
  );

  // Two SECURITY DEFINER RPCs do the heavy lifting:
  //   airfnb_conversation_peers()     → (conv_id, user_id, display_name)
  //   airfnb_conversation_summaries() → (conv_id, last_message_*, unread_count)
  // The summaries RPC bounds the cost — earlier we pulled the entire message
  // history of every conversation just to find the last + count unread, which
  // scales linearly with history per CodeRabbit's "unbounded select" finding.
  const [convsRes, peersRes, summariesRes] = await Promise.all([
    (supa as any).from("airfnb_conversations")
      .select(`id, booking_id, application_id,
               airfnb_applications ( id,
                 airfnb_event_requests ( title, start_at, city, organizer_id ),
                 airfnb_trucks ( name, owner_id ) )`)
      .in("id", convIds),
    (supa as any).rpc("airfnb_conversation_peers"),
    (supa as any).rpc("airfnb_conversation_summaries"),
  ]);

  const convs = (convsRes.data as any[]) ?? [];
  const peers = (peersRes.data as any[]) ?? [];
  const summaries = (summariesRes.data as any[]) ?? [];

  const summaryByConv = new Map<string, any>();
  for (const s of summaries) summaryByConv.set(s.conversation_id, s);

  const otherNameByConv = new Map<string, string>();
  for (const p of peers) {
    otherNameByConv.set(p.conversation_id, p.display_name ?? "—");
  }

  const rows: ConvRow[] = convs.map((c) => {
    const s = summaryByConv.get(c.id);
    const app  = c.airfnb_applications;
    return {
      conversation_id:    c.id,
      booking_id:         c.booking_id,
      application_id:     c.application_id,
      last_read_at:       lastReadByConv.get(c.id) ?? null,
      request_title:      app?.airfnb_event_requests?.title ?? null,
      start_at:           app?.airfnb_event_requests?.start_at ?? null,
      city:               app?.airfnb_event_requests?.city ?? null,
      other_name:         otherNameByConv.get(c.id) ?? "—",
      last_message_body:  s?.last_message_body ?? null,
      last_message_at:    s?.last_message_at ?? null,
      last_message_sender: s?.last_message_sender ?? null,
      unread_count:       s?.unread_count ?? 0,
    };
  }).sort((a, b) => (b.last_message_at ?? "").localeCompare(a.last_message_at ?? ""));

  return (
    <div className="dash" style={{ maxWidth: 780 }}>
      <h1 style={{ margin: 0 }}>{t.title}</h1>
      <p style={{ color: "var(--muted)", marginTop: 6 }}>
        {t.subtitle}
      </p>

      <ul style={{ listStyle: "none", padding: 0, marginTop: 18, display: "grid", gap: 8 }}>
        {rows.map((r) => (
          <li key={r.conversation_id}>
            <Link
              href={`/dashboard/conversa/${r.conversation_id}`}
              style={{
                display: "grid", gridTemplateColumns: "1fr auto", gap: 12,
                padding: 14, border: "1px solid var(--line)", borderRadius: 12, background: "#fff",
                textDecoration: "none", color: "var(--ink)",
              }}
            >
              <div style={{ minWidth: 0 }}>
                <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
                  <strong style={{ fontSize: 15 }}>{r.other_name}</strong>
                  {r.unread_count > 0 && (
                    <span style={{ background: "var(--orange)", color: "#fff", padding: "1px 8px", borderRadius: 999, fontSize: 11, fontWeight: 700 }}>
                      {r.unread_count}
                    </span>
                  )}
                </div>
                <div style={{ fontSize: 13, color: "var(--muted)", marginTop: 2 }}>
                  {r.request_title ?? t.no_event}
                  {r.start_at && ` · ${new Date(r.start_at).toLocaleDateString(dateLocale, { day: "2-digit", month: "short" })}`}
                  {r.city && ` · ${r.city}`}
                </div>
                <div style={{
                  fontSize: 13, marginTop: 6,
                  color: r.unread_count > 0 ? "var(--ink)" : "var(--muted)",
                  fontWeight: r.unread_count > 0 ? 600 : 400,
                  whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis",
                }}>
                  {r.last_message_body ?? t.no_messages}
                </div>
              </div>
              <div style={{ fontSize: 11, color: "var(--muted)", alignSelf: "start" }}>
                {r.last_message_at && new Date(r.last_message_at).toLocaleString(dateLocale, { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" })}
              </div>
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
