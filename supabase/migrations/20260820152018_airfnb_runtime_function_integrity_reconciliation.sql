-- Reconcile the three trigger-only runtime functions without changing their
-- business contract. The predecessor is
-- 20260819094823_airfnb_identity_reconciliation.sql.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';
set local idle_in_transaction_session_timeout = '60s';

do $preconditions$
declare
  v_owner oid;
  v_historical_202605 boolean := false;
  v_old_202608_hardening boolean := false;
  v_final_reapplied boolean := false;
begin
  if (
    select count(*)
      from pg_catalog.pg_roles
     where rolname in ('anon', 'authenticated', 'service_role')
  ) <> 3 then
    raise exception 'runtime function integrity refused: required API roles are missing';
  end if;

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
    raise exception 'runtime function integrity refused: missing or overloaded target function';
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
    raise exception 'runtime function integrity refused: target owners differ';
  end if;

  select procedure.proowner
    into v_owner
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
   where namespace.nspname = 'public'
     and procedure.proname = 'airfnb_generate_referral_code';

  if not exists (
    select 1
      from pg_catalog.pg_roles as owner_role
     where owner_role.oid = v_owner
       and owner_role.rolbypassrls
       and owner_role.rolname not in ('anon', 'authenticated', 'service_role')
  ) then
    raise exception 'runtime function integrity refused: owner is not a trusted non-API role';
  end if;

  -- The signup handler is identical in every accepted prestate. Only its
  -- fixed search_path distinguishes final reapplication from both predecessors.
  if not exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
      join pg_catalog.pg_language as language
        on language.oid = procedure.prolang
     where namespace.nspname = 'public'
       and procedure.proname = 'airfnb_handle_new_user'
       and pg_catalog.pg_get_function_identity_arguments(procedure.oid) = ''
       and procedure.prokind = 'f'
       and procedure.prorettype = 'pg_catalog.trigger'::pg_catalog.regtype
       and language.lanname = 'plpgsql'
       and procedure.prosecdef
       and procedure.provolatile = 'v'
       and procedure.proparallel = 'u'
       and not procedure.proisstrict
       and not procedure.proleakproof
       and procedure.proconfig in (
         array['search_path=public']::text[],
         array['search_path=pg_catalog, public']::text[]
       )
       and procedure.prosrc =
$signup_body$
begin
  insert into public.airfnb_profiles (id, full_name, locale)
  values (new.id, new.raw_user_meta_data->>'full_name', coalesce(new.raw_user_meta_data->>'locale','pt-PT'))
  on conflict (id) do nothing;
  return new;
