-- Remove the F&B-wide auth.users side effect before sharing the Auth tenant.
-- Membership is actor-scoped and a dedicated tombstone permanently prevents
-- a deleted F&B identity from re-onboarding without deleting auth.users.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';
set local idle_in_transaction_session_timeout = '60s';

do $preconditions$
declare
  v_owner oid;
  v_role_not_null boolean;
  v_role_default text;
  v_tombstone_exists boolean := false;
  v_predecessor boolean := false;
  v_final boolean := false;
begin
  if (select count(*) from pg_catalog.pg_roles
       where rolname in ('anon', 'authenticated', 'service_role')) <> 3
     or pg_catalog.to_regclass('auth.users') is null
     or pg_catalog.to_regclass('public.airfnb_profiles') is null
     or pg_catalog.to_regtype('public.airfnb_user_role') is null then
    raise exception 'shared auth boundary refused: required schema or API roles are missing';
  end if;

  select relation.relowner into v_owner
    from pg_catalog.pg_class as relation
   where relation.oid = 'public.airfnb_profiles'::pg_catalog.regclass;

  if not exists (
    select 1 from pg_catalog.pg_roles as owner_role
     where owner_role.oid = v_owner
       and owner_role.rolbypassrls
       and owner_role.rolname not in ('anon', 'authenticated', 'service_role')
  ) then
    raise exception 'shared auth boundary refused: profile owner is not trusted';
  end if;

  select attribute.attnotnull,
         pg_catalog.pg_get_expr(default_value.adbin, default_value.adrelid)
    into v_role_not_null, v_role_default
    from pg_catalog.pg_attribute as attribute
    left join pg_catalog.pg_attrdef as default_value
      on default_value.adrelid = attribute.attrelid
     and default_value.adnum = attribute.attnum
   where attribute.attrelid = 'public.airfnb_profiles'::pg_catalog.regclass
     and attribute.attname = 'role'
     and attribute.attnum > 0
     and not attribute.attisdropped
     and attribute.atttypid = 'public.airfnb_user_role'::pg_catalog.regtype;

  v_tombstone_exists := pg_catalog.to_regclass('public.airfnb_membership_tombstones') is not null;

  v_predecessor := not v_tombstone_exists
    and coalesce(v_role_not_null, false)
    and v_role_default = '''organizer''::airfnb_user_role'
    and pg_catalog.to_regprocedure('public.airfnb_handle_new_user()') is not null
    and pg_catalog.to_regprocedure('public.airfnb_ensure_profile(text,text)') is null
    and pg_catalog.to_regprocedure('public.airfnb_claim_role(public.airfnb_user_role)') is null
    and pg_catalog.to_regprocedure('public.airfnb_self_delete_storage_prefixes()') is null
    and exists (
      select 1 from pg_catalog.pg_proc as procedure
       where procedure.oid = pg_catalog.to_regprocedure('public.airfnb_handle_new_user()')
         and procedure.proowner = v_owner
         and procedure.prosecdef
         and procedure.provolatile = 'v'
         and procedure.proconfig in (
           array['search_path=public']::text[],
           array['search_path=pg_catalog, public']::text[]
         )
         and pg_catalog.md5(procedure.prosrc) = 'e197b8a69dc5eee06f572f0136f918dc'
    )
    and exists (
      select 1 from pg_catalog.pg_trigger as trigger_row
       where trigger_row.tgrelid = 'auth.users'::pg_catalog.regclass
         and trigger_row.tgname = 'airfnb_trg_auth_new_user'
         and not trigger_row.tgisinternal
         and trigger_row.tgenabled = 'O'
         and trigger_row.tgtype = 5
         and trigger_row.tgfoid = pg_catalog.to_regprocedure('public.airfnb_handle_new_user()')
    )
    and exists (
      select 1 from pg_catalog.pg_proc as procedure
       where procedure.oid = pg_catalog.to_regprocedure('public.airfnb_guard_profile_role()')
         and procedure.proowner = v_owner
         and procedure.prosecdef
         and procedure.provolatile = 'v'
         and procedure.proconfig = array['search_path=pg_catalog, public']::text[]
         and pg_catalog.md5(procedure.prosrc) = 'ebd2f85a1bacb5eceaca6a1c3cec5731'
    )
    and exists (
      select 1 from pg_catalog.pg_proc as procedure
       where procedure.oid = pg_catalog.to_regprocedure('public.airfnb_apply_referral(text)')
         and procedure.proowner = v_owner
         and procedure.prosecdef
         and procedure.provolatile = 'v'
         and procedure.proconfig = array['search_path=public']::text[]
         and pg_catalog.md5(procedure.prosrc) = '8c282e85f135c61bebfa770aba12dead'
    )
    and exists (
      select 1 from pg_catalog.pg_proc as procedure
       where procedure.oid = pg_catalog.to_regprocedure('public.airfnb_self_delete()')
         and procedure.proowner = v_owner
         and procedure.prosecdef
         and procedure.provolatile = 'v'
         and procedure.proconfig = array['search_path=public']::text[]
         and pg_catalog.md5(procedure.prosrc) = '3263d4bfe0026701f234172dfc4d66a3'
    )
    and exists (
      select 1 from pg_catalog.pg_trigger as trigger_row
       where trigger_row.tgrelid = 'public.airfnb_profiles'::pg_catalog.regclass
         and trigger_row.tgname = 'airfnb_profiles_guard_role'
         and not trigger_row.tgisinternal
         and trigger_row.tgenabled = 'O'
         and trigger_row.tgtype = 23
         and trigger_row.tgfoid = pg_catalog.to_regprocedure('public.airfnb_guard_profile_role()')
    );

  v_final := v_tombstone_exists
    and not coalesce(v_role_not_null, true)
    and v_role_default is null
    and pg_catalog.to_regprocedure('public.airfnb_handle_new_user()') is null
    and pg_catalog.to_regprocedure('public.airfnb_ensure_profile(text,text)') is not null
    and pg_catalog.to_regprocedure('public.airfnb_claim_role(public.airfnb_user_role)') is not null
    and pg_catalog.to_regprocedure('public.airfnb_apply_referral(text)') is not null
    and pg_catalog.to_regprocedure('public.airfnb_self_delete()') is not null
    and pg_catalog.to_regprocedure('public.airfnb_self_delete_storage_prefixes()') is not null
    and not exists (
      select 1 from pg_catalog.pg_trigger
       where tgrelid = 'auth.users'::pg_catalog.regclass
         and tgname = 'airfnb_trg_auth_new_user'
         and not tgisinternal
    )
    and exists (
      select 1 from pg_catalog.pg_proc as procedure
       where procedure.oid = pg_catalog.to_regprocedure('public.airfnb_ensure_profile(text,text)')
         and procedure.proowner = v_owner and procedure.prosecdef and procedure.provolatile = 'v'
         and procedure.proconfig = array['search_path=""']::text[]
         and pg_catalog.md5(procedure.prosrc) = '9b03c272bb453651123bac3a77a9f938'
    )
    and exists (
      select 1 from pg_catalog.pg_proc as procedure
       where procedure.oid = pg_catalog.to_regprocedure('public.airfnb_claim_role(public.airfnb_user_role)')
         and procedure.proowner = v_owner and procedure.prosecdef and procedure.provolatile = 'v'
         and procedure.proconfig = array['search_path=""']::text[]
         and pg_catalog.md5(procedure.prosrc) = '2755fff7e06bdad768d499ff6305c10f'
    )
    and exists (
      select 1 from pg_catalog.pg_proc as procedure
       where procedure.oid = pg_catalog.to_regprocedure('public.airfnb_apply_referral(text)')
         and procedure.proowner = v_owner and procedure.prosecdef and procedure.provolatile = 'v'
         and procedure.proconfig = array['search_path=""']::text[]
         and pg_catalog.md5(procedure.prosrc) = 'db8fec4890616074250a98f9d8b35d6d'
    )
    and exists (
      select 1 from pg_catalog.pg_proc as procedure
       where procedure.oid = pg_catalog.to_regprocedure('public.airfnb_self_delete()')
         and procedure.proowner = v_owner and procedure.prosecdef and procedure.provolatile = 'v'
         and procedure.proconfig = array['search_path=""']::text[]
         and pg_catalog.md5(procedure.prosrc) = '8d2849ef2dc3fbfbc59c6d6d7fe2aeaf'
    )
    and exists (
      select 1 from pg_catalog.pg_proc as procedure
       where procedure.oid = pg_catalog.to_regprocedure('public.airfnb_self_delete_storage_prefixes()')
         and procedure.proowner = v_owner and procedure.prosecdef and procedure.provolatile = 'v'
         and procedure.proconfig = array['search_path=""']::text[]
         and pg_catalog.md5(procedure.prosrc) = 'ff72982e6ade07065de6d385f79997a1'
    )
    and exists (
      select 1 from pg_catalog.pg_proc as procedure
       where procedure.oid = pg_catalog.to_regprocedure('public.airfnb_guard_profile_role()')
         and procedure.proowner = v_owner and not procedure.prosecdef and procedure.provolatile = 'v'
         and procedure.proconfig = array['search_path=pg_catalog, public']::text[]
         and pg_catalog.md5(procedure.prosrc) = '30225c87def1bebf86c9a443ffead831'
    );

  if not v_predecessor and not v_final then
    raise exception 'shared auth boundary refused: predecessor or final state drifted';
  end if;
end
$preconditions$;

lock table public.airfnb_profiles in share row exclusive mode;
lock table auth.users in share row exclusive mode;

drop trigger if exists airfnb_trg_auth_new_user on auth.users;
drop function if exists public.airfnb_handle_new_user();

alter table public.airfnb_profiles alter column role drop default;
alter table public.airfnb_profiles alter column role drop not null;

create table if not exists public.airfnb_membership_tombstones (
  user_id uuid primary key,
  deleted_at timestamptz not null default pg_catalog.statement_timestamp(),
  storage_truck_ids uuid[] not null default '{}'::uuid[]
);
alter table public.airfnb_membership_tombstones owner to current_user;
alter table public.airfnb_membership_tombstones enable row level security;
revoke all on table public.airfnb_membership_tombstones from public, anon, authenticated, service_role;

-- A deleted shared Auth identity can still hold valid sessions in another
-- Tailor product. Require a live F&B profile on every user-owned Storage
-- operation so those sessions cannot recreate media after the tombstone is
-- committed. Public reads remain unchanged until the trusted API has removed
-- the underlying objects.
alter policy airfnb_avatars_owner_insert on storage.objects
  with check (
    bucket_id = 'airfnb-avatars'
    and auth.uid() is not null
    and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
    and split_part(name, '/', 1) = auth.uid()::text
    and exists (select 1 from public.airfnb_profiles where id = auth.uid())
  );
alter policy airfnb_avatars_owner_update on storage.objects
  using (
    bucket_id = 'airfnb-avatars'
    and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
    and split_part(name, '/', 1) = auth.uid()::text
    and exists (select 1 from public.airfnb_profiles where id = auth.uid())
  )
  with check (
    bucket_id = 'airfnb-avatars'
    and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
    and split_part(name, '/', 1) = auth.uid()::text
    and exists (select 1 from public.airfnb_profiles where id = auth.uid())
  );
alter policy airfnb_avatars_owner_delete on storage.objects
  using (
    bucket_id = 'airfnb-avatars'
    and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
    and split_part(name, '/', 1) = auth.uid()::text
    and exists (select 1 from public.airfnb_profiles where id = auth.uid())
  );

alter policy airfnb_truck_images_owner_insert on storage.objects
  with check (
    bucket_id = 'airfnb-truck-images'
    and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
    and exists (select 1 from public.airfnb_profiles where id = auth.uid())
    and public.airfnb_can_manage_truck(split_part(name, '/', 1))
  );
alter policy airfnb_truck_images_owner_update on storage.objects
  using (
    bucket_id = 'airfnb-truck-images'
    and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
    and exists (select 1 from public.airfnb_profiles where id = auth.uid())
    and public.airfnb_can_manage_truck(split_part(name, '/', 1))
  )
  with check (
    bucket_id = 'airfnb-truck-images'
    and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
    and exists (select 1 from public.airfnb_profiles where id = auth.uid())
    and public.airfnb_can_manage_truck(split_part(name, '/', 1))
  );
alter policy airfnb_truck_images_owner_delete on storage.objects
  using (
    bucket_id = 'airfnb-truck-images'
    and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
    and exists (select 1 from public.airfnb_profiles where id = auth.uid())
    and public.airfnb_can_manage_truck(split_part(name, '/', 1))
  );

alter policy airfnb_documents_owner_read on storage.objects
  using (
    bucket_id = 'airfnb-documents'
    and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
    and exists (select 1 from public.airfnb_profiles where id = auth.uid())
    and public.airfnb_can_manage_truck(split_part(name, '/', 1))
  );
alter policy airfnb_documents_owner_insert on storage.objects
  with check (
    bucket_id = 'airfnb-documents'
    and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
    and exists (select 1 from public.airfnb_profiles where id = auth.uid())
    and public.airfnb_can_manage_truck(split_part(name, '/', 1))
  );
alter policy airfnb_documents_owner_update on storage.objects
  using (
    bucket_id = 'airfnb-documents'
    and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
    and exists (select 1 from public.airfnb_profiles where id = auth.uid())
    and public.airfnb_can_manage_truck(split_part(name, '/', 1))
  )
  with check (
    bucket_id = 'airfnb-documents'
    and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
    and exists (select 1 from public.airfnb_profiles where id = auth.uid())
    and public.airfnb_can_manage_truck(split_part(name, '/', 1))
  );
alter policy airfnb_documents_owner_delete on storage.objects
  using (
    bucket_id = 'airfnb-documents'
    and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
    and exists (select 1 from public.airfnb_profiles where id = auth.uid())
    and public.airfnb_can_manage_truck(split_part(name, '/', 1))
  );

create or replace function public.airfnb_guard_profile_role()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
declare
  v_actor uuid := auth.uid();
  v_actor_is_privileged boolean := false;
  v_caller_is_owner boolean := false;
  v_retired_seed constant uuid := '11111111-1111-1111-1111-111111111111';
begin
  if new.id = v_retired_seed then
    raise exception using errcode = '42501',
      message = 'retired demo identity cannot create or update a profile';
  end if;

  if current_user = 'authenticated' and tg_op = 'INSERT' then
    raise exception using errcode = '42501',
      message = 'direct profile insertion is forbidden; use airfnb_ensure_profile';
  end if;
  if current_user = 'authenticated' and tg_op = 'UPDATE' and (
       new.role is distinct from old.role
       or new.organizer_rating_avg is distinct from old.organizer_rating_avg
       or new.organizer_rating_count is distinct from old.organizer_rating_count
       or new.referral_code is distinct from old.referral_code
       or new.referred_by is distinct from old.referred_by
       or new.referrals_count is distinct from old.referrals_count
  ) then
    raise exception using errcode = '42501',
      message = 'server-maintained profile fields require a trusted RPC';
  end if;

  select relation.relowner = current_user::pg_catalog.regrole
    into v_caller_is_owner
    from pg_catalog.pg_class as relation
   where relation.oid = tg_relid;
  if v_caller_is_owner then
    return new;
  end if;

  if tg_op = 'UPDATE' and new.role is not distinct from old.role then
    return new;
  end if;
  if tg_op = 'INSERT' and new.role is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.role is null and new.role in (
    'organizer'::public.airfnb_user_role,
    'owner'::public.airfnb_user_role
  ) then
    return new;
  end if;

  if v_actor is null then
    return new;
  end if;

  select exists (
    select 1 from public.airfnb_profiles as profile
     where profile.id = v_actor
       and profile.role in ('admin'::public.airfnb_user_role, 'staff'::public.airfnb_user_role)
  ) into v_actor_is_privileged;

  if not v_actor_is_privileged then
    raise exception using errcode = '42501',
      message = 'profile role transitions require an existing admin or staff member';
  end if;
  return new;
end
$function$;

alter function public.airfnb_guard_profile_role() owner to current_user;
revoke all on function public.airfnb_guard_profile_role() from public, anon, authenticated, service_role;

create or replace function public.airfnb_ensure_profile(
  p_full_name text default null,
  p_locale text default 'pt-PT'
)
returns public.airfnb_profiles
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_name text := case when p_full_name is null then null else pg_catalog.btrim(p_full_name) end;
  v_profile public.airfnb_profiles;
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;
  if p_full_name is not null and (pg_catalog.char_length(v_name) < 2 or pg_catalog.char_length(v_name) > 120) then
    raise exception using errcode = '22023', message = 'full name must contain between 2 and 120 characters';
  end if;
  if p_locale is null or p_locale not in ('pt-PT', 'en') then
    raise exception using errcode = '22023', message = 'unsupported locale';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(1095122502, pg_catalog.hashtext(v_actor::text));
  if exists (
    select 1 from public.airfnb_membership_tombstones as tombstone
     where tombstone.user_id = v_actor
  ) then
    raise exception using errcode = '42501', message = 'F&B membership was deleted';
  end if;

  insert into public.airfnb_profiles (id, role, full_name, locale)
  values (v_actor, null, v_name, p_locale)
  on conflict (id) do nothing;

  select profile.* into strict v_profile
    from public.airfnb_profiles as profile
   where profile.id = v_actor;
  return v_profile;
end
$function$;

create or replace function public.airfnb_claim_role(
  p_role public.airfnb_user_role
)
returns public.airfnb_profiles
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_profile public.airfnb_profiles;
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;
  if p_role is null or p_role not in (
    'organizer'::public.airfnb_user_role,
    'owner'::public.airfnb_user_role
  ) then
    raise exception using errcode = '42501', message = 'role is not self-claimable';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(1095122502, pg_catalog.hashtext(v_actor::text));
  if exists (
    select 1 from public.airfnb_membership_tombstones as tombstone
     where tombstone.user_id = v_actor
  ) then
    raise exception using errcode = '42501', message = 'F&B membership was deleted';
  end if;

  select profile.* into v_profile
    from public.airfnb_profiles as profile
   where profile.id = v_actor
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'F&B profile does not exist';
  end if;
  if v_profile.role is null then
    update public.airfnb_profiles set role = p_role where id = v_actor returning * into strict v_profile;
  elsif v_profile.role is distinct from p_role then
    raise exception using errcode = '42501', message = 'profile role cannot be changed after claim';
  end if;
  return v_profile;
end
$function$;

create or replace function public.airfnb_apply_referral(p_code text)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_code text := pg_catalog.upper(pg_catalog.btrim(coalesce(p_code, '')));
  v_referrer uuid;
  v_updated integer;
begin
  if v_actor is null or pg_catalog.length(v_code) < 6 then
    return false;
  end if;

  if exists (
    select 1 from public.airfnb_membership_tombstones as tombstone
     where tombstone.user_id = v_actor
  ) then
    return false;
  end if;

  select profile.id into v_referrer
    from public.airfnb_profiles as profile
   where profile.referral_code = v_code
     and profile.id <> v_actor
     and not exists (
       select 1 from public.airfnb_membership_tombstones as tombstone
        where tombstone.user_id = profile.id
     );
  if v_referrer is null then
    return false;
  end if;

  perform profile.id
    from public.airfnb_profiles as profile
   where profile.id in (v_actor, v_referrer)
   order by profile.id
   for update;
  if exists (
    select 1 from public.airfnb_membership_tombstones as tombstone
     where tombstone.user_id in (v_actor, v_referrer)
  ) then
    return false;
  end if;

  update public.airfnb_profiles
     set referred_by = v_referrer
   where id = v_actor and referred_by is null;
  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    return false;
  end if;

  update public.airfnb_profiles
     set referrals_count = referrals_count + 1
   where id = v_referrer;
  if not found then
    raise exception 'referrer disappeared during attribution';
  end if;
  return true;
end
$function$;

create or replace function public.airfnb_self_delete()
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_truck record;
  v_has_bookings boolean;
  v_storage_truck_ids uuid[] := '{}'::uuid[];
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(1095122502, pg_catalog.hashtext(v_actor::text));
  if exists (
    select 1 from public.airfnb_membership_tombstones as tombstone
     where tombstone.user_id = v_actor
  ) then
    if exists (select 1 from public.airfnb_profiles where id = v_actor) then
      raise exception 'F&B membership tombstone/profile state is inconsistent';
    end if;
    select storage_truck_ids into strict v_storage_truck_ids
      from public.airfnb_membership_tombstones
     where user_id = v_actor;
    return;
  end if;

  perform 1 from public.airfnb_profiles as profile
   where profile.id = v_actor
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'F&B profile does not exist';
  end if;

  select coalesce(pg_catalog.array_agg(id order by id), '{}'::uuid[])
    into v_storage_truck_ids
    from public.airfnb_trucks
   where owner_id = v_actor;

  insert into public.airfnb_membership_tombstones (user_id, storage_truck_ids)
  values (v_actor, v_storage_truck_ids);

  update public.airfnb_profiles set
    full_name = null,
    display_name = null,
    phone = null,
    vat_number = null,
    avatar_url = null,
    company_name = null,
    address_line = null,
    billing_address_line = null
  where id = v_actor;

  update public.airfnb_blog_posts set author_id = null
   where author_id = v_actor;

  for v_truck in
    select id from public.airfnb_trucks where owner_id = v_actor
  loop
    select exists (
      select 1 from public.airfnb_booking_trucks as booking_truck
       where booking_truck.truck_id = v_truck.id
    ) into v_has_bookings;

    if v_has_bookings then
      update public.airfnb_trucks set
        name = '[Truck removido]',
        slug = 'removed-' || id::text,
        description = null,
        base_city = null,
        status = 'archived'
      where id = v_truck.id;
    else
      delete from public.airfnb_trucks where id = v_truck.id;
    end if;
  end loop;

  update public.airfnb_bookings set organizer_id = null where organizer_id = v_actor;
  update public.airfnb_messages set sender_id = null where sender_id = v_actor;
  update public.airfnb_reviews set organizer_id = null where organizer_id = v_actor;
  update public.airfnb_proposals set prepared_by = null where prepared_by = v_actor;
  update public.airfnb_contact_requests set handled_by = null where handled_by = v_actor;
  update public.airfnb_request_invitations set invited_by = null where invited_by = v_actor;
  update public.airfnb_partner_leads set handled_by = null where handled_by = v_actor;
  update public.airfnb_platform_settings set updated_by = null where updated_by = v_actor;

  delete from public.airfnb_organizer_reviews where organizer_id = v_actor;
  delete from public.airfnb_event_requests where organizer_id = v_actor;
  delete from public.airfnb_events where organizer_id = v_actor;
  delete from public.airfnb_conversation_participants where user_id = v_actor;
  delete from public.airfnb_notifications where user_id = v_actor;
  delete from public.airfnb_favorites where user_id = v_actor;
  delete from public.airfnb_profiles where id = v_actor;

  if not exists (
    select 1 from public.airfnb_membership_tombstones where user_id = v_actor
  ) or exists (
    select 1 from public.airfnb_profiles where id = v_actor
  ) or not exists (
    select 1 from auth.users where id = v_actor
  ) then
    raise exception 'F&B membership deletion postcondition failed';
  end if;
end
$function$;

create or replace function public.airfnb_self_delete_storage_prefixes()
returns uuid[]
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_storage_truck_ids uuid[];
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;

  select storage_truck_ids into v_storage_truck_ids
    from public.airfnb_membership_tombstones
   where user_id = v_actor;
  if not found then
    raise exception using errcode = 'P0002', message = 'F&B membership deletion is not initialized';
  end if;
  return v_storage_truck_ids;
end
$function$;

alter function public.airfnb_ensure_profile(text,text) owner to current_user;
alter function public.airfnb_claim_role(public.airfnb_user_role) owner to current_user;
alter function public.airfnb_apply_referral(text) owner to current_user;
alter function public.airfnb_self_delete() owner to current_user;
alter function public.airfnb_self_delete_storage_prefixes() owner to current_user;
revoke all on function public.airfnb_ensure_profile(text,text) from public, anon, authenticated, service_role;
revoke all on function public.airfnb_claim_role(public.airfnb_user_role) from public, anon, authenticated, service_role;
revoke all on function public.airfnb_apply_referral(text) from public, anon, authenticated, service_role;
revoke all on function public.airfnb_self_delete() from public, anon, authenticated, service_role;
revoke all on function public.airfnb_self_delete_storage_prefixes() from public, anon, authenticated, service_role;
grant execute on function public.airfnb_ensure_profile(text,text) to authenticated;
grant execute on function public.airfnb_claim_role(public.airfnb_user_role) to authenticated;
grant execute on function public.airfnb_apply_referral(text) to authenticated;
grant execute on function public.airfnb_self_delete() to authenticated;
grant execute on function public.airfnb_self_delete_storage_prefixes() to authenticated;

revoke all on table public.airfnb_profiles from public, anon;
revoke insert, update, delete on table public.airfnb_profiles from authenticated;
revoke update (
  id, role, organizer_rating_avg, organizer_rating_count, referral_code,
  referred_by, referrals_count, created_at, updated_at
) on table public.airfnb_profiles from authenticated;
grant select on table public.airfnb_profiles to authenticated;
grant update (
  full_name, display_name, phone, avatar_url, locale, vat_number, company_name,
  marketing_opt_in, onboarding_completed, address_line, billing_address_line
) on table public.airfnb_profiles to authenticated;

do $postconditions$
declare
  v_owner oid := (select relowner from pg_catalog.pg_class where oid = 'public.airfnb_profiles'::regclass);
  v_function oid;
begin
  if exists (
    select 1 from pg_catalog.pg_trigger
     where tgrelid = 'auth.users'::pg_catalog.regclass
       and tgname = 'airfnb_trg_auth_new_user'
       and not tgisinternal
  ) or pg_catalog.to_regprocedure('public.airfnb_handle_new_user()') is not null then
    raise exception 'shared auth boundary failed: global signup hook remains';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_attribute as attribute
    left join pg_catalog.pg_attrdef as default_value
      on default_value.adrelid = attribute.attrelid and default_value.adnum = attribute.attnum
    where attribute.attrelid = 'public.airfnb_profiles'::pg_catalog.regclass
      and attribute.attname = 'role' and not attribute.attnotnull and default_value.oid is null
  ) then
    raise exception 'shared auth boundary failed: profile role is not nullable without default';
  end if;

  foreach v_function in array array[
    'public.airfnb_ensure_profile(text,text)'::pg_catalog.regprocedure::oid,
    'public.airfnb_claim_role(public.airfnb_user_role)'::pg_catalog.regprocedure::oid,
    'public.airfnb_apply_referral(text)'::pg_catalog.regprocedure::oid,
    'public.airfnb_self_delete()'::pg_catalog.regprocedure::oid,
    'public.airfnb_self_delete_storage_prefixes()'::pg_catalog.regprocedure::oid
  ] loop
    if not exists (
      select 1 from pg_catalog.pg_proc as procedure
       where procedure.oid = v_function
         and procedure.proowner = v_owner
         and procedure.prosecdef
         and procedure.provolatile = 'v'
         and procedure.proconfig = array['search_path=""']::text[]
         and pg_catalog.md5(procedure.prosrc) = case procedure.proname
           when 'airfnb_ensure_profile' then '9b03c272bb453651123bac3a77a9f938'
           when 'airfnb_claim_role' then '2755fff7e06bdad768d499ff6305c10f'
           when 'airfnb_apply_referral' then 'db8fec4890616074250a98f9d8b35d6d'
           when 'airfnb_self_delete' then '8d2849ef2dc3fbfbc59c6d6d7fe2aeaf'
           else 'ff72982e6ade07065de6d385f79997a1'
         end
    ) or exists (
      select 1
        from pg_catalog.aclexplode((select proacl from pg_catalog.pg_proc where oid = v_function)) as privilege
       where privilege.grantor <> v_owner
          or privilege.grantee not in (v_owner, 'authenticated'::pg_catalog.regrole::oid)
          or privilege.privilege_type <> 'EXECUTE'
          or privilege.is_grantable
    ) or not pg_catalog.has_function_privilege('authenticated', v_function, 'EXECUTE')
      or pg_catalog.has_function_privilege('anon', v_function, 'EXECUTE')
      or pg_catalog.has_function_privilege('service_role', v_function, 'EXECUTE') then
      raise exception 'shared auth boundary failed: RPC definition or ACL drifted';
    end if;
  end loop;

  if not exists (
    select 1 from pg_catalog.pg_proc as procedure
     where procedure.oid = 'public.airfnb_guard_profile_role()'::pg_catalog.regprocedure
       and procedure.proowner = v_owner and not procedure.prosecdef and procedure.provolatile = 'v'
       and procedure.proconfig = array['search_path=pg_catalog, public']::text[]
       and pg_catalog.md5(procedure.prosrc) = '30225c87def1bebf86c9a443ffead831'
  ) or not exists (
    select 1 from pg_catalog.pg_trigger as trigger_row
     where trigger_row.tgrelid = 'public.airfnb_profiles'::pg_catalog.regclass
       and trigger_row.tgname = 'airfnb_profiles_guard_role'
       and not trigger_row.tgisinternal and trigger_row.tgenabled = 'O'
       and trigger_row.tgtype = 23
       and trigger_row.tgfoid = 'public.airfnb_guard_profile_role()'::pg_catalog.regprocedure
  ) then
    raise exception 'shared auth boundary failed: profile guard drifted';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_class as relation
     where relation.oid = 'public.airfnb_membership_tombstones'::pg_catalog.regclass
       and relation.relowner = v_owner
       and relation.relrowsecurity
  ) or exists (
    select 1 from pg_catalog.pg_policies
     where schemaname = 'public' and tablename = 'airfnb_membership_tombstones'
  ) or pg_catalog.has_table_privilege('anon', 'public.airfnb_membership_tombstones', 'SELECT')
    or pg_catalog.has_table_privilege('authenticated', 'public.airfnb_membership_tombstones', 'SELECT')
    or pg_catalog.has_table_privilege('service_role', 'public.airfnb_membership_tombstones', 'SELECT')
    or not exists (
      select 1 from pg_catalog.pg_attribute as attribute
       where attribute.attrelid = 'public.airfnb_membership_tombstones'::pg_catalog.regclass
         and attribute.attname = 'storage_truck_ids'
         and attribute.atttypid = 'uuid[]'::pg_catalog.regtype
         and attribute.attnotnull
         and not attribute.attisdropped
    ) then
    raise exception 'shared auth boundary failed: tombstone relation or ACL drifted';
  end if;

  if pg_catalog.has_table_privilege('authenticated', 'public.airfnb_profiles', 'INSERT')
    or pg_catalog.has_table_privilege('authenticated', 'public.airfnb_profiles', 'UPDATE')
    or pg_catalog.has_table_privilege('authenticated', 'public.airfnb_profiles', 'DELETE')
    or not pg_catalog.has_table_privilege('authenticated', 'public.airfnb_profiles', 'SELECT')
    or pg_catalog.has_column_privilege('authenticated', 'public.airfnb_profiles', 'role', 'UPDATE')
    or pg_catalog.has_column_privilege('authenticated', 'public.airfnb_profiles', 'organizer_rating_avg', 'UPDATE')
    or pg_catalog.has_column_privilege('authenticated', 'public.airfnb_profiles', 'organizer_rating_count', 'UPDATE')
    or pg_catalog.has_column_privilege('authenticated', 'public.airfnb_profiles', 'referral_code', 'UPDATE')
    or pg_catalog.has_column_privilege('authenticated', 'public.airfnb_profiles', 'referred_by', 'UPDATE')
    or pg_catalog.has_column_privilege('authenticated', 'public.airfnb_profiles', 'referrals_count', 'UPDATE')
    or not pg_catalog.has_column_privilege('authenticated', 'public.airfnb_profiles', 'full_name', 'UPDATE')
    or not pg_catalog.has_column_privilege('authenticated', 'public.airfnb_profiles', 'avatar_url', 'UPDATE') then
    raise exception 'shared auth boundary failed: profile column ACL drifted';
  end if;
end
$postconditions$;

commit;
