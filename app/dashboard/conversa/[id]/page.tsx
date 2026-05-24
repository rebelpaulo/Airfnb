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

  return <ChatClient conversationId={id} initialMessages={messages} currentUserId={user.id} />;
}
