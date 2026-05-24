-- airfnb_23: SECURITY DEFINER RPC to resolve the OTHER participant + their
-- display name for every conversation the caller is in.
--
-- Why we can't just SELECT from airfnb_conversation_participants + profiles:
--   the existing RLS policy `airfnb_cp_self` only lets a user see their own
--   participant row, and `airfnb_profile_self` only their own profile. So a
--   plain join in the /dashboard/conversas page returns empty for every
--   non-admin user.
--
-- We could broaden those policies, but then any participant in any conversation
-- would gain read access to peer profile data globally. A focused RPC keeps
-- the surface tight: returns just (conversation_id, user_id, display_name,
-- email) for the OTHER participants in conversations the caller is in.

create or replace function public.airfnb_conversation_peers()
returns table (
  conversation_id uuid,
  user_id         uuid,
  display_name    text
)
language sql
stable
security definer
set search_path = public
as $$
  select cp_other.conversation_id,
         cp_other.user_id,
         pr.display_name
    from public.airfnb_conversation_participants cp_self
    join public.airfnb_conversation_participants cp_other
      on cp_other.conversation_id = cp_self.conversation_id
     and cp_other.user_id <> cp_self.user_id
    join public.airfnb_profiles pr
      on pr.id = cp_other.user_id
   where cp_self.user_id = auth.uid()
$$;

revoke execute on function public.airfnb_conversation_peers() from public, anon;
grant  execute on function public.airfnb_conversation_peers() to authenticated;
