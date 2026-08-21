-- Reconcile the event-request privacy boundary after the identity and runtime
-- integrity predecessors. RLS continues to decide rows; column privileges and
-- authenticated-only matching RPCs decide which fields can leave PostgreSQL.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';
set local idle_in_transaction_session_timeout = '60s';

do $preconditions$
declare
  v_table oid := pg_catalog.to_regclass('public.airfnb_event_requests');
  v_categories oid := pg_catalog.to_regclass('public.airfnb_truck_categories');
  v_availability oid := pg_catalog.to_regclass('public.airfnb_truck_availability');
  v_owner oid;
  v_anon oid;
  v_authenticated oid;
  v_service_role oid;
  v_anon_columns text[];
  v_authenticated_columns text[];
  v_privilege_state text;
  v_old_rpc_acl boolean;
  v_final_rpc_acl boolean;
begin
  select pg_catalog.max(role.oid) filter (where role.rolname = 'anon'),
         pg_catalog.max(role.oid) filter (where role.rolname = 'authenticated'),
         pg_catalog.max(role.oid) filter (where role.rolname = 'service_role')
    into v_anon, v_authenticated, v_service_role
    from pg_catalog.pg_roles as role
   where role.rolname in ('anon', 'authenticated', 'service_role');

  if v_anon is null or v_authenticated is null or v_service_role is null then
    raise exception 'public request privacy refused: required API roles are missing';
  end if;

  if v_table is null or not exists (
    select 1
      from pg_catalog.pg_class as relation
     where relation.oid = v_table
       and relation.relkind = 'r'
       and relation.relrowsecurity
       and not relation.relforcerowsecurity
  ) then
    raise exception 'public request privacy refused: event-request table or RLS mode drifted';
  end if;

  if v_categories is null or v_availability is null or exists (
    select 1
      from pg_catalog.pg_class as relation
     where relation.oid in (v_categories, v_availability)
       and (
         relation.relkind <> 'r'
         or not relation.relrowsecurity
         or relation.relforcerowsecurity
       )
  ) or (
    select pg_catalog.md5(
             pg_catalog.string_agg(
               pg_catalog.format(
                 '%s:%s:%s',
                 attribute.attname,
                 pg_catalog.format_type(attribute.atttypid, attribute.atttypmod),
                 attribute.attnotnull
               ),
               ',' order by attribute.attnum
             )
           )
      from pg_catalog.pg_attribute as attribute
     where attribute.attrelid = v_categories
       and attribute.attnum > 0
       and not attribute.attisdropped
  ) <> 'e5434c557209aafd5dac41f419fafc00' or (
    select pg_catalog.md5(
             pg_catalog.string_agg(
               pg_catalog.format(
                 '%s:%s:%s',
                 attribute.attname,
                 pg_catalog.format_type(attribute.atttypid, attribute.atttypmod),
                 attribute.attnotnull
               ),
               ',' order by attribute.attnum
             )
           )
      from pg_catalog.pg_attribute as attribute
     where attribute.attrelid = v_availability
       and attribute.attnum > 0
       and not attribute.attisdropped
  ) <> '344c8d82fb3de7f346017c11797537de' then
    raise exception 'public request privacy refused: matching dependency shape drifted';
  end if;

  if (
    select pg_catalog.count(*)
      from pg_catalog.pg_policy as policy
     where policy.polrelid in (v_categories, v_availability)
  ) <> 3 or not exists (
    select 1
      from pg_catalog.pg_policy as policy
     where policy.polrelid = v_categories
       and policy.polname = 'airfnb_truck_cat_read'
       and policy.polcmd = 'r'
       and policy.polpermissive
       and policy.polwithcheck is null
       and (
         (
           policy.polroles = array[0::oid]
           and pg_catalog.pg_get_expr(policy.polqual, policy.polrelid) = 'true'
         )
         or (
           policy.polroles = array[v_anon, v_authenticated]
           and pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
             = 'airfnb_can_read_truck_child((truck_id)::text)'
         )
       )
  ) or (
    select pg_catalog.md5(
             pg_catalog.string_agg(
               pg_catalog.concat_ws(
                 '|',
                 relation.relname,
                 policy.polname,
                 policy.polcmd,
                 policy.polpermissive,
                 policy.polroles::text,
                 coalesce(pg_catalog.pg_get_expr(policy.polqual, policy.polrelid), ''),
                 coalesce(pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid), '')
               ),
               E'\n' order by relation.relname, policy.polname
             ) filter (where policy.polname <> 'airfnb_truck_cat_read')
           )
      from pg_catalog.pg_policy as policy
      join pg_catalog.pg_class as relation on relation.oid = policy.polrelid
     where policy.polrelid in (v_categories, v_availability)
  ) <> '9238f605f295fb478bf4fe6148bd4957' then
    raise exception 'public request privacy refused: matching dependency policy drifted';
  end if;

  if (
    select pg_catalog.count(*)
      from pg_catalog.pg_attribute as attribute
     where attribute.attrelid = v_table
       and attribute.attnum > 0
       and not attribute.attisdropped
  ) <> 50 or (
    select pg_catalog.md5(
             pg_catalog.string_agg(
               pg_catalog.format(
                 '%s:%s:%s',
                 attribute.attname,
                 pg_catalog.format_type(attribute.atttypid, attribute.atttypmod),
                 attribute.attnotnull
               ),
               ',' order by attribute.attnum
             )
           )
      from pg_catalog.pg_attribute as attribute
     where attribute.attrelid = v_table
       and attribute.attnum > 0
       and not attribute.attisdropped
  ) <> 'b1c7105b115d8fe4bed8fb89882c993d' then
    raise exception 'public request privacy refused: expected exact 50-column event-request shape';
  end if;

  if (
    select pg_catalog.count(*)
      from pg_catalog.pg_policy as policy
     where policy.polrelid = v_table
  ) <> 4 or (
    select pg_catalog.md5(
             pg_catalog.string_agg(
               pg_catalog.concat_ws(
                 '|',
                 policy.polname,
                 policy.polcmd,
                 policy.polpermissive,
                 policy.polroles::text,
                 coalesce(
                   pg_catalog.pg_get_expr(policy.polqual, policy.polrelid),
                   ''
                 ),
                 coalesce(
                   pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid),
                   ''
                 )
               ),
               E'\n' order by policy.polname
             )
           )
      from pg_catalog.pg_policy as policy
     where policy.polrelid = v_table
  ) <> 'be3e742b43c1e53d2a5dd22720ad30ce' then
    raise exception 'public request privacy refused: four-policy row semantics drifted';
  end if;

  if (
    select pg_catalog.count(*)
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'airfnb_match_score',
         'airfnb_match_scores_batch',
         'airfnb_find_matching_requests',
         'airfnb_find_matching_trucks',
         'airfnb_recommend_trucks_for_request',
         'airfnb_match_category_availability_score',
         'airfnb_is_admin',
         'airfnb_user_owns_invited_truck',
         'airfnb_user_organizes_request',
         'airfnb_private_event_requests'
       )
  ) not in (9, 10) or (
    select pg_catalog.count(*)
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname = 'airfnb_match_category_availability_score'
  ) not in (0, 1) or (
    select pg_catalog.count(*)
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname = 'airfnb_match_category_availability_score'
  ) = 1 and pg_catalog.to_regprocedure(
    'public.airfnb_match_category_availability_score(uuid,uuid)'
  ) is null or pg_catalog.to_regprocedure(
    'public.airfnb_match_score(uuid,uuid)'
  ) is null or pg_catalog.to_regprocedure(
    'public.airfnb_match_scores_batch(uuid[],uuid[])'
  ) is null or pg_catalog.to_regprocedure(
    'public.airfnb_find_matching_requests(uuid,integer)'
  ) is null or pg_catalog.to_regprocedure(
    'public.airfnb_find_matching_trucks(uuid,integer)'
  ) is null or pg_catalog.to_regprocedure(
    'public.airfnb_recommend_trucks_for_request(uuid,integer)'
  ) is null or pg_catalog.to_regprocedure(
    'public.airfnb_is_admin()'
  ) is null or pg_catalog.to_regprocedure(
    'public.airfnb_user_owns_invited_truck(uuid)'
  ) is null or pg_catalog.to_regprocedure(
    'public.airfnb_user_organizes_request(uuid)'
  ) is null or pg_catalog.to_regprocedure(
    'public.airfnb_private_event_requests(uuid)'
  ) is null then
    raise exception 'public request privacy refused: missing or overloaded target function';
  end if;

  select relation.relowner
    into v_owner
    from pg_catalog.pg_class as relation
   where relation.oid = v_table;

  if not exists (
    select 1
      from pg_catalog.pg_roles as owner_role
     where owner_role.oid = v_owner
       and owner_role.rolbypassrls
       and owner_role.rolname not in ('anon', 'authenticated', 'service_role')
  ) or exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'airfnb_match_score',
         'airfnb_match_scores_batch',
         'airfnb_find_matching_requests',
         'airfnb_find_matching_trucks',
         'airfnb_recommend_trucks_for_request',
         'airfnb_match_category_availability_score',
         'airfnb_is_admin',
         'airfnb_user_owns_invited_truck',
         'airfnb_user_organizes_request',
         'airfnb_private_event_requests'
       )
       and procedure.proowner <> v_owner
  ) or exists (
    select 1
      from pg_catalog.pg_class as relation
     where relation.oid in (v_categories, v_availability)
       and relation.relowner <> v_owner
  ) then
    raise exception 'public request privacy refused: table/helper owner drifted';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
      join pg_catalog.pg_language as language
        on language.oid = procedure.prolang
     where namespace.nspname = 'public'
       and procedure.proname in (
         'airfnb_match_score',
         'airfnb_match_scores_batch',
         'airfnb_find_matching_requests',
         'airfnb_find_matching_trucks',
         'airfnb_recommend_trucks_for_request',
         'airfnb_match_category_availability_score',
         'airfnb_is_admin',
         'airfnb_user_owns_invited_truck',
         'airfnb_user_organizes_request',
         'airfnb_private_event_requests'
       )
       and (
         procedure.prokind <> 'f'
         or procedure.provolatile <> 's'
         or language.lanname not in ('sql', 'plpgsql')
       )
  ) or exists (
    select 1
      from pg_catalog.pg_proc as procedure
     where procedure.oid in (
       'public.airfnb_match_score(uuid,uuid)'::pg_catalog.regprocedure,
       'public.airfnb_match_scores_batch(uuid[],uuid[])'::pg_catalog.regprocedure,
       'public.airfnb_find_matching_requests(uuid,integer)'::pg_catalog.regprocedure,
       'public.airfnb_find_matching_trucks(uuid,integer)'::pg_catalog.regprocedure,
       'public.airfnb_recommend_trucks_for_request(uuid,integer)'::pg_catalog.regprocedure
     )
       and procedure.prosecdef
  ) or exists (
    select 1
      from pg_catalog.pg_proc as procedure
     where procedure.oid in (
       'public.airfnb_is_admin()'::pg_catalog.regprocedure,
       'public.airfnb_user_owns_invited_truck(uuid)'::pg_catalog.regprocedure,
       'public.airfnb_user_organizes_request(uuid)'::pg_catalog.regprocedure,
       'public.airfnb_private_event_requests(uuid)'::pg_catalog.regprocedure
     )
       and not procedure.prosecdef
  ) or exists (
    select 1
      from pg_catalog.pg_proc as procedure
     where procedure.oid = pg_catalog.to_regprocedure(
       'public.airfnb_match_category_availability_score(uuid,uuid)'
     )
       and not procedure.prosecdef
  ) then
    raise exception 'public request privacy refused: stability or security mode drifted';
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_proc as procedure
     where procedure.oid = 'public.airfnb_match_score(uuid,uuid)'::pg_catalog.regprocedure
       and procedure.prorettype = 'pg_catalog.numeric'::pg_catalog.regtype
       and not procedure.proretset
       and procedure.proconfig in (
         array['search_path=public']::text[],
         array['search_path=""']::text[]
       )
       and (
         pg_catalog.md5(procedure.prosrc) = '9a4e472e755ab5920be3e5fa2c238fec'
         or procedure.prosrc =
$reconciled_match_score$
declare
  score numeric := 0;
  t record;
  r record;
begin
  select truck.id,
         truck.base_city,
         truck.capacity,
         truck.rating_avg,
         truck.featured,
         truck.base_price
    into t
    from public.airfnb_trucks as truck
   where truck.id = p_truck
     and truck.status = 'active';
  if not found then
    return 0;
  end if;

  select request_row.id,
         request_row.status,
         request_row.desired_categories,
         request_row.city,
         request_row.expected_pax,
         request_row.start_at,
         request_row.budget_max
    into r
    from public.airfnb_event_requests as request_row
   where request_row.id = p_request
     and request_row.status in ('open', 'reviewing');
  if not found then
    return 0;
  end if;

  score := score + public.airfnb_match_category_availability_score(t.id, r.id);

  if t.base_city is not null
     and r.city is not null
     and pg_catalog.lower(t.base_city) = pg_catalog.lower(r.city) then
    score := score + 20;
  end if;
  if t.capacity is not null
     and r.expected_pax is not null
     and t.capacity >= r.expected_pax then
    score := score + 15;
  end if;
  if t.rating_avg >= 4.5 then score := score + 10;
  elsif t.rating_avg >= 4.0 then score := score + 5;
  end if;
  if t.featured then score := score + 5; end if;
  if t.base_price is not null
     and r.budget_max is not null
     and t.base_price <= r.budget_max then
    score := score + 10;
  end if;
  return least(score, 100);
end
$reconciled_match_score$
       )
  ) then
    raise exception 'public request privacy refused: match-score definition drifted';
  end if;

  if pg_catalog.to_regprocedure(
       'public.airfnb_match_category_availability_score(uuid,uuid)'
     ) is not null and not exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_language as language on language.oid = procedure.prolang
     where procedure.oid = pg_catalog.to_regprocedure(
       'public.airfnb_match_category_availability_score(uuid,uuid)'
     )
       and procedure.proowner = v_owner
       and procedure.prorettype = 'pg_catalog.numeric'::pg_catalog.regtype
       and not procedure.proretset
       and procedure.prokind = 'f'
       and procedure.provolatile = 's'
       and procedure.prosecdef
       and language.lanname = 'sql'
       and procedure.proconfig = array['search_path=""']::text[]
       and pg_catalog.md5(procedure.prosrc) = '6541cf17b1d05b7e59077326e48e1738'
       and not pg_catalog.has_function_privilege(v_anon, procedure.oid, 'EXECUTE')
       and pg_catalog.has_function_privilege(v_authenticated, procedure.oid, 'EXECUTE')
       and not pg_catalog.has_function_privilege(v_service_role, procedure.oid, 'EXECUTE')
       and not exists (
         select 1
           from pg_catalog.aclexplode(
             coalesce(
               procedure.proacl,
               pg_catalog.acldefault('f', procedure.proowner)
             )
           ) as privilege
          where privilege.grantee = 0
            and privilege.privilege_type = 'EXECUTE'
       )
  ) then
    raise exception 'public request privacy refused: scalar helper definition or ACL drifted';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_proc as procedure
     where procedure.oid in (
       'public.airfnb_match_scores_batch(uuid[],uuid[])'::pg_catalog.regprocedure,
       'public.airfnb_find_matching_requests(uuid,integer)'::pg_catalog.regprocedure,
       'public.airfnb_find_matching_trucks(uuid,integer)'::pg_catalog.regprocedure,
       'public.airfnb_recommend_trucks_for_request(uuid,integer)'::pg_catalog.regprocedure
     )
       and (
         procedure.proconfig not in (
           array['search_path=public']::text[],
           array['search_path=""']::text[]
         )
         or pg_catalog.md5(procedure.prosrc) <> case procedure.oid
           when 'public.airfnb_match_scores_batch(uuid[],uuid[])'::pg_catalog.regprocedure
             then '58da7d4b10ecaea3e70c63d0e23dc571'
           when 'public.airfnb_find_matching_requests(uuid,integer)'::pg_catalog.regprocedure
             then '5310f5caf763d54e7f94d51372b67d7b'
           when 'public.airfnb_find_matching_trucks(uuid,integer)'::pg_catalog.regprocedure
             then 'aedb38e7443cbe29c5ed7ef4e6449f77'
           when 'public.airfnb_recommend_trucks_for_request(uuid,integer)'::pg_catalog.regprocedure
             then '6b9d841a803e8e9344fd40e57295dfbb'
         end
       )
  ) then
    raise exception 'public request privacy refused: matching RPC definition drifted';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_proc as procedure
     where procedure.oid in (
       'public.airfnb_is_admin()'::pg_catalog.regprocedure,
       'public.airfnb_user_owns_invited_truck(uuid)'::pg_catalog.regprocedure,
       'public.airfnb_user_organizes_request(uuid)'::pg_catalog.regprocedure,
       'public.airfnb_private_event_requests(uuid)'::pg_catalog.regprocedure
     )
       and (
         procedure.proconfig not in (
           array['search_path=public']::text[],
           array['search_path=""']::text[]
         )
         or pg_catalog.md5(procedure.prosrc) <> case procedure.oid
           when 'public.airfnb_is_admin()'::pg_catalog.regprocedure
             then 'aa950c573de3ffe4835f7851c09a0631'
           when 'public.airfnb_user_owns_invited_truck(uuid)'::pg_catalog.regprocedure
             then '6de885423f67e9dd9f899000189fa76a'
           when 'public.airfnb_user_organizes_request(uuid)'::pg_catalog.regprocedure
             then '8a6c90384ddac61068db12270a78addf'
           when 'public.airfnb_private_event_requests(uuid)'::pg_catalog.regprocedure
             then 'eaeaa4edf5a43ed926685df21f1c70c3'
         end
       )
  ) then
    raise exception 'public request privacy refused: DB-backed helper definition drifted';
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
         'airfnb_match_score',
         'airfnb_match_scores_batch',
         'airfnb_find_matching_requests',
         'airfnb_find_matching_trucks',
         'airfnb_recommend_trucks_for_request',
         'airfnb_is_admin',
         'airfnb_user_owns_invited_truck',
         'airfnb_user_organizes_request',
         'airfnb_private_event_requests'
       )
       and (
         privilege.grantor <> procedure.proowner
         or privilege.privilege_type <> 'EXECUTE'
         or privilege.is_grantable
         or privilege.grantee not in (
           0,
           procedure.proowner,
           v_anon,
           v_authenticated,
           v_service_role
         )
       )
  ) then
    raise exception 'public request privacy refused: unexpected function ACL';
  end if;

  select
    pg_catalog.has_function_privilege(v_anon, procedure.oid, 'EXECUTE')
    and pg_catalog.has_function_privilege(v_authenticated, procedure.oid, 'EXECUTE')
    and pg_catalog.has_function_privilege(v_service_role, procedure.oid, 'EXECUTE')
    and exists (
      select 1
        from pg_catalog.aclexplode(
          coalesce(
            procedure.proacl,
            pg_catalog.acldefault('f', procedure.proowner)
          )
        ) as privilege
       where privilege.grantee = 0
         and privilege.privilege_type = 'EXECUTE'
    )
    into v_old_rpc_acl
    from pg_catalog.pg_proc as procedure
   where procedure.oid = 'public.airfnb_match_score(uuid,uuid)'::pg_catalog.regprocedure;

  v_old_rpc_acl := v_old_rpc_acl and not pg_catalog.has_function_privilege(
    v_anon,
    'public.airfnb_match_scores_batch(uuid[],uuid[])'::pg_catalog.regprocedure,
    'EXECUTE'
  ) and pg_catalog.has_function_privilege(
    v_authenticated,
    'public.airfnb_match_scores_batch(uuid[],uuid[])'::pg_catalog.regprocedure,
    'EXECUTE'
  ) and not pg_catalog.has_function_privilege(
    v_service_role,
    'public.airfnb_match_scores_batch(uuid[],uuid[])'::pg_catalog.regprocedure,
    'EXECUTE'
  ) and not exists (
    select 1
      from pg_catalog.pg_proc as procedure
      cross join lateral pg_catalog.aclexplode(
        coalesce(
          procedure.proacl,
          pg_catalog.acldefault('f', procedure.proowner)
        )
      ) as privilege
     where procedure.oid = 'public.airfnb_match_scores_batch(uuid[],uuid[])'::pg_catalog.regprocedure
       and privilege.grantee = 0
       and privilege.privilege_type = 'EXECUTE'
  ) and not exists (
    select 1
      from pg_catalog.pg_proc as procedure
     where procedure.oid in (
       'public.airfnb_find_matching_requests(uuid,integer)'::pg_catalog.regprocedure,
       'public.airfnb_find_matching_trucks(uuid,integer)'::pg_catalog.regprocedure,
       'public.airfnb_recommend_trucks_for_request(uuid,integer)'::pg_catalog.regprocedure
     )
       and not (
         pg_catalog.has_function_privilege(v_anon, procedure.oid, 'EXECUTE')
         and pg_catalog.has_function_privilege(v_authenticated, procedure.oid, 'EXECUTE')
         and pg_catalog.has_function_privilege(v_service_role, procedure.oid, 'EXECUTE')
         and exists (
           select 1
             from pg_catalog.aclexplode(
               coalesce(
                 procedure.proacl,
                 pg_catalog.acldefault('f', procedure.proowner)
               )
             ) as privilege
            where privilege.grantee = 0
              and privilege.privilege_type = 'EXECUTE'
         )
       )
  );

  select not exists (
    select 1
      from pg_catalog.pg_proc as procedure
     where procedure.oid in (
       'public.airfnb_match_score(uuid,uuid)'::pg_catalog.regprocedure,
       'public.airfnb_match_scores_batch(uuid[],uuid[])'::pg_catalog.regprocedure,
       'public.airfnb_find_matching_requests(uuid,integer)'::pg_catalog.regprocedure,
       'public.airfnb_find_matching_trucks(uuid,integer)'::pg_catalog.regprocedure,
       'public.airfnb_recommend_trucks_for_request(uuid,integer)'::pg_catalog.regprocedure
     )
       and (
         pg_catalog.has_function_privilege(v_anon, procedure.oid, 'EXECUTE')
         or not pg_catalog.has_function_privilege(v_authenticated, procedure.oid, 'EXECUTE')
         or pg_catalog.has_function_privilege(v_service_role, procedure.oid, 'EXECUTE')
         or exists (
           select 1
             from pg_catalog.aclexplode(
               coalesce(
                 procedure.proacl,
                 pg_catalog.acldefault('f', procedure.proowner)
               )
             ) as privilege
            where privilege.grantee = 0
              and privilege.privilege_type = 'EXECUTE'
         )
       )
  ) into v_final_rpc_acl;

  if not (v_old_rpc_acl or v_final_rpc_acl) then
    raise exception 'public request privacy refused: matching RPC ACL drifted';
  end if;

  if not (
    pg_catalog.has_function_privilege(v_anon, 'public.airfnb_is_admin()'::pg_catalog.regprocedure, 'EXECUTE')
    and pg_catalog.has_function_privilege(v_authenticated, 'public.airfnb_is_admin()'::pg_catalog.regprocedure, 'EXECUTE')
    and not pg_catalog.has_function_privilege(v_service_role, 'public.airfnb_is_admin()'::pg_catalog.regprocedure, 'EXECUTE')
    and pg_catalog.has_function_privilege(v_anon, 'public.airfnb_user_owns_invited_truck(uuid)'::pg_catalog.regprocedure, 'EXECUTE')
    and pg_catalog.has_function_privilege(v_authenticated, 'public.airfnb_user_owns_invited_truck(uuid)'::pg_catalog.regprocedure, 'EXECUTE')
    and pg_catalog.has_function_privilege(v_service_role, 'public.airfnb_user_owns_invited_truck(uuid)'::pg_catalog.regprocedure, 'EXECUTE')
    and pg_catalog.has_function_privilege(v_anon, 'public.airfnb_user_organizes_request(uuid)'::pg_catalog.regprocedure, 'EXECUTE')
    and pg_catalog.has_function_privilege(v_authenticated, 'public.airfnb_user_organizes_request(uuid)'::pg_catalog.regprocedure, 'EXECUTE')
    and pg_catalog.has_function_privilege(v_service_role, 'public.airfnb_user_organizes_request(uuid)'::pg_catalog.regprocedure, 'EXECUTE')
    and not pg_catalog.has_function_privilege(v_anon, 'public.airfnb_private_event_requests(uuid)'::pg_catalog.regprocedure, 'EXECUTE')
    and pg_catalog.has_function_privilege(v_authenticated, 'public.airfnb_private_event_requests(uuid)'::pg_catalog.regprocedure, 'EXECUTE')
    and not pg_catalog.has_function_privilege(v_service_role, 'public.airfnb_private_event_requests(uuid)'::pg_catalog.regprocedure, 'EXECUTE')
  ) then
    raise exception 'public request privacy refused: helper ACL drifted';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_proc as procedure
      cross join lateral pg_catalog.aclexplode(
        coalesce(
          procedure.proacl,
          pg_catalog.acldefault('f', procedure.proowner)
        )
      ) as privilege
     where procedure.oid in (
       'public.airfnb_is_admin()'::pg_catalog.regprocedure,
       'public.airfnb_user_owns_invited_truck(uuid)'::pg_catalog.regprocedure,
       'public.airfnb_user_organizes_request(uuid)'::pg_catalog.regprocedure,
       'public.airfnb_private_event_requests(uuid)'::pg_catalog.regprocedure
     )
       and privilege.grantee = 0
       and privilege.privilege_type = 'EXECUTE'
  ) then
    raise exception 'public request privacy refused: PUBLIC can execute a private helper';
  end if;

  select pg_catalog.array_agg(attribute.attname::text order by attribute.attnum)
    into v_anon_columns
    from pg_catalog.pg_attribute as attribute
   where attribute.attrelid = v_table
     and attribute.attnum > 0
     and not attribute.attisdropped
     and pg_catalog.has_column_privilege(v_anon, v_table, attribute.attnum, 'SELECT');

  select pg_catalog.array_agg(attribute.attname::text order by attribute.attnum)
    into v_authenticated_columns
    from pg_catalog.pg_attribute as attribute
   where attribute.attrelid = v_table
     and attribute.attnum > 0
     and not attribute.attisdropped
     and pg_catalog.has_column_privilege(
       v_authenticated,
       v_table,
       attribute.attnum,
       'SELECT'
     );

  if exists (
    select 1
      from pg_catalog.aclexplode(
        coalesce(
          (select relation.relacl from pg_catalog.pg_class as relation where relation.oid = v_table),
          pg_catalog.acldefault('r', v_owner)
        )
      ) as privilege
     where privilege.grantee = 0
       and privilege.privilege_type = 'SELECT'
  ) or exists (
    select 1
      from pg_catalog.pg_attribute as attribute
      cross join lateral pg_catalog.aclexplode(attribute.attacl) as privilege
     where attribute.attrelid = v_table
       and attribute.attnum > 0
       and not attribute.attisdropped
       and privilege.grantee = 0
       and privilege.privilege_type = 'SELECT'
  ) or not pg_catalog.has_table_privilege(v_service_role, v_table, 'SELECT') then
    raise exception 'public request privacy refused: PUBLIC or service-role SELECT drifted';
  end if;

  if pg_catalog.has_table_privilege(v_anon, v_table, 'SELECT')
     and pg_catalog.has_table_privilege(v_authenticated, v_table, 'SELECT')
     and pg_catalog.cardinality(v_anon_columns) = 50
     and pg_catalog.cardinality(v_authenticated_columns) = 50 then
    v_privilege_state := 'broad_preprivacy';
  elsif not pg_catalog.has_table_privilege(v_anon, v_table, 'SELECT')
        and not pg_catalog.has_table_privilege(v_authenticated, v_table, 'SELECT')
        and v_anon_columns = array[
          'id', 'organizer_id', 'title', 'kind', 'description', 'start_at',
          'end_at', 'city', 'expected_pax', 'slots_needed', 'budget_min',
          'budget_max', 'desired_categories', 'dietary_requirements',
          'applications_deadline', 'power_available', 'water_available',
          'notes', 'status', 'visibility', 'awarded_at', 'created_at',
          'updated_at', 'discovery_mode', 'accepted_deal_types',
          'min_fixed_fee', 'min_revenue_share_pct', 'recommended_slots',
          'slot_breakdown', 'application_response_window_hours', 'locality',
          'budget_estimate', 'budget_flexible', 'catering_type',
          'desired_cuisines', 'setup_minutes', 'teardown_minutes',
          'energy_need', 'energy_assistance', 'sanitation_level',
          'extra_services', 'selection_mode', 'assistance_requested',
          'water_provided', 'wc_provided'
        ]::text[]
        and v_authenticated_columns = v_anon_columns then
    v_privilege_state := 'old_candidate';
  elsif not pg_catalog.has_table_privilege(v_anon, v_table, 'SELECT')
        and not pg_catalog.has_table_privilege(v_authenticated, v_table, 'SELECT')
        and v_anon_columns = array[
          'id', 'title', 'kind', 'description', 'start_at', 'city',
          'expected_pax', 'slots_needed', 'budget_min', 'budget_max', 'status',
          'visibility', 'accepted_deal_types', 'min_fixed_fee',
          'min_revenue_share_pct'
        ]::text[]
        and v_authenticated_columns = array[
          'id', 'organizer_id', 'title', 'kind', 'description', 'start_at',
          'end_at', 'city', 'expected_pax', 'slots_needed', 'budget_min',
          'budget_max', 'desired_categories', 'dietary_requirements',
          'applications_deadline', 'power_available', 'notes', 'status',
          'visibility', 'created_at', 'discovery_mode', 'accepted_deal_types',
          'min_fixed_fee', 'min_revenue_share_pct', 'locality',
          'desired_cuisines', 'setup_minutes', 'energy_need',
          'energy_assistance', 'sanitation_level'
        ]::text[] then
    v_privilege_state := 'reconciled';
  end if;

  if v_privilege_state is null then
    raise exception 'public request privacy refused: unsupported table SELECT prestate';
  end if;
