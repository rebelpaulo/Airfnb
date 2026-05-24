"use client";
import { useEffect, useRef, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";

type Msg = { id: string; body: string | null; sender_id: string | null; created_at: string };

export function ChatClient({
  conversationId,
  initialMessages,
  currentUserId,
}: {
  conversationId: string;
  initialMessages: Msg[];
  currentUserId: string;
}) {
  const [messages, setMessages] = useState<Msg[]>(initialMessages);
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const endRef = useRef<HTMLDivElement>(null);
  const supa = supabaseBrowser();

  useEffect(() => {
    const ch = supa
      .channel(`conv:${conversationId}`)
      .on("postgres_changes",
        { event: "INSERT", schema: "public", table: "airfnb_messages", filter: `conversation_id=eq.${conversationId}` },
        (p) => {
          const incoming = p.new as Msg;
          // Realtime can fire before/after our optimistic insert. De-dupe on id.
          setMessages((m) => (m.some((x) => x.id === incoming.id) ? m : [...m, incoming]));
        })
      .subscribe();
    return () => {
      // Always close the channel; ignore errors to avoid noisy console on unmount.
      supa.removeChannel(ch).catch(() => undefined);
    };
  // supa is a stable client instance — depending on it would cause double-subscribe
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [conversationId]);

  useEffect(() => { endRef.current?.scrollIntoView({ behavior: "smooth" }); }, [messages.length]);

  async function send(e: React.FormEvent) {
    e.preventDefault();
    if (!text.trim()) return;
    setBusy(true);
    const body = text.trim();
    setText("");
    const { error } = await (supa as any).from("airfnb_messages").insert({
      conversation_id: conversationId,
      sender_id: currentUserId,
      body,
    });
    setBusy(false);
    if (error) alert(error.message);
  }

  return (
    <div className="dash" style={{ maxWidth: 780 }}>
      <h1>Conversa</h1>
      <div style={{
        background:"#fff", border:"1px solid var(--line)", borderRadius:14, padding:20,
        minHeight:400, maxHeight:520, overflowY:"auto", display:"flex", flexDirection:"column", gap:10,
      }}>
        {messages.length === 0 ? (
          <div style={{ color: "var(--muted)", textAlign: "center", margin: "auto" }}>
            Nenhuma mensagem ainda. Sê o primeiro.
          </div>
        ) : messages.map((m) => {
          const mine = m.sender_id === currentUserId;
          return (
            <div key={m.id} style={{ alignSelf: mine ? "flex-end" : "flex-start", maxWidth: "70%" }}>
              <div style={{
                background: mine ? "var(--orange)" : "#F2F2F2",
                color: mine ? "#fff" : "var(--ink)",
                padding: "10px 14px",
                borderRadius: 14,
                fontSize: 14,
                lineHeight: 1.45,
              }}>{m.body}</div>
              <div style={{ fontSize: 11, color: "var(--muted)", marginTop: 2, textAlign: mine ? "right" : "left" }}>
                {new Date(m.created_at).toLocaleTimeString("pt-PT", { hour: "2-digit", minute: "2-digit" })}
              </div>
            </div>
          );
        })}
        <div ref={endRef} />
      </div>
      <form onSubmit={send} style={{ display: "flex", gap: 10, marginTop: 14 }}>
        <input value={text} onChange={(e) => setText(e.target.value)}
          placeholder="Escreve a tua mensagem..."
          className="filters-btn" style={{ flex: 1, padding: "12px 16px" }} />
        <button className="btn-pill" type="submit" disabled={busy}>Enviar</button>
      </form>
    </div>
  );
}
