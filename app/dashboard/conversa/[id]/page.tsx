import { notFound, redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { ChatClient } from "./ChatClient";

export default async function ConversaPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect(`/login?next=/dashboard/conversa/${id}`);

  const { data: conv } = await supa
    .from("airfnb_conversations")
    .select(`id, booking_id, application_id`)
    .eq("id", id)
    .maybeSingle();
  if (!conv) notFound();

  const { data: msgsData } = await supa
    .from("airfnb_messages")
    .select(`id, body, sender_id, created_at`)
    .eq("conversation_id", id)
    .order("created_at", { ascending: true })
    .limit(200);
  const messages = msgsData ?? [];

  // Mark the conversation as read for this user. Without this, the unread
  // badge on /dashboard/conversas would never clear (it's computed from
  // last_read_at vs message timestamps). Best-effort: a failure shouldn't
  // block rendering the chat.
  await (supa as any)
    .from("airfnb_conversation_participants")
    .update({ last_read_at: new Date().toISOString() })
    .eq("conversation_id", id)
    .eq("user_id", user.id);

  return <ChatClient conversationId={id} initialMessages={messages} currentUserId={user.id} />;
}