end
$preconditions$;

create temporary table airfnb_public_request_privacy_state_20260820
on commit drop
as
select procedure.oid,
       procedure.proowner
  from pg_catalog.pg_proc as procedure
 where procedure.oid in (
   'public.airfnb_match_score(uuid,uuid)'::pg_catalog.regprocedure,
   'public.airfnb_match_scores_batch(uuid[],uuid[])'::pg_catalog.regprocedure,
   'public.airfnb_find_matching_requests(uuid,integer)'::pg_catalog.regprocedure,
   'public.airfnb_find_matching_trucks(uuid,integer)'::pg_catalog.regprocedure,
   'public.airfnb_recommend_trucks_for_request(uuid,integer)'::pg_catalog.regprocedure,
   'public.airfnb_is_admin()'::pg_catalog.regprocedure,
   'public.airfnb_user_owns_invited_truck(uuid)'::pg_catalog.regprocedure,
   'public.airfnb_user_organizes_request(uuid)'::pg_catalog.regprocedure,
   'public.airfnb_private_event_requests(uuid)'::pg_catalog.regprocedure
 );

create temporary table airfnb_public_request_dependency_state_20260820
on commit drop
as
select relation.oid as relation_oid,
       pg_catalog.has_table_privilege(v_service.oid, relation.oid, 'SELECT') as service_table_select,
       (
         select pg_catalog.array_agg(attribute.attname::text order by attribute.attnum)
           from pg_catalog.pg_attribute as attribute
          where attribute.attrelid = relation.oid
            and attribute.attnum > 0
            and not attribute.attisdropped
            and pg_catalog.has_column_privilege(
              v_service.oid,
              relation.oid,
              attribute.attnum,
              'SELECT'
            )
       ) as service_columns,
       (
         select pg_catalog.md5(
                  pg_catalog.string_agg(
                    pg_catalog.concat_ws(
                      '|',
                      policy.polname,
                      policy.polcmd,
                      policy.polpermissive,
                      policy.polroles::text,
                      coalesce(pg_catalog.pg_get_expr(policy.polqual, policy.polrelid), ''),
                      coalesce(pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid), '')
                    ),
                    E'\n' order by policy.polname
                  )
                )
           from pg_catalog.pg_policy as policy
          where policy.polrelid = relation.oid
       ) as policy_sha256_guard
  from pg_catalog.pg_class as relation
  cross join lateral (
    select role.oid
      from pg_catalog.pg_roles as role
     where role.rolname = 'service_role'
  ) as v_service
 where relation.oid in (
   'public.airfnb_truck_categories'::pg_catalog.regclass,
   'public.airfnb_truck_availability'::pg_catalog.regclass
 );

