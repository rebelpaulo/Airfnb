-- Fix: messages RLS policies had a tautological self-join.
--
-- Before: `cp.conversation_id = cp.conversation_id` (always TRUE), so the
-- EXISTS subquery only checked whether the *current user* participates in
-- *any* conversation — not the conversation of the row being read/inserted.
-- Net effect: any authenticated user with at least one conversation could
-- read every message in the database, and send into any conversation.
--
-- After: the join is anchored to `airfnb_messages.conversation_id`, so the
-- EXISTS only matches participation rows for *this* conversation.
--
-- Defence in depth: also add a column-level check on INSERT that sender_id
-- equals auth.uid() (already in WITH CHECK, kept here for clarity).

drop policy if exists airfnb_msg_read on public.airfnb_messages;
create policy airfnb_msg_read on public.airfnb_messages
  for select
  using (
    exists (
      select 1
        from public.airfnb_conversation_participants cp
       where cp.conversation_id = airfnb_messages.conversation_id
         and cp.user_id = auth.uid()
    )
    or public.airfnb_is_admin()
  );

drop policy if exists airfnb_msg_send on public.airfnb_messages;
create policy airfnb_msg_send on public.airfnb_messages
  for insert
  with check (
    sender_id = auth.uid()
    and exists (
      select 1
        from public.airfnb_conversation_participants cp
       where cp.conversation_id = airfnb_messages.conversation_id
         and cp.user_id = auth.uid()
    )
  );