end $signup_body$
  ) then
    raise exception 'runtime function integrity refused: signup definition drifted';
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname = 'airfnb_handle_new_user'
       and procedure.proowner = v_owner
       and procedure.proacl is not null
       and (
         select count(*)
           from pg_catalog.aclexplode(procedure.proacl)
       ) = 1
       and not exists (
         select 1
           from pg_catalog.aclexplode(procedure.proacl) as privilege
          where privilege.grantor <> procedure.proowner
             or privilege.grantee <> procedure.proowner
             or privilege.privilege_type <> 'EXECUTE'
             or privilege.is_grantable
       )
  ) then
    raise exception 'runtime function integrity refused: signup ACL drifted';
  end if;

  -- Accepted prestate 1: the exact 202605 referral definitions. The two new
  -- functions had PostgreSQL's NULL/default ACL (owner and PUBLIC execute),
  -- while the earlier security-fix migration had already reduced the signup
  -- handler to one explicit owner-only EXECUTE entry.
  select
    exists (
      select 1
        from pg_catalog.pg_proc as procedure
        join pg_catalog.pg_namespace as namespace
          on namespace.oid = procedure.pronamespace
        join pg_catalog.pg_language as language
          on language.oid = procedure.prolang
       where namespace.nspname = 'public'
         and procedure.proname = 'airfnb_generate_referral_code'
         and procedure.proowner = v_owner
         and pg_catalog.pg_get_function_identity_arguments(procedure.oid) = ''
         and procedure.prokind = 'f'
         and procedure.prorettype = 'pg_catalog.text'::pg_catalog.regtype
         and language.lanname = 'plpgsql'
         and not procedure.prosecdef
         and procedure.provolatile = 'v'
         and procedure.proparallel = 'u'
         and not procedure.proisstrict
         and not procedure.proleakproof
         and procedure.proconfig is null
         and procedure.proacl is null
         and procedure.prosrc =
$historical_202605_generator$
declare
  v_code text;
  v_attempts int := 0;
begin
  loop
    v_attempts := v_attempts + 1;
    -- Base32 alphabet without 0/O/I/L
    v_code := upper(substr(encode(gen_random_bytes(6), 'base64'), 1, 8));
    v_code := regexp_replace(v_code, '[+/=0OIL]', 'X', 'g');
    exit when not exists (select 1 from public.airfnb_profiles where referral_code = v_code);
    if v_attempts > 10 then raise exception 'could not generate unique referral code'; end if;
  end loop;
  return v_code;
end $historical_202605_generator$
    )
    and exists (
      select 1
        from pg_catalog.pg_proc as procedure
        join pg_catalog.pg_namespace as namespace
          on namespace.oid = procedure.pronamespace
        join pg_catalog.pg_language as language
          on language.oid = procedure.prolang
       where namespace.nspname = 'public'
         and procedure.proname = 'airfnb_assign_referral_code'
         and procedure.proowner = v_owner
         and pg_catalog.pg_get_function_identity_arguments(procedure.oid) = ''
         and procedure.prokind = 'f'
         and procedure.prorettype = 'pg_catalog.trigger'::pg_catalog.regtype
         and language.lanname = 'plpgsql'
         and not procedure.prosecdef
         and procedure.provolatile = 'v'
         and procedure.proparallel = 'u'
         and not procedure.proisstrict
         and not procedure.proleakproof
         and procedure.proconfig is null
         and procedure.proacl is null
         and procedure.prosrc =
$historical_202605_assignment$
begin
  if new.referral_code is null then
    new.referral_code := public.airfnb_generate_referral_code();
  end if;
  return new;
end $historical_202605_assignment$
    )
    and exists (
      select 1
        from pg_catalog.pg_proc as procedure
        join pg_catalog.pg_namespace as namespace
          on namespace.oid = procedure.pronamespace
       where namespace.nspname = 'public'
         and procedure.proname = 'airfnb_handle_new_user'
         and procedure.proconfig = array['search_path=public']::text[]
    )
  into v_historical_202605;

  -- Accepted prestate 2: the exact old 202608 local hardening, including its
  -- subsequently corrected retry-boundary and error-message regression.
  select
    exists (
      select 1
        from pg_catalog.pg_proc as procedure
        join pg_catalog.pg_namespace as namespace
          on namespace.oid = procedure.pronamespace
        join pg_catalog.pg_language as language
          on language.oid = procedure.prolang
       where namespace.nspname = 'public'
         and procedure.proname = 'airfnb_generate_referral_code'
         and procedure.proowner = v_owner
         and pg_catalog.pg_get_function_identity_arguments(procedure.oid) = ''
         and procedure.prokind = 'f'
         and procedure.prorettype = 'pg_catalog.text'::pg_catalog.regtype
         and language.lanname = 'plpgsql'
         and not procedure.prosecdef
         and procedure.provolatile = 'v'
         and procedure.proparallel = 'u'
         and not procedure.proisstrict
         and not procedure.proleakproof
         and procedure.proconfig = array['search_path=pg_catalog, public']::text[]
         and procedure.proacl is not null
         and (
           select count(*) from pg_catalog.aclexplode(procedure.proacl)
         ) = 1
         and not exists (
           select 1
             from pg_catalog.aclexplode(procedure.proacl) as privilege
            where privilege.grantor <> procedure.proowner
               or privilege.grantee <> procedure.proowner
               or privilege.privilege_type <> 'EXECUTE'
               or privilege.is_grantable
         )
         and procedure.prosrc =
$old_202608_generator$
declare
  v_code text;
  v_attempts integer := 0;
begin
  loop
    v_attempts := v_attempts + 1;

    -- Preserve the existing eight-character, uppercase normalization contract.
    v_code := upper(substr(encode(extensions.gen_random_bytes(6), 'base64'), 1, 8));
    v_code := regexp_replace(v_code, '[+/=0OIL]', 'X', 'g');

    if not exists (
      select 1
        from public.airfnb_profiles
       where referral_code = v_code
    ) then
      return v_code;
    end if;

    if v_attempts >= 10 then
      raise exception 'could not generate unique referral code after % attempts', v_attempts;
    end if;
  end loop;
end
$old_202608_generator$
    )
    and exists (
      select 1
        from pg_catalog.pg_proc as procedure
        join pg_catalog.pg_namespace as namespace
          on namespace.oid = procedure.pronamespace
        join pg_catalog.pg_language as language
          on language.oid = procedure.prolang
       where namespace.nspname = 'public'
         and procedure.proname = 'airfnb_assign_referral_code'
         and procedure.proowner = v_owner
         and pg_catalog.pg_get_function_identity_arguments(procedure.oid) = ''
         and procedure.prokind = 'f'
         and procedure.prorettype = 'pg_catalog.trigger'::pg_catalog.regtype
         and language.lanname = 'plpgsql'
         and procedure.prosecdef
         and procedure.provolatile = 'v'
         and procedure.proparallel = 'u'
         and not procedure.proisstrict
         and not procedure.proleakproof
         and procedure.proconfig = array['search_path=pg_catalog, public']::text[]
         and procedure.proacl is not null
         and (
           select count(*) from pg_catalog.aclexplode(procedure.proacl)
         ) = 1
         and not exists (
           select 1
             from pg_catalog.aclexplode(procedure.proacl) as privilege
            where privilege.grantor <> procedure.proowner
               or privilege.grantee <> procedure.proowner
               or privilege.privilege_type <> 'EXECUTE'
               or privilege.is_grantable
         )
         and procedure.prosrc =
$old_202608_assignment$
begin
  if new.referral_code is null then
    new.referral_code := public.airfnb_generate_referral_code();
  end if;
  return new;
end
$old_202608_assignment$
    )
    and exists (
      select 1
        from pg_catalog.pg_proc as procedure
        join pg_catalog.pg_namespace as namespace
          on namespace.oid = procedure.pronamespace
       where namespace.nspname = 'public'
         and procedure.proname = 'airfnb_handle_new_user'
         and procedure.proconfig = array['search_path=public']::text[]
    )
  into v_old_202608_hardening;

  -- Accepted prestate 3: this migration's exact final state for safe reapply.
  select
    exists (
      select 1
        from pg_catalog.pg_proc as procedure
        join pg_catalog.pg_namespace as namespace
          on namespace.oid = procedure.pronamespace
        join pg_catalog.pg_language as language
          on language.oid = procedure.prolang
       where namespace.nspname = 'public'
         and procedure.proname = 'airfnb_generate_referral_code'
         and procedure.proowner = v_owner
         and pg_catalog.pg_get_function_identity_arguments(procedure.oid) = ''
         and procedure.prokind = 'f'
         and procedure.prorettype = 'pg_catalog.text'::pg_catalog.regtype
         and language.lanname = 'plpgsql'
         and not procedure.prosecdef
         and procedure.provolatile = 'v'
         and procedure.proparallel = 'u'
         and not procedure.proisstrict
         and not procedure.proleakproof
         and procedure.proconfig = array['search_path=pg_catalog, public']::text[]
         and procedure.proacl is not null
         and (
           select count(*) from pg_catalog.aclexplode(procedure.proacl)
         ) = 1
         and not exists (
           select 1
             from pg_catalog.aclexplode(procedure.proacl) as privilege
            where privilege.grantor <> procedure.proowner
               or privilege.grantee <> procedure.proowner
               or privilege.privilege_type <> 'EXECUTE'
               or privilege.is_grantable
         )
         and procedure.prosrc =
$final_generator$
declare
  v_code text;
  v_attempts integer := 0;
begin
  loop
    v_attempts := v_attempts + 1;
    v_code := pg_catalog.upper(
      pg_catalog.substr(
        pg_catalog.encode(extensions.gen_random_bytes(6), 'base64'),
        1,
        8
      )
    );
    v_code := pg_catalog.regexp_replace(v_code, '[+/=0OIL]', 'X', 'g');
    exit when not exists (
      select 1
        from public.airfnb_profiles
       where referral_code = v_code
    );
    if v_attempts > 10 then
      raise exception 'could not generate unique referral code';
    end if;
  end loop;
  return v_code;
end
$final_generator$
    )
    and exists (
      select 1
        from pg_catalog.pg_proc as procedure
        join pg_catalog.pg_namespace as namespace
          on namespace.oid = procedure.pronamespace
        join pg_catalog.pg_language as language
          on language.oid = procedure.prolang
       where namespace.nspname = 'public'
         and procedure.proname = 'airfnb_assign_referral_code'
         and procedure.proowner = v_owner
         and pg_catalog.pg_get_function_identity_arguments(procedure.oid) = ''
         and procedure.prokind = 'f'
         and procedure.prorettype = 'pg_catalog.trigger'::pg_catalog.regtype
         and language.lanname = 'plpgsql'
         and procedure.prosecdef
         and procedure.provolatile = 'v'
         and procedure.proparallel = 'u'
         and not procedure.proisstrict
         and not procedure.proleakproof
         and procedure.proconfig = array['search_path=pg_catalog, public']::text[]
         and procedure.proacl is not null
         and (
           select count(*) from pg_catalog.aclexplode(procedure.proacl)
         ) = 1
         and not exists (
           select 1
             from pg_catalog.aclexplode(procedure.proacl) as privilege
            where privilege.grantor <> procedure.proowner
               or privilege.grantee <> procedure.proowner
               or privilege.privilege_type <> 'EXECUTE'
               or privilege.is_grantable
         )
         and procedure.prosrc =
$final_assignment$
begin
  if new.referral_code is null then
    new.referral_code := public.airfnb_generate_referral_code();
  end if;
  return new;
end
$final_assignment$
    )
    and exists (
      select 1
        from pg_catalog.pg_proc as procedure
        join pg_catalog.pg_namespace as namespace
          on namespace.oid = procedure.pronamespace
       where namespace.nspname = 'public'
         and procedure.proname = 'airfnb_handle_new_user'
         and procedure.proconfig = array['search_path=pg_catalog, public']::text[]
    )
  into v_final_reapplied;

  if (
    v_historical_202605::integer
    + v_old_202608_hardening::integer
    + v_final_reapplied::integer
  ) <> 1 then
    raise exception 'runtime function integrity refused: mixed or unknown prestate';
  end if;

  if (
    select count(*)
      from pg_catalog.pg_trigger as trigger_row
      join pg_catalog.pg_proc as procedure
        on procedure.oid = trigger_row.tgfoid
      join pg_catalog.pg_namespace as function_namespace
        on function_namespace.oid = procedure.pronamespace
     where not trigger_row.tgisinternal
       and function_namespace.nspname = 'public'
       and procedure.proname in (
         'airfnb_assign_referral_code',
         'airfnb_handle_new_user'
       )
  ) <> 2 then
    raise exception 'runtime function integrity refused: unexpected trigger binding count';
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_trigger as trigger_row
      join pg_catalog.pg_class as relation
        on relation.oid = trigger_row.tgrelid
      join pg_catalog.pg_namespace as table_namespace
        on table_namespace.oid = relation.relnamespace
      join pg_catalog.pg_proc as procedure
        on procedure.oid = trigger_row.tgfoid
      join pg_catalog.pg_namespace as function_namespace
        on function_namespace.oid = procedure.pronamespace
     where not trigger_row.tgisinternal
       and table_namespace.nspname = 'public'
       and relation.relname = 'airfnb_profiles'
       and trigger_row.tgname = 'airfnb_profile_referral_code'
       and trigger_row.tgenabled = 'O'
       and trigger_row.tgtype = 7
       and trigger_row.tgnargs = 0
       and trigger_row.tgconstraint = 0
       and trigger_row.tgqual is null
       and trigger_row.tgoldtable is null
       and trigger_row.tgnewtable is null
       and function_namespace.nspname = 'public'
       and procedure.proname = 'airfnb_assign_referral_code'
       and pg_catalog.pg_get_function_identity_arguments(procedure.oid) = ''
  ) then
    raise exception 'runtime function integrity refused: profile trigger drifted';
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_trigger as trigger_row
      join pg_catalog.pg_class as relation
        on relation.oid = trigger_row.tgrelid
      join pg_catalog.pg_namespace as table_namespace
        on table_namespace.oid = relation.relnamespace
      join pg_catalog.pg_proc as procedure
        on procedure.oid = trigger_row.tgfoid
      join pg_catalog.pg_namespace as function_namespace
        on function_namespace.oid = procedure.pronamespace
     where not trigger_row.tgisinternal
       and table_namespace.nspname = 'auth'
       and relation.relname = 'users'
       and trigger_row.tgname = 'airfnb_trg_auth_new_user'
       and trigger_row.tgenabled = 'O'
       and trigger_row.tgtype = 5
       and trigger_row.tgnargs = 0
       and trigger_row.tgconstraint = 0
       and trigger_row.tgqual is null
       and trigger_row.tgoldtable is null
       and trigger_row.tgnewtable is null
       and function_namespace.nspname = 'public'
       and procedure.proname = 'airfnb_handle_new_user'
       and pg_catalog.pg_get_function_identity_arguments(procedure.oid) = ''
  ) then
    raise exception 'runtime function integrity refused: signup trigger drifted';
  end if;
