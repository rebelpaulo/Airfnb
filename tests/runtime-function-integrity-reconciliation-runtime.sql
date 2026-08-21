\set ON_ERROR_STOP on

begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';
set local idle_in_transaction_session_timeout = '60s';

do $catalog_assertions$
declare
  v_owner oid;
begin
  if (
    select count(*)
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'airfnb_generate_referral_code',
         'airfnb_assign_referral_code',
         'airfnb_handle_new_user'
       )
  ) <> 3 then
    raise exception 'runtime proof failed: target overload or function count drift';
  end if;

  if (
    select count(distinct procedure.proowner)
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'airfnb_generate_referral_code',
         'airfnb_assign_referral_code',
         'airfnb_handle_new_user'
       )
  ) <> 1 then
    raise exception 'runtime proof failed: target owners differ';
  end if;

  select procedure.proowner
    into v_owner
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
   where namespace.nspname = 'public'
     and procedure.proname = 'airfnb_generate_referral_code';

  if exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
      cross join lateral pg_catalog.aclexplode(
        coalesce(
          procedure.proacl,
          pg_catalog.acldefault('f', procedure.proowner)
        )
      ) as privilege
     where namespace.nspname = 'public'
       and procedure.proname in (
         'airfnb_generate_referral_code',
         'airfnb_assign_referral_code',
         'airfnb_handle_new_user'
       )
       and (
         privilege.grantor <> procedure.proowner
         or privilege.grantee <> procedure.proowner
         or privilege.privilege_type <> 'EXECUTE'
         or privilege.is_grantable
       )
  ) or exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
      cross join pg_catalog.pg_roles as api_role
     where namespace.nspname = 'public'
       and procedure.proname in (
         'airfnb_generate_referral_code',
         'airfnb_assign_referral_code',
         'airfnb_handle_new_user'
       )
       and api_role.rolname in ('anon', 'authenticated', 'service_role')
       and pg_catalog.has_function_privilege(api_role.oid, procedure.oid, 'EXECUTE')
  ) then
    raise exception 'runtime proof failed: unexpected direct execute privilege';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'airfnb_generate_referral_code',
         'airfnb_assign_referral_code',
         'airfnb_handle_new_user'
       )
       and (
         procedure.proowner <> v_owner
         or procedure.proconfig <> array['search_path=pg_catalog, public']::text[]
       )
  ) then
    raise exception 'runtime proof failed: owner or search_path postcondition drift';
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_trigger as trigger_row
      join pg_catalog.pg_class as relation on relation.oid = trigger_row.tgrelid
      join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
     where namespace.nspname = 'public'
       and relation.relname = 'airfnb_profiles'
       and trigger_row.tgname = 'airfnb_profile_referral_code'
       and trigger_row.tgenabled = 'O'
       and trigger_row.tgtype = 7
  ) or not exists (
    select 1
      from pg_catalog.pg_trigger as trigger_row
      join pg_catalog.pg_class as relation on relation.oid = trigger_row.tgrelid
      join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
     where namespace.nspname = 'auth'
       and relation.relname = 'users'
       and trigger_row.tgname = 'airfnb_trg_auth_new_user'
       and trigger_row.tgenabled = 'O'
       and trigger_row.tgtype = 5
  ) then
    raise exception 'runtime proof failed: enabled trigger binding drift';
  end if;
end
$catalog_assertions$;

create schema rfi_hostile;

create function rfi_hostile.upper(text)
returns text
language plpgsql
as $hostile$
begin
  raise exception 'hostile upper shadow executed';
end
$hostile$;

create function rfi_hostile.substr(text, integer, integer)
returns text
language plpgsql
as $hostile$
begin
  raise exception 'hostile substr shadow executed';
end
$hostile$;

create function rfi_hostile.encode(bytea, text)
returns text
language plpgsql
as $hostile$
begin
  raise exception 'hostile encode shadow executed';
end
$hostile$;

create function rfi_hostile.regexp_replace(text, text, text, text)
returns text
language plpgsql
as $hostile$
begin
  raise exception 'hostile regexp_replace shadow executed';
end
$hostile$;

create table rfi_hostile.airfnb_profiles (referral_code text);
insert into rfi_hostile.airfnb_profiles values ('HOSTILE1');

alter table auth.users disable trigger airfnb_trg_auth_new_user;
insert into auth.users (id, email, raw_user_meta_data)
values (
  'f1000000-0000-4000-8000-000000000001',
  'rfi-profile-path@example.invalid',
  '{}'::jsonb
);
alter table auth.users enable trigger airfnb_trg_auth_new_user;

set local search_path = rfi_hostile, public, pg_catalog;
insert into public.airfnb_profiles (id, full_name, locale)
values (
  'f1000000-0000-4000-8000-000000000001',
  'Profile Path',
  'pt-PT'
);
set local search_path = pg_catalog, public;

