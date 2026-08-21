-- Remove the historical, publicly-known demo authentication identity while
-- keeping its public catalogue/editorial content, and close the profile-role
-- self-promotion boundary exposed by the original all-column self RLS policy.

create or replace function public.airfnb_guard_profile_role()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_actor uuid := auth.uid();
  v_actor_is_privileged boolean := false;
  v_retired_seed constant uuid := '11111111-1111-1111-1111-111111111111';
begin
  -- A previously-issued JWT for the deleted demo user can remain valid until
  -- expiry. Never let that fixed identity recreate its database profile.
  if new.id = v_retired_seed then
    raise exception using
      errcode = '42501',
      message = 'retired demo identity cannot create or update a profile';
  end if;

  -- Ordinary field edits and the supported organizer <-> owner transition do
  -- not touch a privileged role and remain on the existing RLS path.
  if tg_op = 'UPDATE' and new.role is not distinct from old.role then
    return new;
  end if;

  if new.role not in ('admin'::public.airfnb_user_role, 'staff'::public.airfnb_user_role) then
    return new;
  end if;

  -- Internal trigger/service operations have no end-user subject. When there
  -- is a subject, only an already-trusted admin/staff profile may assign a
  -- privileged role. The lookup is database-backed, never user_metadata.
  if v_actor is null then
    return new;
  end if;

  select exists (
    select 1
      from public.airfnb_profiles p
     where p.id = v_actor
       and p.role in ('admin'::public.airfnb_user_role, 'staff'::public.airfnb_user_role)
  ) into v_actor_is_privileged;

  if not v_actor_is_privileged then
    raise exception using
      errcode = '42501',
      message = 'only an existing admin or staff member can assign a privileged role';
  end if;

  return new;
end
$function$;

revoke all on function public.airfnb_guard_profile_role() from public, anon, authenticated;

drop trigger if exists airfnb_profiles_guard_role on public.airfnb_profiles;
create trigger airfnb_profiles_guard_role
  before insert or update on public.airfnb_profiles
  for each row execute function public.airfnb_guard_profile_role();

do $migration$
declare
  v_seed_id constant uuid := '11111111-1111-1111-1111-111111111111';
  v_seed_email constant text := 'seed@airfnb.local';
  v_seed_exists boolean;
begin
  -- Serialize against either representation, then fail closed if this fixed
  -- UUID/email pair has drifted onto any other identity.
  lock table auth.users in share row exclusive mode;

  perform 1
    from auth.users u
   where u.id = v_seed_id
      or lower(u.email) = lower(v_seed_email)
   for update;

  if exists (
    select 1
      from auth.users u
     where u.id = v_seed_id
       and u.email is distinct from v_seed_email
  ) then
    raise exception 'refusing demo cleanup: seed UUID has an unexpected email';
  end if;

  if exists (
    select 1
      from auth.users u
     where lower(u.email) = lower(v_seed_email)
       and (u.id <> v_seed_id or u.email is distinct from v_seed_email)
  ) then
    raise exception 'refusing demo cleanup: seed email belongs to an unexpected identity';
  end if;

  select exists (
    select 1
      from auth.users u
     where u.id = v_seed_id
       and u.email = v_seed_email
  ) into v_seed_exists;

  if not v_seed_exists then
    -- A second run is valid only after the first run detached every retained
    -- catalogue/editorial reference and removed the profile.
    if exists (select 1 from public.airfnb_profiles where id = v_seed_id)
       or exists (select 1 from public.airfnb_trucks where owner_id = v_seed_id)
       or exists (select 1 from public.airfnb_blog_authors where id = v_seed_id)
       or exists (select 1 from public.airfnb_blog_posts where author_id = v_seed_id) then
      raise exception 'refusing demo cleanup: orphaned seed references remain without the exact auth identity';
    end if;
    return;
  end if;

  -- Preserve the public content, but remove every ownership/authorisation
  -- edge to the retired identity before deleting its auth user.
  update public.airfnb_trucks
     set owner_id = null
   where owner_id = v_seed_id;

  update public.airfnb_blog_posts
     set author_id = null
   where author_id = v_seed_id;

  -- Detach nullable audit/history references that otherwise use NO ACTION.
  update public.airfnb_bookings set organizer_id = null where organizer_id = v_seed_id;
  update public.airfnb_messages set sender_id = null where sender_id = v_seed_id;
  update public.airfnb_reviews set organizer_id = null where organizer_id = v_seed_id;
  update public.airfnb_proposals set prepared_by = null where prepared_by = v_seed_id;
  update public.airfnb_contact_requests set handled_by = null where handled_by = v_seed_id;
  update public.airfnb_request_invitations set invited_by = null where invited_by = v_seed_id;
  delete from public.airfnb_conversation_participants where user_id = v_seed_id;

  -- auth-owned sessions, refresh tokens and identities follow the auth.users
  -- deletion through Supabase's auth-schema foreign keys. The profile then
  -- cascades, while the retained trucks/posts are already detached above.
  delete from auth.users
   where id = v_seed_id
     and email = v_seed_email;

  if not found then
    raise exception 'refusing demo cleanup: exact seed identity disappeared during cleanup';
  end if;

  if exists (select 1 from public.airfnb_profiles where id = v_seed_id) then
    raise exception 'demo profile still exists after auth identity deletion';
  end if;
end
$migration$;