end
$preconditions$;

create temporary table airfnb_rfi_reconciliation_state_20260820
on commit drop
as
select procedure.oid,
       procedure.proowner
  from pg_catalog.pg_proc as procedure
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = procedure.pronamespace
 where namespace.nspname = 'public'
   and procedure.proname in (
     'airfnb_generate_referral_code',
     'airfnb_assign_referral_code',
     'airfnb_handle_new_user'
   );

create or replace function public.airfnb_generate_referral_code()
returns text
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
declare
  v_code text;
  v_attempts integer := 0;
begin
  loop
    v_attempts := v_attempts + 1;
    v_code := pg_catalog.upper(
      pg_catalog.substr(
        pg_catalog.encode(extensions.gen_random_bytes(6), 'base64'),
        1,
        8
      )
    );
    v_code := pg_catalog.regexp_replace(v_code, '[+/=0OIL]', 'X', 'g');
    exit when not exists (
      select 1
        from public.airfnb_profiles
       where referral_code = v_code
    );
    if v_attempts > 10 then
      raise exception 'could not generate unique referral code';
    end if;
  end loop;
  return v_code;
end
$function$;

create or replace function public.airfnb_assign_referral_code()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if new.referral_code is null then
    new.referral_code := public.airfnb_generate_referral_code();
  end if;
  return new;