do $profile_path_assertion$
begin
  if not exists (
    select 1
      from public.airfnb_profiles
     where id = 'f1000000-0000-4000-8000-000000000001'
       and referral_code is not null
       and pg_catalog.length(referral_code) = 8
  ) then
    raise exception 'runtime proof failed: hostile-path profile trigger chain';
  end if;
end
$profile_path_assertion$;

insert into auth.users (id, email, raw_user_meta_data)
values (
  'f1000000-0000-4000-8000-000000000002',
  'rfi-referrer@example.invalid',
  '{"full_name":"Signup Referrer","locale":"en-GB"}'::jsonb
);

insert into auth.users (id, email, raw_user_meta_data)
values (
  'f1000000-0000-4000-8000-000000000003',
  'rfi-referee@example.invalid',
  '{"full_name":"Signup Referee"}'::jsonb
);

do $signup_path_assertion$
begin
  if not exists (
    select 1
      from public.airfnb_profiles
     where id = 'f1000000-0000-4000-8000-000000000002'
       and full_name = 'Signup Referrer'
       and locale = 'en-GB'
       and referral_code is not null
       and referred_by is null
       and referrals_count = 0
  ) or not exists (
    select 1
      from public.airfnb_profiles
     where id = 'f1000000-0000-4000-8000-000000000003'
       and full_name = 'Signup Referee'
       and locale = 'pt-PT'
       and referral_code is not null
       and referred_by is null
       and referrals_count = 0
  ) then
    raise exception 'runtime proof failed: signup handler behavior changed';
  end if;
end
$signup_path_assertion$;

select referral_code as rfi_referrer_code
  from public.airfnb_profiles
 where id = 'f1000000-0000-4000-8000-000000000002'
\gset

select pg_catalog.set_config(
  'request.jwt.claim.sub',
  'f1000000-0000-4000-8000-000000000003',
  true
);
set local role authenticated;
select public.airfnb_apply_referral(:'rfi_referrer_code');
reset role;

do $referral_path_assertion$
begin
  if not exists (
    select 1
      from public.airfnb_profiles
     where id = 'f1000000-0000-4000-8000-000000000003'
       and referred_by = 'f1000000-0000-4000-8000-000000000002'
  ) or not exists (
    select 1
      from public.airfnb_profiles
     where id = 'f1000000-0000-4000-8000-000000000002'
       and referrals_count = 1
  ) then
    raise exception 'runtime proof failed: legitimate referral attribution path';
  end if;
end
$referral_path_assertion$;

alter table auth.users disable trigger airfnb_trg_auth_new_user;
insert into auth.users (id, email, raw_user_meta_data)
values (
  'f1000000-0000-4000-8000-000000000004',
  'rfi-retry@example.invalid',
  '{}'::jsonb
);
alter table auth.users enable trigger airfnb_trg_auth_new_user;

insert into public.airfnb_profiles (id, full_name, referral_code)
values (
  'f1000000-0000-4000-8000-000000000004',
  'Retry Collision',
  'QUFBQUFB'
);

create temporary table rfi_rng_state (
  calls integer not null,
  mode text not null
) on commit drop;
insert into rfi_rng_state values (0, 'eleventh_unique');

create or replace function extensions.gen_random_bytes(integer)
returns bytea
language plpgsql
volatile
set search_path = pg_catalog, pg_temp
as $mock_rng$
declare
  v_call integer;
begin
  update pg_temp.rfi_rng_state
     set calls = calls + 1
  returning calls into v_call;

  if (select mode from pg_temp.rfi_rng_state) = 'eleventh_unique'
     and v_call > 10 then
    return pg_catalog.decode(pg_catalog.repeat('42', $1), 'hex');
  end if;

  return pg_catalog.decode(pg_catalog.repeat('41', $1), 'hex');
end
$mock_rng$;

do $eleventh_attempt_assertion$
declare
  v_code text;
  v_calls integer;
begin
  v_code := public.airfnb_generate_referral_code();
  select calls into v_calls from pg_temp.rfi_rng_state;

  if v_calls <> 11 or v_code <> 'QKJCQKJC' then
    raise exception 'runtime proof failed: historical eleventh-attempt success boundary';
  end if;
end
$eleventh_attempt_assertion$;

update pg_temp.rfi_rng_state set calls = 0, mode = 'always_collide';

do $error_contract_assertion$
declare
  v_message text;
  v_state text;
begin
  begin
    perform public.airfnb_generate_referral_code();
    raise exception 'runtime proof failed: collision exhaustion unexpectedly succeeded';
  exception
    when others then
      get stacked diagnostics
        v_message = message_text,
        v_state = returned_sqlstate;
  end;

  if v_state <> 'P0001'
     or v_message <> 'could not generate unique referral code' then
    raise exception 'runtime proof failed: historical collision error contract';
  end if;
end
$error_contract_assertion$;

rollback;
