-- airfnb_24: SECURITY DEFINER RPC that returns per-conversation summary rows
-- (last message preview + unread count) for the caller.
--
-- Why an RPC: the previous implementation pulled every message of every
-- conversation the user is in and counted/picked in JS. For chatty
-- conversations that's an unbounded select that grows linearly with history.
-- This function computes the same in SQL with bounded cost (one row per
-- conversation, two index scans on (conversation_id, created_at)).

create or replace function public.airfnb_conversation_summaries()
returns table (
  conversation_id      uuid,
  last_message_body    text,
  last_message_at      timestamptz,
  last_message_sender  uuid,
  unread_count         int
)
language sql
stable
security definer
set search_path = public
as $$
  with my_parts as (
    select conversation_id, last_read_at
      from public.airfnb_conversation_participants
     where user_id = auth.uid()
  )
  select
    mp.conversation_id,
    (select m.body
       from public.airfnb_messages m
      where m.conversation_id = mp.conversation_id
      order by m.created_at desc
      limit 1) as last_message_body,
    (select m.created_at
       from public.airfnb_messages m
      where m.conversation_id = mp.conversation_id
      order by m.created_at desc
      limit 1) as last_message_at,
    (select m.sender_id
       from public.airfnb_messages m
      where m.conversation_id = mp.conversation_id
      order by m.created_at desc
      limit 1) as last_message_sender,
    (select count(*)::int
       from public.airfnb_messages m
      where m.conversation_id = mp.conversation_id
        and m.sender_id is distinct from auth.uid()
        and (mp.last_read_at is null or m.created_at > mp.last_read_at)
    ) as unread_count
  from my_parts mp;
$$;

revoke execute on function public.airfnb_conversation_summaries() from public, anon;
grant  execute on function public.airfnb_conversation_summaries() to authenticated;