end
$function$;

alter function public.airfnb_handle_new_user()
  security definer;
alter function public.airfnb_handle_new_user()
  set search_path = pg_catalog, public;

revoke execute on function public.airfnb_generate_referral_code()
  from public, anon, authenticated, service_role;
revoke execute on function public.airfnb_assign_referral_code()
  from public, anon, authenticated, service_role;
revoke execute on function public.airfnb_handle_new_user()
  from public, anon, authenticated, service_role;

do $postconditions$
declare
  v_owner oid;
begin
  if exists (
    select 1
      from airfnb_rfi_reconciliation_state_20260820 as original
      full join (
        select procedure.oid,
               procedure.proowner
          from pg_catalog.pg_proc as procedure
          join pg_catalog.pg_namespace as namespace
            on namespace.oid = procedure.pronamespace
         where namespace.nspname = 'public'
           and procedure.proname in (
             'airfnb_generate_referral_code',
             'airfnb_assign_referral_code',
             'airfnb_handle_new_user'
           )
      ) as reconciled using (oid, proowner)
     where original.oid is null
        or reconciled.oid is null
  ) then
    raise exception 'runtime function integrity failed: target OID or owner changed';
  end if;

  select procedure.proowner
    into v_owner
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
   where namespace.nspname = 'public'
     and procedure.proname = 'airfnb_generate_referral_code';

  if not exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname = 'airfnb_generate_referral_code'
       and procedure.proowner = v_owner
       and pg_catalog.pg_get_function_identity_arguments(procedure.oid) = ''
       and procedure.prorettype = 'pg_catalog.text'::pg_catalog.regtype
       and not procedure.prosecdef
       and procedure.proconfig = array['search_path=pg_catalog, public']::text[]
       and procedure.prosrc =
