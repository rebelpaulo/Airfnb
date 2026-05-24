import Link from "next/link";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";

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
        <h1>Conversas</h1>
        <div className="empty">
          Ainda não tens nenhuma conversa. Vão aparecer aqui quando uma candidatura
          for aceite ou um pedido for atribuído.
        </div>
      </div>
    );
  }

  const convIds = parts.map((p) => p.conversation_id);
  const lastReadByConv = new Map<string, string | null>(
    parts.map((p) => [p.conversation_id, p.last_read_at]),
  );

  // peers come from a SECURITY DEFINER RPC because RLS on
  // airfnb_conversation_participants only lets a user see their OWN row —
  // a plain join would return empty for every non-admin user. The RPC
  // narrowly returns just (conversation_id, user_id, display_name) for
  // conversations the caller is in.
  const [convsRes, msgsRes, peersRes] = await Promise.all([
    (supa as any).from("airfnb_conversations")
      .select(`id, booking_id, application_id,
               airfnb_applications ( id,
                 airfnb_event_requests ( title, start_at, city, organizer_id ),
                 airfnb_trucks ( name, owner_id ) )`)
      .in("id", convIds),
    (supa as any).from("airfnb_messages")
      .select("conversation_id, body, sender_id, created_at")
      .in("conversation_id", convIds)
      .order("created_at", { ascending: false }),
    (supa as any).rpc("airfnb_conversation_peers"),
  ]);

  const convs = (convsRes.data as any[]) ?? [];
  const allMsgs = (msgsRes.data as any[]) ?? [];
  const peers = (peersRes.data as any[]) ?? [];

  const lastMsgByConv = new Map<string, any>();
  const unreadByConv = new Map<string, number>();
  for (const m of allMsgs) {
    if (!lastMsgByConv.has(m.conversation_id)) lastMsgByConv.set(m.conversation_id, m);
    const lastRead = lastReadByConv.get(m.conversation_id);
    if (m.sender_id !== user.id && (!lastRead || m.created_at > lastRead)) {
      unreadByConv.set(m.conversation_id, (unreadByConv.get(m.conversation_id) ?? 0) + 1);
    }
  }

  const otherNameByConv = new Map<string, string>();
  for (const p of peers) {
    otherNameByConv.set(p.conversation_id, p.display_name ?? "—");
  }

  const rows: ConvRow[] = convs.map((c) => {
    const last = lastMsgByConv.get(c.id);
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
      last_message_body:  last?.body ?? null,
      last_message_at:    last?.created_at ?? null,
      last_message_sender: last?.sender_id ?? null,
      unread_count:       unreadByConv.get(c.id) ?? 0,
    };
  }).sort((a, b) => (b.last_message_at ?? "").localeCompare(a.last_message_at ?? ""));

  return (
    <div className="dash" style={{ maxWidth: 780 }}>
      <h1 style={{ margin: 0 }}>Conversas</h1>
      <p style={{ color: "var(--muted)", marginTop: 6 }}>
        Conversa diretamente com o organizador ou truck de cada candidatura aceite.
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
                  {r.request_title ?? "Sem evento associado"}
                  {r.start_at && ` · ${new Date(r.start_at).toLocaleDateString("pt-PT", { day: "2-digit", month: "short" })}`}
                  {r.city && ` · ${r.city}`}
                </div>
                <div style={{
                  fontSize: 13, marginTop: 6,
                  color: r.unread_count > 0 ? "var(--ink)" : "var(--muted)",
                  fontWeight: r.unread_count > 0 ? 600 : 400,
                  whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis",
                }}>
                  {r.last_message_body ?? "Sem mensagens ainda."}
                </div>
              </div>
              <div style={{ fontSize: 11, color: "var(--muted)", alignSelf: "start" }}>
                {r.last_message_at && new Date(r.last_message_at).toLocaleString("pt-PT", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" })}
              </div>
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