create or replace function public.airfnb_match_category_availability_score(
  p_truck uuid,
  p_request uuid
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce((
    select
      case
        when coalesce(pg_catalog.array_length(request_row.desired_categories, 1), 0) = 0
          then 15
        when exists (
          select 1
            from public.airfnb_truck_categories as truck_category
           where truck_category.truck_id = truck.id
             and truck_category.category_id = any(request_row.desired_categories)
        ) then 30
        else 0
      end
      +
      case
        when exists (
          select 1
            from public.airfnb_truck_availability as availability
           where availability.truck_id = truck.id
             and availability.date = request_row.start_at::date
             and availability.status in ('blocked', 'booked')
        ) then 0
        else 10
      end
      from public.airfnb_trucks as truck
      join public.airfnb_event_requests as request_row
        on request_row.id = p_request
     where auth.uid() is not null
       and truck.id = p_truck
       and truck.status = 'active'
       and request_row.status in ('open', 'reviewing')
       and (
         request_row.visibility = 'public'
         or request_row.organizer_id = auth.uid()
         or exists (
           select 1
             from public.airfnb_profiles as profile
            where profile.id = auth.uid()
              and profile.role in ('admin', 'staff')
         )
         or exists (
           select 1
             from public.airfnb_request_invitations as invitation
             join public.airfnb_trucks as invited_truck
               on invited_truck.id = invitation.truck_id
            where invitation.request_id = request_row.id
              and invited_truck.owner_id = auth.uid()
         )
       )
  ), 0)::numeric
$function$;

create or replace function public.airfnb_match_score(
  p_truck uuid,
  p_request uuid
)
returns numeric
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  score numeric := 0;
  t record;
  r record;
begin
  select truck.id,
         truck.base_city,
         truck.capacity,
         truck.rating_avg,
         truck.featured,
         truck.base_price
    into t
    from public.airfnb_trucks as truck
   where truck.id = p_truck
     and truck.status = 'active';
  if not found then
    return 0;
  end if;

  select request_row.id,
         request_row.status,
         request_row.desired_categories,
         request_row.city,
         request_row.expected_pax,
         request_row.start_at,
         request_row.budget_max
    into r
    from public.airfnb_event_requests as request_row
   where request_row.id = p_request
     and request_row.status in ('open', 'reviewing');
  if not found then
    return 0;
  end if;

  score := score + public.airfnb_match_category_availability_score(t.id, r.id);

  if t.base_city is not null
     and r.city is not null
     and pg_catalog.lower(t.base_city) = pg_catalog.lower(r.city) then
    score := score + 20;
  end if;
  if t.capacity is not null
     and r.expected_pax is not null
     and t.capacity >= r.expected_pax then
    score := score + 15;
  end if;
  if t.rating_avg >= 4.5 then score := score + 10;
  elsif t.rating_avg >= 4.0 then score := score + 5;
  end if;
  if t.featured then score := score + 5; end if;
  if t.base_price is not null
     and r.budget_max is not null
     and t.base_price <= r.budget_max then
    score := score + 10;
  end if;
  return least(score, 100);
end
$function$;

alter function public.airfnb_match_scores_batch(uuid[], uuid[])
  set search_path = '';
alter function public.airfnb_find_matching_requests(uuid, integer)
  set search_path = '';
alter function public.airfnb_find_matching_trucks(uuid, integer)
  set search_path = '';
alter function public.airfnb_recommend_trucks_for_request(uuid, integer)
  set search_path = '';

alter function public.airfnb_is_admin()
  set search_path = '';
alter function public.airfnb_user_owns_invited_truck(uuid)
  set search_path = '';
alter function public.airfnb_user_organizes_request(uuid)
  set search_path = '';
alter function public.airfnb_private_event_requests(uuid)
  set search_path = '';

revoke execute on function public.airfnb_match_score(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke execute on function public.airfnb_match_scores_batch(uuid[], uuid[])
  from public, anon, authenticated, service_role;
revoke execute on function public.airfnb_find_matching_requests(uuid, integer)
  from public, anon, authenticated, service_role;
revoke execute on function public.airfnb_find_matching_trucks(uuid, integer)
  from public, anon, authenticated, service_role;
revoke execute on function public.airfnb_recommend_trucks_for_request(uuid, integer)
  from public, anon, authenticated, service_role;

grant execute on function public.airfnb_match_score(uuid, uuid)
  to authenticated;
grant execute on function public.airfnb_match_scores_batch(uuid[], uuid[])
  to authenticated;
grant execute on function public.airfnb_find_matching_requests(uuid, integer)
  to authenticated;
grant execute on function public.airfnb_find_matching_trucks(uuid, integer)
  to authenticated;
grant execute on function public.airfnb_recommend_trucks_for_request(uuid, integer)
  to authenticated;

revoke execute on function public.airfnb_match_category_availability_score(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.airfnb_match_category_availability_score(uuid, uuid)
  to authenticated;

revoke execute on function public.airfnb_is_admin()
  from public, anon, authenticated, service_role;
grant execute on function public.airfnb_is_admin()
  to anon, authenticated;

revoke execute on function public.airfnb_user_owns_invited_truck(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.airfnb_user_owns_invited_truck(uuid)
  to anon, authenticated, service_role;

revoke execute on function public.airfnb_user_organizes_request(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.airfnb_user_organizes_request(uuid)
  to anon, authenticated, service_role;

revoke execute on function public.airfnb_private_event_requests(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.airfnb_private_event_requests(uuid)
  to authenticated;

revoke select on table public.airfnb_truck_categories
  from public, anon, authenticated;
revoke select (truck_id, category_id)
  on table public.airfnb_truck_categories
  from public, anon, authenticated;

revoke select on table public.airfnb_truck_availability
  from public, anon, authenticated;
revoke select (id, truck_id, date, status, booking_id)
  on table public.airfnb_truck_availability
  from public, anon, authenticated;

revoke select on table public.airfnb_event_requests
  from public, anon, authenticated;
revoke select (
  id,
  organizer_id,
  title,
  kind,
  description,
  start_at,
  end_at,
  city,
  address_id,
  expected_pax,
  slots_needed,
  budget_min,
  budget_max,
  desired_categories,
  dietary_requirements,
  applications_deadline,
  power_available,
  water_available,
  notes,
  status,
  visibility,
  awarded_at,
  created_at,
  updated_at,
  discovery_mode,
  accepted_deal_types,
  min_fixed_fee,
  min_revenue_share_pct,
  recommended_slots,
  slot_breakdown,
  application_response_window_hours,
  contact_name,
  contact_email,
  contact_phone,
  address_line,
  locality,
  budget_estimate,
  budget_flexible,
  catering_type,
  desired_cuisines,
  setup_minutes,
  teardown_minutes,
  energy_need,
  energy_assistance,
  sanitation_level,
  extra_services,
  selection_mode,
  assistance_requested,
  water_provided,
  wc_provided
) on table public.airfnb_event_requests from public, anon, authenticated;

grant select (
  id,
  title,
  kind,
  description,
  start_at,
  city,
  expected_pax,
  slots_needed,
  budget_min,
  budget_max,
  status,
  visibility,
  accepted_deal_types,
  min_fixed_fee,
  min_revenue_share_pct
) on table public.airfnb_event_requests to anon;

grant select (
  id,
  organizer_id,
  title,
  kind,
  description,
  start_at,
  end_at,
  city,
  expected_pax,
  slots_needed,
  budget_min,
  budget_max,
  desired_categories,
  dietary_requirements,
  applications_deadline,
  power_available,
  notes,
  status,
  visibility,
  created_at,
  discovery_mode,
  accepted_deal_types,
  min_fixed_fee,
  min_revenue_share_pct,
  locality,
  desired_cuisines,
  setup_minutes,
  energy_need,
  energy_assistance,
  sanitation_level
) on table public.airfnb_event_requests to authenticated;

grant select on table public.airfnb_event_requests to service_role;

do $postconditions$
declare
  v_table oid := 'public.airfnb_event_requests'::pg_catalog.regclass;
  v_categories oid := 'public.airfnb_truck_categories'::pg_catalog.regclass;
  v_availability oid := 'public.airfnb_truck_availability'::pg_catalog.regclass;
  v_owner oid;
  v_anon oid := (select oid from pg_catalog.pg_roles where rolname = 'anon');
  v_authenticated oid := (select oid from pg_catalog.pg_roles where rolname = 'authenticated');
  v_service_role oid := (select oid from pg_catalog.pg_roles where rolname = 'service_role');
  v_anon_columns text[];
  v_authenticated_columns text[];
begin
  select relation.relowner
    into v_owner
    from pg_catalog.pg_class as relation
   where relation.oid = v_table;

  if exists (
    select 1
      from airfnb_public_request_privacy_state_20260820 as original
      full join (
        select procedure.oid,
               procedure.proowner
          from pg_catalog.pg_proc as procedure
         where procedure.oid in (
           'public.airfnb_match_score(uuid,uuid)'::pg_catalog.regprocedure,
           'public.airfnb_match_scores_batch(uuid[],uuid[])'::pg_catalog.regprocedure,
           'public.airfnb_find_matching_requests(uuid,integer)'::pg_catalog.regprocedure,
           'public.airfnb_find_matching_trucks(uuid,integer)'::pg_catalog.regprocedure,
           'public.airfnb_recommend_trucks_for_request(uuid,integer)'::pg_catalog.regprocedure,
           'public.airfnb_is_admin()'::pg_catalog.regprocedure,
           'public.airfnb_user_owns_invited_truck(uuid)'::pg_catalog.regprocedure,
           'public.airfnb_user_organizes_request(uuid)'::pg_catalog.regprocedure,
           'public.airfnb_private_event_requests(uuid)'::pg_catalog.regprocedure
         )
      ) as reconciled using (oid, proowner)
     where original.oid is null
        or reconciled.oid is null
  ) then
    raise exception 'public request privacy failed: target OID or owner changed';
  end if;

  if (
    select pg_catalog.md5(
             pg_catalog.string_agg(
               pg_catalog.concat_ws(
                 '|',
                 policy.polname,
                 policy.polcmd,
                 policy.polpermissive,
                 policy.polroles::text,
                 coalesce(pg_catalog.pg_get_expr(policy.polqual, policy.polrelid), ''),
                 coalesce(pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid), '')
               ),
               E'\n' order by policy.polname
             )
           )
      from pg_catalog.pg_policy as policy
     where policy.polrelid = v_table
  ) <> 'be3e742b43c1e53d2a5dd22720ad30ce' then
    raise exception 'public request privacy failed: RLS semantics changed';
  end if;

  if exists (
    select 1
      from airfnb_public_request_dependency_state_20260820 as original
      join pg_catalog.pg_class as relation on relation.oid = original.relation_oid
     where original.service_table_select is distinct from
           pg_catalog.has_table_privilege(v_service_role, relation.oid, 'SELECT')
        or original.service_columns is distinct from (
          select pg_catalog.array_agg(attribute.attname::text order by attribute.attnum)
            from pg_catalog.pg_attribute as attribute
           where attribute.attrelid = relation.oid
             and attribute.attnum > 0
             and not attribute.attisdropped
             and pg_catalog.has_column_privilege(
               v_service_role,
               relation.oid,
               attribute.attnum,
               'SELECT'
             )
        )
        or original.policy_sha256_guard is distinct from (
          select pg_catalog.md5(
                   pg_catalog.string_agg(
                     pg_catalog.concat_ws(
                       '|',
                       policy.polname,
                       policy.polcmd,
                       policy.polpermissive,
                       policy.polroles::text,
                       coalesce(pg_catalog.pg_get_expr(policy.polqual, policy.polrelid), ''),
                       coalesce(pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid), '')
                     ),
                     E'\n' order by policy.polname
                   )
                 )
            from pg_catalog.pg_policy as policy
           where policy.polrelid = relation.oid
        )
  ) then
    raise exception 'public request privacy failed: dependency policy or service-role state changed';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_class as relation
      cross join pg_catalog.pg_roles as api_role
     where relation.oid in (v_categories, v_availability)
       and api_role.rolname in ('anon', 'authenticated')
       and pg_catalog.has_table_privilege(api_role.oid, relation.oid, 'SELECT')
  ) or exists (
    select 1
      from pg_catalog.pg_attribute as attribute
      cross join pg_catalog.pg_roles as api_role
     where attribute.attrelid in (v_categories, v_availability)
       and attribute.attnum > 0
       and not attribute.attisdropped
       and api_role.rolname in ('anon', 'authenticated')
       and pg_catalog.has_column_privilege(
         api_role.oid,
         attribute.attrelid,
         attribute.attnum,
         'SELECT'
       )
  ) or exists (
    select 1
      from pg_catalog.pg_class as relation
      cross join lateral pg_catalog.aclexplode(
        coalesce(relation.relacl, pg_catalog.acldefault('r', relation.relowner))
      ) as privilege
     where relation.oid in (v_categories, v_availability)
       and privilege.grantee = 0
       and privilege.privilege_type = 'SELECT'
  ) or exists (
    select 1
      from pg_catalog.pg_attribute as attribute
      cross join lateral pg_catalog.aclexplode(attribute.attacl) as privilege
     where attribute.attrelid in (v_categories, v_availability)
       and attribute.attnum > 0
       and not attribute.attisdropped
       and privilege.grantee = 0
       and privilege.privilege_type = 'SELECT'
  ) then
    raise exception 'public request privacy failed: raw matching dependency SELECT remains';
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_proc as procedure
     where procedure.oid = 'public.airfnb_match_score(uuid,uuid)'::pg_catalog.regprocedure
       and procedure.proowner = v_owner
       and not procedure.prosecdef
       and procedure.provolatile = 's'
       and procedure.proconfig = array['search_path=""']::text[]
       and procedure.prosrc =
$reconciled_match_score$
declare
  score numeric := 0;
  t record;
  r record;
begin
  select truck.id,
         truck.base_city,
         truck.capacity,
         truck.rating_avg,
         truck.featured,
         truck.base_price
    into t
    from public.airfnb_trucks as truck
   where truck.id = p_truck
     and truck.status = 'active';
  if not found then
    return 0;
  end if;

  select request_row.id,
         request_row.status,
         request_row.desired_categories,
         request_row.city,
         request_row.expected_pax,
         request_row.start_at,
         request_row.budget_max
    into r
    from public.airfnb_event_requests as request_row
   where request_row.id = p_request
     and request_row.status in ('open', 'reviewing');
  if not found then
    return 0;
  end if;

  score := score + public.airfnb_match_category_availability_score(t.id, r.id);

  if t.base_city is not null
     and r.city is not null
     and pg_catalog.lower(t.base_city) = pg_catalog.lower(r.city) then
    score := score + 20;
  end if;
  if t.capacity is not null
     and r.expected_pax is not null
     and t.capacity >= r.expected_pax then
    score := score + 15;
  end if;
  if t.rating_avg >= 4.5 then score := score + 10;
  elsif t.rating_avg >= 4.0 then score := score + 5;
  end if;
  if t.featured then score := score + 5; end if;
  if t.base_price is not null
     and r.budget_max is not null
     and t.base_price <= r.budget_max then
    score := score + 10;
  end if;
  return least(score, 100);
end
$reconciled_match_score$
       and pg_catalog.strpos(procedure.prosrc, 'select *') = 0
  ) then
    raise exception 'public request privacy failed: match-score postcondition';
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_language as language on language.oid = procedure.prolang
     where procedure.oid = 'public.airfnb_match_category_availability_score(uuid,uuid)'::pg_catalog.regprocedure
       and procedure.proowner = v_owner
       and procedure.prorettype = 'pg_catalog.numeric'::pg_catalog.regtype
       and not procedure.proretset
       and procedure.prokind = 'f'
       and procedure.provolatile = 's'
       and procedure.prosecdef
       and language.lanname = 'sql'
       and procedure.proconfig = array['search_path=""']::text[]
       and pg_catalog.md5(procedure.prosrc) = '6541cf17b1d05b7e59077326e48e1738'
       and not pg_catalog.has_function_privilege(v_anon, procedure.oid, 'EXECUTE')
       and pg_catalog.has_function_privilege(v_authenticated, procedure.oid, 'EXECUTE')
       and not pg_catalog.has_function_privilege(v_service_role, procedure.oid, 'EXECUTE')
       and not exists (
         select 1
           from pg_catalog.aclexplode(
             coalesce(
               procedure.proacl,
               pg_catalog.acldefault('f', procedure.proowner)
             )
           ) as privilege
          where privilege.grantee = 0
            and privilege.privilege_type = 'EXECUTE'
       )
  ) then
    raise exception 'public request privacy failed: scalar helper postcondition';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_proc as procedure
     where procedure.oid in (
       'public.airfnb_match_scores_batch(uuid[],uuid[])'::pg_catalog.regprocedure,
       'public.airfnb_find_matching_requests(uuid,integer)'::pg_catalog.regprocedure,
       'public.airfnb_find_matching_trucks(uuid,integer)'::pg_catalog.regprocedure,
       'public.airfnb_recommend_trucks_for_request(uuid,integer)'::pg_catalog.regprocedure,
       'public.airfnb_is_admin()'::pg_catalog.regprocedure,
       'public.airfnb_user_owns_invited_truck(uuid)'::pg_catalog.regprocedure,
       'public.airfnb_user_organizes_request(uuid)'::pg_catalog.regprocedure,
       'public.airfnb_private_event_requests(uuid)'::pg_catalog.regprocedure
     )
       and (
         procedure.proowner <> v_owner
         or procedure.proconfig <> array['search_path=""']::text[]
       )
  ) then
    raise exception 'public request privacy failed: helper/RPC owner or path postcondition';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_proc as procedure
     where procedure.oid in (
       'public.airfnb_match_score(uuid,uuid)'::pg_catalog.regprocedure,
       'public.airfnb_match_scores_batch(uuid[],uuid[])'::pg_catalog.regprocedure,
       'public.airfnb_find_matching_requests(uuid,integer)'::pg_catalog.regprocedure,
       'public.airfnb_find_matching_trucks(uuid,integer)'::pg_catalog.regprocedure,
       'public.airfnb_recommend_trucks_for_request(uuid,integer)'::pg_catalog.regprocedure
     )
       and (
         pg_catalog.has_function_privilege(v_anon, procedure.oid, 'EXECUTE')
         or not pg_catalog.has_function_privilege(v_authenticated, procedure.oid, 'EXECUTE')
         or pg_catalog.has_function_privilege(v_service_role, procedure.oid, 'EXECUTE')
         or exists (
           select 1
             from pg_catalog.aclexplode(
               coalesce(
                 procedure.proacl,
                 pg_catalog.acldefault('f', procedure.proowner)
               )
             ) as privilege
            where privilege.grantee = 0
              and privilege.privilege_type = 'EXECUTE'
         )
       )
  ) then
    raise exception 'public request privacy failed: matching RPC ACL postcondition';
  end if;

  select pg_catalog.array_agg(attribute.attname::text order by attribute.attnum)
    into v_anon_columns
    from pg_catalog.pg_attribute as attribute
   where attribute.attrelid = v_table
     and attribute.attnum > 0
     and not attribute.attisdropped
     and pg_catalog.has_column_privilege(v_anon, v_table, attribute.attnum, 'SELECT');

  select pg_catalog.array_agg(attribute.attname::text order by attribute.attnum)
    into v_authenticated_columns
    from pg_catalog.pg_attribute as attribute
   where attribute.attrelid = v_table
     and attribute.attnum > 0
     and not attribute.attisdropped
     and pg_catalog.has_column_privilege(v_authenticated, v_table, attribute.attnum, 'SELECT');

  if pg_catalog.has_table_privilege(v_anon, v_table, 'SELECT')
     or pg_catalog.has_table_privilege(v_authenticated, v_table, 'SELECT')
     or not pg_catalog.has_table_privilege(v_service_role, v_table, 'SELECT')
     or v_anon_columns <> array[
       'id', 'title', 'kind', 'description', 'start_at', 'city',
       'expected_pax', 'slots_needed', 'budget_min', 'budget_max', 'status',
       'visibility', 'accepted_deal_types', 'min_fixed_fee',
       'min_revenue_share_pct'
     ]::text[]
     or v_authenticated_columns <> array[
       'id', 'organizer_id', 'title', 'kind', 'description', 'start_at',
       'end_at', 'city', 'expected_pax', 'slots_needed', 'budget_min',
       'budget_max', 'desired_categories', 'dietary_requirements',
       'applications_deadline', 'power_available', 'notes', 'status',
       'visibility', 'created_at', 'discovery_mode', 'accepted_deal_types',
       'min_fixed_fee', 'min_revenue_share_pct', 'locality',
       'desired_cuisines', 'setup_minutes', 'energy_need',
       'energy_assistance', 'sanitation_level'
     ]::text[]
  then
    raise exception 'public request privacy failed: exact column projection postcondition';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_attribute as attribute
      cross join pg_catalog.pg_roles as api_role
     where attribute.attrelid = v_table
       and attribute.attname in (
         'contact_name',
         'contact_email',
         'contact_phone',
         'address_line',
         'address_id'
       )
       and api_role.rolname in ('anon', 'authenticated')
       and pg_catalog.has_column_privilege(
         api_role.oid,
         v_table,
         attribute.attnum,
         'SELECT'
       )
  ) then
    raise exception 'public request privacy failed: structural PII remains selectable';
  end if;
end
$postconditions$;

commit;