$generator_body$
declare
  v_code text;
  v_attempts integer := 0;
begin
  loop
    v_attempts := v_attempts + 1;
    v_code := pg_catalog.upper(
      pg_catalog.substr(
        pg_catalog.encode(extensions.gen_random_bytes(6), 'base64'),
        1,
        8
      )
    );
    v_code := pg_catalog.regexp_replace(v_code, '[+/=0OIL]', 'X', 'g');
    exit when not exists (
      select 1
        from public.airfnb_profiles
       where referral_code = v_code
    );
    if v_attempts > 10 then
      raise exception 'could not generate unique referral code';
    end if;
  end loop;
  return v_code;
end
$generator_body$
  ) then
    raise exception 'runtime function integrity failed: generator postcondition';
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname = 'airfnb_assign_referral_code'
       and procedure.proowner = v_owner
       and pg_catalog.pg_get_function_identity_arguments(procedure.oid) = ''
       and procedure.prorettype = 'pg_catalog.trigger'::pg_catalog.regtype
       and procedure.prosecdef
       and procedure.proconfig = array['search_path=pg_catalog, public']::text[]
       and procedure.prosrc =
$assignment_body$
begin
  if new.referral_code is null then
    new.referral_code := public.airfnb_generate_referral_code();
  end if;
  return new;
end
$assignment_body$
  ) then
    raise exception 'runtime function integrity failed: assignment postcondition';
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname = 'airfnb_handle_new_user'
       and procedure.proowner = v_owner
       and pg_catalog.pg_get_function_identity_arguments(procedure.oid) = ''
       and procedure.prorettype = 'pg_catalog.trigger'::pg_catalog.regtype
       and procedure.prosecdef
       and procedure.proconfig = array['search_path=pg_catalog, public']::text[]
       and procedure.prosrc =
$signup_body$
begin
  insert into public.airfnb_profiles (id, full_name, locale)
  values (new.id, new.raw_user_meta_data->>'full_name', coalesce(new.raw_user_meta_data->>'locale','pt-PT'))
  on conflict (id) do nothing;
  return new;
end $signup_body$
  ) then
    raise exception 'runtime function integrity failed: signup postcondition';
  end if;

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
    raise exception 'runtime function integrity failed: direct execute remains';
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
       and not pg_catalog.has_function_privilege(v_owner, procedure.oid, 'EXECUTE')
  ) then
    raise exception 'runtime function integrity failed: owner execute missing';
  end if;
end
$postconditions$;

commit;
