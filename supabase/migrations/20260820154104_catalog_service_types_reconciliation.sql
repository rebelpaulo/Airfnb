-- Reconcile supplier moderation, the three supplier service directions and
-- the public catalog projection after the Storage visibility boundary.
-- This migration is deliberately atomic and accepts only the exact legacy,
-- 2026-08-18 candidate, or already-reconciled catalog prestates.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';
set local idle_in_transaction_session_timeout = '60s';

do $preconditions$
declare
  v_owner oid;
  v_anon oid;
  v_authenticated oid;
  v_service_role oid;
  v_truck_shape text;
  v_view_columns name[];
  v_view_hash text;
  v_legacy boolean := false;
  v_old_candidate boolean := false;
  v_final boolean := false;
  v_relation record;
  v_actual_shape text;
  v_role name;
  v_target record;
  v_column record;
  v_expected_select boolean;
  v_expected_insert boolean;
  v_expected_update boolean;
begin
  select pg_catalog.max(role.oid) filter (where role.rolname = 'anon'),
         pg_catalog.max(role.oid) filter (where role.rolname = 'authenticated'),
         pg_catalog.max(role.oid) filter (where role.rolname = 'service_role')
    into v_anon, v_authenticated, v_service_role
    from pg_catalog.pg_roles as role
   where role.rolname in ('anon', 'authenticated', 'service_role');

  if v_anon is null or v_authenticated is null or v_service_role is null then
    raise exception 'catalog reconciliation refused: required API roles are missing';
  end if;

  select relation.relowner
    into v_owner
    from pg_catalog.pg_class as relation
   where relation.oid = pg_catalog.to_regclass('public.airfnb_trucks');

  if v_owner is null or not exists (
    select 1
      from pg_catalog.pg_roles as owner_role
     where owner_role.oid = v_owner
       and owner_role.rolbypassrls
       and owner_role.rolname not in ('anon', 'authenticated', 'service_role')
  ) then
    raise exception 'catalog reconciliation refused: trusted table owner is missing';
  end if;

  if exists (
    select 1
      from unnest(array[
        'public.airfnb_categories'::pg_catalog.regclass,
        'public.airfnb_truck_images'::pg_catalog.regclass,
        'public.airfnb_truck_categories'::pg_catalog.regclass,
        'public.airfnb_v_truck_card'::pg_catalog.regclass
      ]) as target(relation_oid)
      join pg_catalog.pg_class as relation on relation.oid = target.relation_oid
     where relation.relowner <> v_owner
  ) then
    raise exception 'catalog reconciliation refused: relation owner alignment drifted';
  end if;

  for v_relation in
    select *
      from (values
        ('airfnb_categories', '4587ddbb2d28f8009c991c5e89e7a177'),
        ('airfnb_truck_images', '6c68db980e2deb4e9ce77ab1670b8f03'),
        ('airfnb_truck_categories', '2026b21e4660e0c0e5fb6f6ce7b00973')
      ) as expected(relation_name, shape_hash)
  loop
    select pg_catalog.md5(
             pg_catalog.string_agg(
               pg_catalog.format(
                 '%s:%s:%s:%s',
                 attribute.attname,
                 pg_catalog.format_type(attribute.atttypid, attribute.atttypmod),
                 attribute.attnotnull,
                 coalesce(pg_catalog.pg_get_expr(default_value.adbin, default_value.adrelid), '')
               ),
               ',' order by attribute.attnum
             )
           )
      into v_actual_shape
      from pg_catalog.pg_attribute as attribute
      left join pg_catalog.pg_attrdef as default_value
        on default_value.adrelid = attribute.attrelid
       and default_value.adnum = attribute.attnum
     where attribute.attrelid = pg_catalog.to_regclass(
             pg_catalog.format('public.%I', v_relation.relation_name)
           )
       and attribute.attnum > 0
       and not attribute.attisdropped;

    if v_actual_shape is distinct from v_relation.shape_hash then
      raise exception 'catalog reconciliation refused: public.% shape drifted',
        v_relation.relation_name;
    end if;
  end loop;

  select pg_catalog.md5(
           pg_catalog.string_agg(
             pg_catalog.format(
               '%s:%s:%s:%s',
               attribute.attname,
               pg_catalog.format_type(attribute.atttypid, attribute.atttypmod),
               attribute.attnotnull,
               coalesce(pg_catalog.pg_get_expr(default_value.adbin, default_value.adrelid), '')
             ),
             ',' order by attribute.attnum
           )
         )
    into v_truck_shape
    from pg_catalog.pg_attribute as attribute
    left join pg_catalog.pg_attrdef as default_value
      on default_value.adrelid = attribute.attrelid
     and default_value.adnum = attribute.attnum
   where attribute.attrelid = 'public.airfnb_trucks'::pg_catalog.regclass
     and attribute.attnum > 0
     and not attribute.attisdropped;

  if v_truck_shape not in (
    '3be0b23364d56d24afc62c4f604c1753',
    '791c439172d36c4bad40b9cfdf1b34c8'
  ) then
    raise exception 'catalog reconciliation refused: supplier table shape drifted';
  end if;

  if exists (
    select 1
      from unnest(array[
        'public.airfnb_trucks'::pg_catalog.regclass,
        'public.airfnb_categories'::pg_catalog.regclass,
        'public.airfnb_truck_images'::pg_catalog.regclass,
        'public.airfnb_truck_categories'::pg_catalog.regclass
      ]) as target(relation_oid)
      join pg_catalog.pg_class as relation on relation.oid = target.relation_oid
     where not relation.relrowsecurity or relation.relforcerowsecurity
  ) then
    raise exception 'catalog reconciliation refused: RLS mode drifted';
  end if;

  -- The immediately preceding Storage migration must already have closed the
  -- child visibility boundary before this migration grants view columns.
  if pg_catalog.to_regprocedure('public.airfnb_can_manage_truck(text)') is null
     or pg_catalog.to_regprocedure('public.airfnb_can_read_truck_child(text)') is null
     or exists (
       select 1
         from unnest(array[
           'public.airfnb_can_manage_truck(text)'::pg_catalog.regprocedure,
           'public.airfnb_can_read_truck_child(text)'::pg_catalog.regprocedure
         ]) as target(function_oid)
         join pg_catalog.pg_proc as procedure on procedure.oid = target.function_oid
        where procedure.proowner <> v_owner
           or not procedure.prosecdef
           or procedure.provolatile <> 's'
           or procedure.proconfig <> array['search_path=""']::text[]
           or pg_catalog.md5(procedure.prosrc) <> case procedure.oid
             when 'public.airfnb_can_manage_truck(text)'::pg_catalog.regprocedure
               then '982caee25d35d0ac9dfe1d3a343ab0a5'
             when 'public.airfnb_can_read_truck_child(text)'::pg_catalog.regprocedure
               then '63f8f31bbf345d3075b489257b6fdea5'
           end
           or exists (
             select 1
               from pg_catalog.aclexplode(
                 coalesce(procedure.proacl, pg_catalog.acldefault('f', procedure.proowner))
               ) as privilege
              where privilege.grantee = 0
                and privilege.privilege_type = 'EXECUTE'
           )
     )
     or pg_catalog.has_function_privilege(v_anon, 'public.airfnb_can_manage_truck(text)', 'EXECUTE')
     or not pg_catalog.has_function_privilege(v_authenticated, 'public.airfnb_can_manage_truck(text)', 'EXECUTE')
     or pg_catalog.has_function_privilege(v_service_role, 'public.airfnb_can_manage_truck(text)', 'EXECUTE')
     or not pg_catalog.has_function_privilege(v_anon, 'public.airfnb_can_read_truck_child(text)', 'EXECUTE')
     or not pg_catalog.has_function_privilege(v_authenticated, 'public.airfnb_can_read_truck_child(text)', 'EXECUTE')
     or pg_catalog.has_function_privilege(v_service_role, 'public.airfnb_can_read_truck_child(text)', 'EXECUTE')
  then
    raise exception 'catalog reconciliation refused: final Storage helper boundary is absent';
  end if;

  if (
    select pg_catalog.count(*)
      from pg_catalog.pg_policy
     where polrelid in (
       'public.airfnb_truck_images'::pg_catalog.regclass,
       'public.airfnb_menu_items'::pg_catalog.regclass,
       'public.airfnb_truck_categories'::pg_catalog.regclass
     )
  ) <> 6 or exists (
    select 1
      from (values
        ('public.airfnb_truck_images'::pg_catalog.regclass,
         'airfnb_truck_images_read'::name, 'r'::"char"),
        ('public.airfnb_truck_images'::pg_catalog.regclass,
         'airfnb_truck_images_write'::name, '*'::"char"),
        ('public.airfnb_menu_items'::pg_catalog.regclass,
         'airfnb_menu_items_read'::name, 'r'::"char"),
        ('public.airfnb_menu_items'::pg_catalog.regclass,
         'airfnb_menu_items_write'::name, '*'::"char"),
        ('public.airfnb_truck_categories'::pg_catalog.regclass,
         'airfnb_truck_cat_read'::name, 'r'::"char"),
        ('public.airfnb_truck_categories'::pg_catalog.regclass,
         'airfnb_truck_cat_write'::name, '*'::"char")
      ) as expected(relation_oid, policy_name, command)
     where not exists (
       select 1
         from pg_catalog.pg_policy as policy
        where policy.polrelid = expected.relation_oid
          and policy.polname = expected.policy_name
          and policy.polcmd = expected.command
     )
  ) or exists (
    select 1
      from pg_catalog.pg_policy as policy
     where policy.polrelid in (
       'public.airfnb_truck_images'::pg_catalog.regclass,
       'public.airfnb_menu_items'::pg_catalog.regclass,
       'public.airfnb_truck_categories'::pg_catalog.regclass
     )
       and (
         not policy.polpermissive
         or policy.polcmd not in ('r', '*')
         or policy.polcmd = 'r' and (
           policy.polroles <> array[v_anon, v_authenticated]
           or pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
                <> 'airfnb_can_read_truck_child((truck_id)::text)'
           or policy.polwithcheck is not null
         )
         or policy.polcmd = '*' and (
           policy.polroles <> array[v_authenticated]
           or pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
                <> 'airfnb_can_manage_truck((truck_id)::text)'
           or pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
                <> 'airfnb_can_manage_truck((truck_id)::text)'
         )
       )
  ) then
    raise exception 'catalog reconciliation refused: final Storage child policies differ';
  end if;

  if (
    select pg_catalog.count(*)
      from pg_catalog.pg_policy
     where polrelid = 'public.airfnb_categories'::pg_catalog.regclass
  ) <> 2 or not exists (
    select 1 from pg_catalog.pg_policy
     where polrelid = 'public.airfnb_categories'::pg_catalog.regclass
       and polname = 'airfnb_categories_read'
       and polpermissive
       and polcmd = 'r'
       and polroles = array[0::oid]
       and pg_catalog.pg_get_expr(polqual, polrelid) = 'true'
       and polwithcheck is null
  ) or not exists (
    select 1 from pg_catalog.pg_policy
     where polrelid = 'public.airfnb_categories'::pg_catalog.regclass
       and polname = 'airfnb_categories_admin_write'
       and polpermissive
       and polcmd = '*'
       and polroles = array[0::oid]
       and pg_catalog.pg_get_expr(polqual, polrelid) = 'airfnb_is_admin()'
       and pg_catalog.pg_get_expr(polwithcheck, polrelid) = 'airfnb_is_admin()'
  ) then
    raise exception 'catalog reconciliation refused: category policies drifted';
  end if;

  -- Preserve the exact privacy-final identity boundary plus the resolved
  -- admin, messaging-rating and timestamp functions. The reconciliation may
  -- only add the moderation guard; equivalent-but-different ACLs are refused.
  if exists (
    select 1
      from (values
        ('public.airfnb_is_admin()'::pg_catalog.regprocedure,
         'aa950c573de3ffe4835f7851c09a0631', true, 's'::"char",
         array['search_path=""']::text[], false,
         array[v_owner, v_anon, v_authenticated]::oid[]),
        ('public.airfnb_admin_approve_truck(uuid)'::pg_catalog.regprocedure,
         'c7ea3894d04b6a96a6a0b77d4184d1bd', true, 'v'::"char",
         array['search_path=pg_catalog, public']::text[], false,
         array[v_owner, v_authenticated]::oid[]),
        ('public.airfnb_admin_reject_truck(uuid,text)'::pg_catalog.regprocedure,
         '2d526fe2ff72eb835bbf054aa526828a', true, 'v'::"char",
         array['search_path=pg_catalog, public']::text[], false,
         array[v_owner, v_authenticated]::oid[]),
        ('public.airfnb_recalc_truck_rating()'::pg_catalog.regprocedure,
         '06b8f300efdd0e8d2d418a8ae0ca48e5', true, 'v'::"char",
         array['search_path=pg_catalog, public']::text[], false,
         array[v_owner]::oid[]),
        ('public.airfnb_touch_updated_at()'::pg_catalog.regprocedure,
         '7eb7a124693fea28124edfd2e7860d87', false, 'v'::"char",
         array['search_path=pg_catalog, public']::text[], true,
         array[]::oid[])
      ) as expected(
        function_oid, body_hash, security_definer, volatility, config,
        acl_is_null, execute_grantees
      )
      join pg_catalog.pg_proc as procedure on procedure.oid = expected.function_oid
     where procedure.proowner <> v_owner
        or pg_catalog.md5(procedure.prosrc) <> expected.body_hash
        or procedure.prosecdef <> expected.security_definer
        or procedure.provolatile <> expected.volatility
        or procedure.proconfig is distinct from expected.config
        or (procedure.proacl is null) <> expected.acl_is_null
        or (
          not expected.acl_is_null and exists (
            select 1
              from pg_catalog.aclexplode(procedure.proacl) as privilege
             where privilege.grantor <> v_owner
                or privilege.privilege_type <> 'EXECUTE'
                or privilege.is_grantable
          )
        )
        or (
          not expected.acl_is_null and (
            select pg_catalog.array_agg(privilege.grantee order by privilege.grantee)
              from pg_catalog.aclexplode(procedure.proacl) as privilege
          ) is distinct from (
            select pg_catalog.array_agg(grantee order by grantee)
              from pg_catalog.unnest(expected.execute_grantees) as grantee
          )
        )
  ) or (
    select pg_catalog.count(*)
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'airfnb_is_admin', 'airfnb_admin_approve_truck',
         'airfnb_admin_reject_truck', 'airfnb_recalc_truck_rating',
         'airfnb_touch_updated_at'
       )
  ) <> 5 then
    raise exception 'catalog reconciliation refused: trusted function body/config/ACL drifted';
  end if;

  if (
    select pg_catalog.md5(
             pg_catalog.string_agg(
               pg_catalog.format('%s:%s:%s', truck.id, truck.rating_avg, truck.rating_count),
               ',' order by truck.id
             )
           )
      from public.airfnb_trucks as truck
  ) <> 'b7601dc5d1de93f854aaaf10085c33f7' then
    raise exception 'catalog reconciliation refused: seeded rating aggregates drifted';
  end if;

  select pg_catalog.array_agg(attribute.attname order by attribute.attnum),
         pg_catalog.md5(pg_catalog.pg_get_viewdef('public.airfnb_v_truck_card'::pg_catalog.regclass, true))
    into v_view_columns, v_view_hash
    from pg_catalog.pg_attribute as attribute
   where attribute.attrelid = 'public.airfnb_v_truck_card'::pg_catalog.regclass
     and attribute.attnum > 0
     and not attribute.attisdropped;

  if (select relation.reloptions from pg_catalog.pg_class as relation
       where relation.oid = 'public.airfnb_v_truck_card'::pg_catalog.regclass)
       is distinct from array['security_invoker=true']::text[] then
    raise exception 'catalog reconciliation refused: catalog view security mode drifted';
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_policy as policy
     where policy.polrelid = 'public.airfnb_trucks'::pg_catalog.regclass
       and policy.polname = 'airfnb_trucks_public_read'
       and policy.polpermissive
       and policy.polcmd = 'r'
       and policy.polroles = array[0::oid]
       and pg_catalog.md5(pg_catalog.pg_get_expr(policy.polqual, policy.polrelid))
             = '1b2f127482edf82fb4021bbdf1b7fdc3'
       and policy.polwithcheck is null
  ) then
    raise exception 'catalog reconciliation refused: public supplier read policy drifted';
  end if;

  if pg_catalog.to_regtype('public.airfnb_service_type') is null then
    if exists (
      select 1 from pg_catalog.pg_attribute
       where attrelid = 'public.airfnb_trucks'::pg_catalog.regclass
         and attname = 'service_type'
         and attnum > 0 and not attisdropped
    ) or exists (
      select 1 from pg_catalog.pg_indexes
       where schemaname = 'public' and tablename = 'airfnb_trucks'
         and indexname = 'airfnb_trucks_active_service_type_idx'
    ) then
      raise exception 'catalog reconciliation refused: partial legacy service-type state';
    end if;
  else
    if not exists (
      select 1
        from pg_catalog.pg_type as data_type
        join pg_catalog.pg_namespace as namespace on namespace.oid = data_type.typnamespace
       where data_type.oid = pg_catalog.to_regtype('public.airfnb_service_type')
         and namespace.nspname = 'public'
         and data_type.typtype = 'e'
         and data_type.typowner = v_owner
    ) or (
      select pg_catalog.array_agg(value.enumlabel order by value.enumsortorder)
        from pg_catalog.pg_enum as value
       where value.enumtypid = pg_catalog.to_regtype('public.airfnb_service_type')
    ) is distinct from array['food_truck','catering','bar']::name[] or (
      select pg_catalog.count(*)
        from pg_catalog.pg_enum as value
       where value.enumtypid = pg_catalog.to_regtype('public.airfnb_service_type')
    ) <> 3 or not exists (
      select 1
        from pg_catalog.pg_attribute as attribute
        join pg_catalog.pg_attrdef as default_value
          on default_value.adrelid = attribute.attrelid
         and default_value.adnum = attribute.attnum
       where attribute.attrelid = 'public.airfnb_trucks'::pg_catalog.regclass
         and attribute.attname = 'service_type'
         and attribute.atttypid = pg_catalog.to_regtype('public.airfnb_service_type')
         and attribute.attnotnull
         and pg_catalog.pg_get_expr(default_value.adbin, default_value.adrelid)
               = '''food_truck''::airfnb_service_type'
    ) or exists (
      select 1 from public.airfnb_trucks as truck where truck.service_type is null
    ) or (
      select pg_catalog.count(*)
        from pg_catalog.pg_indexes
       where schemaname = 'public' and tablename = 'airfnb_trucks'
         and indexname = 'airfnb_trucks_active_service_type_idx'
    ) <> 1 or not exists (
      select 1
        from pg_catalog.pg_indexes
       where schemaname = 'public' and tablename = 'airfnb_trucks'
         and indexname = 'airfnb_trucks_active_service_type_idx'
         and indexdef = 'CREATE INDEX airfnb_trucks_active_service_type_idx ON public.airfnb_trucks USING btree (service_type) WHERE (status = ''active''::airfnb_truck_status)'
    ) then
      raise exception 'catalog reconciliation refused: service-type schema/index drifted';
    end if;
  end if;

  if pg_catalog.to_regprocedure('public.airfnb_guard_truck_moderation()') is null then
    if exists (
      select 1 from pg_catalog.pg_trigger
       where tgrelid = 'public.airfnb_trucks'::pg_catalog.regclass
         and tgname = 'airfnb_trg_trucks_moderation'
         and not tgisinternal
    ) or (
      select pg_catalog.array_agg(policy.polname order by policy.polname)
        from pg_catalog.pg_policy as policy
       where policy.polrelid = 'public.airfnb_trucks'::pg_catalog.regclass
    ) is distinct from array[
      'airfnb_trucks_owner_write','airfnb_trucks_public_read'
    ]::name[] or not exists (
      select 1
        from pg_catalog.pg_policy as policy
       where policy.polrelid = 'public.airfnb_trucks'::pg_catalog.regclass
         and policy.polname = 'airfnb_trucks_owner_write'
         and policy.polpermissive
         and policy.polcmd = '*'
         and policy.polroles = array[0::oid]
         and pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
               = '((owner_id = auth.uid()) OR airfnb_is_admin())'
         and pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
               = '((owner_id = auth.uid()) OR airfnb_is_admin())'
    ) then
      raise exception 'catalog reconciliation refused: legacy moderation state drifted';
    end if;
  else
    if (
      select pg_catalog.count(*)
        from pg_catalog.pg_proc as procedure
        join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
       where namespace.nspname = 'public'
         and procedure.proname = 'airfnb_guard_truck_moderation'
    ) <> 1 or not exists (
      select 1
        from pg_catalog.pg_proc as procedure
       where procedure.oid = pg_catalog.to_regprocedure('public.airfnb_guard_truck_moderation()')
         and procedure.proowner = v_owner
         and not procedure.prosecdef
         and procedure.provolatile = 'v'
         and procedure.proconfig = array['search_path=pg_catalog, public']::text[]
         and pg_catalog.md5(procedure.prosrc) = '9580d50b368d29269983025249704dda'
         and not exists (
           select 1
             from pg_catalog.aclexplode(
               coalesce(procedure.proacl, pg_catalog.acldefault('f', procedure.proowner))
             ) as privilege
            where privilege.grantee in (0, v_anon, v_authenticated, v_service_role)
              and privilege.privilege_type = 'EXECUTE'
         )
    ) or (
      select pg_catalog.count(*)
        from pg_catalog.pg_trigger as trigger
       where trigger.tgrelid = 'public.airfnb_trucks'::pg_catalog.regclass
         and trigger.tgname = 'airfnb_trg_trucks_moderation'
         and not trigger.tgisinternal
    ) <> 1 or not exists (
      select 1
        from pg_catalog.pg_trigger as trigger
       where trigger.tgrelid = 'public.airfnb_trucks'::pg_catalog.regclass
         and trigger.tgname = 'airfnb_trg_trucks_moderation'
         and not trigger.tgisinternal
         and trigger.tgenabled = 'O'
         and trigger.tgtype = 23
         and trigger.tgnargs = 0
         and trigger.tgfoid = pg_catalog.to_regprocedure('public.airfnb_guard_truck_moderation()')
    ) or (
      select pg_catalog.array_agg(policy.polname order by policy.polname)
        from pg_catalog.pg_policy as policy
       where policy.polrelid = 'public.airfnb_trucks'::pg_catalog.regclass
    ) is distinct from array[
      'airfnb_trucks_owner_insert','airfnb_trucks_owner_update',
      'airfnb_trucks_public_read'
    ]::name[] or not exists (
      select 1
        from pg_catalog.pg_policy as policy
       where policy.polrelid = 'public.airfnb_trucks'::pg_catalog.regclass
         and policy.polname = 'airfnb_trucks_owner_insert'
         and policy.polpermissive
         and policy.polcmd = 'a'
         and policy.polroles = array[v_authenticated]
         and policy.polqual is null
         and pg_catalog.md5(pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid))
               = '27c40b82371b4a3e30a272b5b6712a23'
    ) or not exists (
      select 1
        from pg_catalog.pg_policy as policy
       where policy.polrelid = 'public.airfnb_trucks'::pg_catalog.regclass
         and policy.polname = 'airfnb_trucks_owner_update'
         and policy.polpermissive
         and policy.polcmd = 'w'
         and policy.polroles = array[v_authenticated]
         and pg_catalog.md5(pg_catalog.pg_get_expr(policy.polqual, policy.polrelid))
               = '27c40b82371b4a3e30a272b5b6712a23'
         and pg_catalog.md5(pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid))
               = '27c40b82371b4a3e30a272b5b6712a23'
    ) then
      raise exception 'catalog reconciliation refused: candidate moderation state drifted';
    end if;
  end if;

  -- Exact legacy state: no service direction, no moderation trigger/function,
  -- the 27-column image-kind view and the original owner FOR ALL policy.
  v_legacy :=
    v_truck_shape = '3be0b23364d56d24afc62c4f604c1753'
    and pg_catalog.to_regtype('public.airfnb_service_type') is null
    and pg_catalog.to_regprocedure('public.airfnb_guard_truck_moderation()') is null
    and not exists (
      select 1 from pg_catalog.pg_trigger
       where tgrelid = 'public.airfnb_trucks'::pg_catalog.regclass
         and tgname = 'airfnb_trg_trucks_moderation'
         and not tgisinternal
    )
    and not exists (
      select 1 from pg_catalog.pg_indexes
       where schemaname = 'public'
         and tablename = 'airfnb_trucks'
         and indexname = 'airfnb_trucks_active_service_type_idx'
    )
    and v_view_columns = array[
      'id','slug','name','tagline','base_city','capacity','base_price',
      'price_per_pax','min_event_pax','max_event_pax','service_radius_km',
      'cuisine_types','dietary_options','catering_type','serves',
      'setup_minutes','teardown_minutes','power_required_kw',
      'sanitation_required','compatible_event_kinds','rating_avg',
      'rating_count','featured','status','cover_url','gallery_urls',
      'category_slugs'
    ]::name[]
    and v_view_hash = '5e17d15485c2be8af68157568ba84028'
    and (
      select pg_catalog.array_agg(policy.polname order by policy.polname)
        from pg_catalog.pg_policy as policy
       where policy.polrelid = 'public.airfnb_trucks'::pg_catalog.regclass
    ) = array['airfnb_trucks_owner_write','airfnb_trucks_public_read']::name[];

  -- Candidate/final structural state is the exact August candidate. The final
  -- state differs only by the least-privilege underlying view grants.
  if v_truck_shape = '791c439172d36c4bad40b9cfdf1b34c8'
     and pg_catalog.to_regtype('public.airfnb_service_type') is not null
     and pg_catalog.to_regprocedure('public.airfnb_guard_truck_moderation()') is not null
     and v_view_columns = array[
       'id','slug','name','tagline','base_city','capacity','base_price',
       'price_per_pax','min_event_pax','max_event_pax','service_radius_km',
       'cuisine_types','dietary_options','catering_type','serves',
       'setup_minutes','teardown_minutes','power_required_kw',
       'sanitation_required','compatible_event_kinds','rating_avg',
       'rating_count','featured','status','cover_url','gallery_urls',
       'category_slugs','service_type'
     ]::name[]
     and v_view_hash in (
       'd252ca591e49263980a5072107ff8fc0',
       'c3e262896aa919d75361132feff47380'
     )
     and (
       select pg_catalog.array_agg(policy.polname order by policy.polname)
         from pg_catalog.pg_policy as policy
        where policy.polrelid = 'public.airfnb_trucks'::pg_catalog.regclass
     ) = array[
       'airfnb_trucks_owner_insert','airfnb_trucks_owner_update',
       'airfnb_trucks_public_read'
     ]::name[]
     and exists (
       select 1 from pg_catalog.pg_proc as procedure
        where procedure.oid = pg_catalog.to_regprocedure('public.airfnb_guard_truck_moderation()')
          and procedure.proowner = v_owner
          and not procedure.prosecdef
          and procedure.provolatile = 'v'
          and procedure.proconfig = array['search_path=pg_catalog, public']::text[]
          and pg_catalog.md5(procedure.prosrc) = '9580d50b368d29269983025249704dda'
     )
     and exists (
       select 1 from pg_catalog.pg_trigger
        where tgrelid = 'public.airfnb_trucks'::pg_catalog.regclass
          and tgname = 'airfnb_trg_trucks_moderation'
          and not tgisinternal
          and tgenabled = 'O'
          and tgfoid = pg_catalog.to_regprocedure('public.airfnb_guard_truck_moderation()')
     )
  then
    v_final :=
      v_view_hash = 'c3e262896aa919d75361132feff47380';
    v_old_candidate :=
      v_view_hash = 'd252ca591e49263980a5072107ff8fc0';
  end if;

  -- Pin the full API-role ACL state before any write. Candidate mutation
  -- allowlists are exact; the old state has no explicit base-column SELECT,
  -- while the final state has exactly the columns consumed by the view.
  if v_legacy then
    if not pg_catalog.has_table_privilege(v_authenticated, 'public.airfnb_trucks', 'SELECT')
       or not pg_catalog.has_table_privilege(v_authenticated, 'public.airfnb_trucks', 'INSERT')
       or not pg_catalog.has_table_privilege(v_authenticated, 'public.airfnb_trucks', 'UPDATE')
       or not pg_catalog.has_table_privilege(v_authenticated, 'public.airfnb_trucks', 'DELETE')
       or pg_catalog.has_table_privilege(v_authenticated, 'public.airfnb_trucks', 'TRUNCATE')
       or pg_catalog.has_table_privilege(v_authenticated, 'public.airfnb_trucks', 'REFERENCES')
       or pg_catalog.has_table_privilege(v_authenticated, 'public.airfnb_trucks', 'TRIGGER')
       or exists (
         select 1
           from unnest(array['anon'::name, 'service_role'::name]) as role_name(name)
          where pg_catalog.has_table_privilege(role_name.name, 'public.airfnb_trucks', 'SELECT')
             or pg_catalog.has_table_privilege(role_name.name, 'public.airfnb_trucks', 'INSERT')
             or pg_catalog.has_table_privilege(role_name.name, 'public.airfnb_trucks', 'UPDATE')
             or pg_catalog.has_table_privilege(role_name.name, 'public.airfnb_trucks', 'DELETE')
       )
       or exists (
         select 1
           from pg_catalog.pg_attribute as attribute
           cross join lateral pg_catalog.aclexplode(attribute.attacl) as privilege
          where attribute.attrelid = 'public.airfnb_trucks'::pg_catalog.regclass
            and attribute.attnum > 0 and not attribute.attisdropped
            and privilege.privilege_type in ('SELECT','INSERT','UPDATE','REFERENCES')
       )
       or exists (
         select 1
           from pg_catalog.pg_class as relation
           cross join lateral pg_catalog.aclexplode(
             coalesce(relation.relacl, pg_catalog.acldefault('r', relation.relowner))
           ) as privilege
          where relation.oid = 'public.airfnb_v_truck_card'::pg_catalog.regclass
            and privilege.grantee <> v_owner
       ) then
      raise exception 'catalog reconciliation refused: legacy ACL state drifted';
    end if;

    for v_target in
      select relation_oid
        from (values
          ('public.airfnb_trucks'::pg_catalog.regclass),
          ('public.airfnb_truck_images'::pg_catalog.regclass),
          ('public.airfnb_truck_categories'::pg_catalog.regclass),
          ('public.airfnb_categories'::pg_catalog.regclass)
        ) as expected(relation_oid)
    loop
      foreach v_role in array array['anon'::name, 'authenticated'::name, 'service_role'::name]
      loop
        if (
          v_target.relation_oid = 'public.airfnb_trucks'::pg_catalog.regclass
          and v_role = 'authenticated'
        ) <> pg_catalog.has_table_privilege(v_role, v_target.relation_oid, 'SELECT') then
          raise exception 'catalog reconciliation refused: legacy base SELECT table ACL drifted';
        end if;
      end loop;

      if exists (
        select 1
          from pg_catalog.pg_attribute as attribute
          cross join lateral pg_catalog.aclexplode(attribute.attacl) as privilege
         where attribute.attrelid = v_target.relation_oid
           and attribute.attnum > 0 and not attribute.attisdropped
           and privilege.privilege_type = 'SELECT'
      ) or exists (
        select 1
          from pg_catalog.pg_class as relation
          cross join lateral pg_catalog.aclexplode(relation.relacl) as privilege
         where relation.oid = v_target.relation_oid
           and privilege.privilege_type = 'SELECT'
           and privilege.grantee not in (
             v_owner,
             case when v_target.relation_oid = 'public.airfnb_trucks'::pg_catalog.regclass
                  then v_authenticated else v_owner end
           )
      ) then
        raise exception 'catalog reconciliation refused: legacy base SELECT grantee drifted';
      end if;
    end loop;
  elsif v_old_candidate or v_final then
    foreach v_role in array array['anon'::name, 'authenticated'::name, 'service_role'::name]
    loop
      if pg_catalog.has_table_privilege(v_role, 'public.airfnb_trucks', 'INSERT')
         or pg_catalog.has_table_privilege(v_role, 'public.airfnb_trucks', 'UPDATE')
         or pg_catalog.has_table_privilege(v_role, 'public.airfnb_trucks', 'DELETE') then
        raise exception 'catalog reconciliation refused: broad mutation ACL for %', v_role;
      end if;
    end loop;

    if not pg_catalog.has_table_privilege(v_authenticated, 'public.airfnb_v_truck_card', 'SELECT')
       or not pg_catalog.has_table_privilege(v_anon, 'public.airfnb_v_truck_card', 'SELECT')
       or not pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_v_truck_card', 'SELECT')
       or exists (
         select 1
           from pg_catalog.pg_class as relation
           cross join lateral pg_catalog.aclexplode(
             coalesce(relation.relacl, pg_catalog.acldefault('r', relation.relowner))
           ) as privilege
          where relation.oid = 'public.airfnb_v_truck_card'::pg_catalog.regclass
            and (
              privilege.grantee not in (v_owner, v_anon, v_authenticated, v_service_role)
              or privilege.grantee in (v_anon, v_authenticated, v_service_role)
                 and privilege.privilege_type <> 'SELECT'
            )
       ) then
      raise exception 'catalog reconciliation refused: view ACL state drifted';
    end if;

    for v_column in
      select attribute.attname
        from pg_catalog.pg_attribute as attribute
       where attribute.attrelid = 'public.airfnb_trucks'::pg_catalog.regclass
         and attribute.attnum > 0 and not attribute.attisdropped
    loop
      v_expected_insert := v_column.attname = any(array[
        'owner_id','slug','name','tagline','description','base_city',
        'service_radius_km','capacity','min_event_pax','max_event_pax',
        'base_price','price_per_pax','setup_minutes','power_required_kw',
        'needs_water','dimensions_m','status','cuisine_types','dietary_options',
        'teardown_minutes','sanitation_required','catering_type','serves',
        'compatible_event_kinds','service_type'
      ]::name[]);
      v_expected_update := v_column.attname = any(array[
        'name','tagline','description','base_city','service_radius_km','capacity',
        'min_event_pax','max_event_pax','base_price','price_per_pax',
        'setup_minutes','power_required_kw','needs_water','dimensions_m','status',
        'cuisine_types','dietary_options','teardown_minutes',
        'sanitation_required','catering_type','serves',
        'compatible_event_kinds','service_type'
      ]::name[]);

      if pg_catalog.has_column_privilege(
           'authenticated', 'public.airfnb_trucks', v_column.attname, 'INSERT'
         ) <> v_expected_insert
         or pg_catalog.has_column_privilege(
           'authenticated', 'public.airfnb_trucks', v_column.attname, 'UPDATE'
         ) <> v_expected_update
         or pg_catalog.has_column_privilege(
           'anon', 'public.airfnb_trucks', v_column.attname, 'INSERT'
         )
         or pg_catalog.has_column_privilege(
           'anon', 'public.airfnb_trucks', v_column.attname, 'UPDATE'
         )
         or pg_catalog.has_column_privilege(
           'service_role', 'public.airfnb_trucks', v_column.attname, 'INSERT'
         )
         or pg_catalog.has_column_privilege(
           'service_role', 'public.airfnb_trucks', v_column.attname, 'UPDATE'
         ) then
        raise exception 'catalog reconciliation refused: mutation column ACL drifted for %',
          v_column.attname;
      end if;
    end loop;

    if exists (
      select 1
        from pg_catalog.pg_attribute as attribute
        cross join lateral pg_catalog.aclexplode(attribute.attacl) as privilege
       where attribute.attrelid = 'public.airfnb_trucks'::pg_catalog.regclass
         and attribute.attnum > 0 and not attribute.attisdropped
         and privilege.privilege_type in ('INSERT','UPDATE')
         and privilege.grantee <> v_authenticated
    ) then
      raise exception 'catalog reconciliation refused: unexpected mutation grantee';
    end if;

    for v_target in
      select *
        from (values
          ('public.airfnb_trucks'::pg_catalog.regclass, array[
            'id','slug','name','tagline','base_city','capacity','base_price',
            'price_per_pax','min_event_pax','max_event_pax','service_radius_km',
            'cuisine_types','dietary_options','catering_type','serves',
            'setup_minutes','teardown_minutes','power_required_kw',
            'sanitation_required','compatible_event_kinds','rating_avg',
            'rating_count','featured','status','service_type'
          ]::name[]),
          ('public.airfnb_truck_images'::pg_catalog.regclass,
           array['truck_id','url','kind','is_cover','sort_order']::name[]),
          ('public.airfnb_truck_categories'::pg_catalog.regclass,
           array['truck_id','category_id']::name[]),
          ('public.airfnb_categories'::pg_catalog.regclass,
           array['id','slug']::name[])
        ) as expected(relation_oid, select_columns)
    loop
      foreach v_role in array array['anon'::name, 'authenticated'::name, 'service_role'::name]
      loop
        if v_old_candidate then
          if (
            v_target.relation_oid = 'public.airfnb_trucks'::pg_catalog.regclass
            and v_role = 'authenticated'
          ) <> pg_catalog.has_table_privilege(v_role, v_target.relation_oid, 'SELECT')
             or exists (
               select 1
                 from pg_catalog.pg_attribute as attribute
                 cross join lateral pg_catalog.aclexplode(attribute.attacl) as privilege
                where attribute.attrelid = v_target.relation_oid
                  and attribute.attnum > 0 and not attribute.attisdropped
                  and privilege.grantee = case v_role
                    when 'anon' then v_anon
                    when 'authenticated' then v_authenticated
                    else v_service_role
                  end
                  and privilege.privilege_type = 'SELECT'
             ) then
            raise exception 'catalog reconciliation refused: old base SELECT ACL drifted';
          end if;
        else
          if pg_catalog.has_table_privilege(v_role, v_target.relation_oid, 'SELECT') then
            raise exception 'catalog reconciliation refused: broad final base SELECT remains';
          end if;
          for v_column in
            select attribute.attname
              from pg_catalog.pg_attribute as attribute
             where attribute.attrelid = v_target.relation_oid
               and attribute.attnum > 0 and not attribute.attisdropped
          loop
            v_expected_select := v_column.attname = any(v_target.select_columns);
            if pg_catalog.has_column_privilege(
                 v_role, v_target.relation_oid, v_column.attname, 'SELECT'
               ) <> v_expected_select then
              raise exception 'catalog reconciliation refused: final SELECT ACL drifted %.% for %',
                v_target.relation_oid, v_column.attname, v_role;
            end if;
          end loop;
        end if;
      end loop;

      if exists (
        select 1
          from pg_catalog.pg_class as relation
          cross join lateral pg_catalog.aclexplode(relation.relacl) as privilege
         where relation.oid = v_target.relation_oid
           and privilege.privilege_type = 'SELECT'
           and privilege.grantee not in (
             v_owner,
             case when v_old_candidate
                        and v_target.relation_oid = 'public.airfnb_trucks'::pg_catalog.regclass
                  then v_authenticated else v_owner end
           )
      ) or exists (
        select 1
          from pg_catalog.pg_attribute as attribute
          cross join lateral pg_catalog.aclexplode(attribute.attacl) as privilege
         where attribute.attrelid = v_target.relation_oid
           and attribute.attnum > 0 and not attribute.attisdropped
           and privilege.privilege_type = 'SELECT'
           and (
             v_old_candidate
             or privilege.grantee not in (v_anon, v_authenticated, v_service_role)
           )
      ) then
        raise exception 'catalog reconciliation refused: unexpected base SELECT grantee';
      end if;
    end loop;
  end if;

  if (v_legacy::integer + v_old_candidate::integer + v_final::integer) <> 1 then
    raise exception 'catalog reconciliation refused: mixed or unknown prestate';
  end if;

  create temporary table airfnb_catalog_state_20260820 (
    state text primary key
  ) on commit drop;
  insert into airfnb_catalog_state_20260820(state)
  values (case when v_legacy then 'legacy' when v_old_candidate then 'old' else 'final' end);
end
$preconditions$;

-- Snapshot bodies/config/owners/ACLs that this migration is forbidden to
-- replace. The postcondition compares the catalogs directly.
create temporary table airfnb_catalog_function_snapshot_20260820 on commit drop as
select procedure.oid,
       procedure.proowner,
       procedure.proacl,
       procedure.prosecdef,
       procedure.provolatile,
       procedure.proconfig,
       pg_catalog.md5(procedure.prosrc) as body_hash
  from pg_catalog.pg_proc as procedure
 where procedure.oid in (
   'public.airfnb_is_admin()'::pg_catalog.regprocedure,
   'public.airfnb_admin_approve_truck(uuid)'::pg_catalog.regprocedure,
   'public.airfnb_admin_reject_truck(uuid,text)'::pg_catalog.regprocedure,
   'public.airfnb_recalc_truck_rating()'::pg_catalog.regprocedure,
   'public.airfnb_touch_updated_at()'::pg_catalog.regprocedure
 );

do $service_type$
begin
  if (select state from airfnb_catalog_state_20260820) = 'legacy' then
    create type public.airfnb_service_type as enum ('food_truck', 'catering', 'bar');

    alter table public.airfnb_trucks
      add column service_type public.airfnb_service_type
      not null default 'food_truck'::public.airfnb_service_type;

    create index airfnb_trucks_active_service_type_idx
      on public.airfnb_trucks(service_type)
      where status = 'active'::public.airfnb_truck_status;
  end if;
end
$service_type$;

-- Canonicalize the exact supplier mutation surface, including inherited
-- column ACLs left by interrupted or previous candidate executions.
do $truck_acl$
declare
  v_column record;
begin
  revoke insert, update, delete on table public.airfnb_trucks
    from public, anon, authenticated, service_role;

  for v_column in
    select attribute.attname
      from pg_catalog.pg_attribute as attribute
     where attribute.attrelid = 'public.airfnb_trucks'::pg_catalog.regclass
       and attribute.attnum > 0
       and not attribute.attisdropped
  loop
    execute pg_catalog.format(
      'revoke insert (%I), update (%I) on table public.airfnb_trucks from public, anon, authenticated, service_role',
      v_column.attname, v_column.attname
    );
  end loop;

  grant insert (
    owner_id, slug, name, tagline, description, base_city,
    service_radius_km, capacity, min_event_pax, max_event_pax,
    base_price, price_per_pax, setup_minutes, power_required_kw,
    needs_water, dimensions_m, status, cuisine_types, dietary_options,
    teardown_minutes, sanitation_required, catering_type, serves,
    compatible_event_kinds, service_type
  ) on table public.airfnb_trucks to authenticated;

  grant update (
    name, tagline, description, base_city, service_radius_km, capacity,
    min_event_pax, max_event_pax, base_price, price_per_pax, setup_minutes,
    power_required_kw, needs_water, dimensions_m, status, cuisine_types,
    dietary_options, teardown_minutes, sanitation_required, catering_type,
    serves, compatible_event_kinds, service_type
  ) on table public.airfnb_trucks to authenticated;
end
$truck_acl$;

do $moderation_policies$
begin
  if (select state from airfnb_catalog_state_20260820) = 'legacy' then
    drop policy "airfnb_trucks_owner_write" on public.airfnb_trucks;

    create policy "airfnb_trucks_owner_insert"
      on public.airfnb_trucks
      for insert
      to authenticated
      with check (
        owner_id = (select auth.uid())
        or public.airfnb_is_admin()
      );

    create policy "airfnb_trucks_owner_update"
      on public.airfnb_trucks
      for update
      to authenticated
      using (
        owner_id = (select auth.uid())
        or public.airfnb_is_admin()
      )
      with check (
        owner_id = (select auth.uid())
        or public.airfnb_is_admin()
      );
  end if;
end
$moderation_policies$;

create or replace function public.airfnb_guard_truck_moderation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $function$
declare
  v_table_owner name;
  v_is_trusted boolean;
begin
  select pg_catalog.pg_get_userbyid(c.relowner)
    into v_table_owner
    from pg_catalog.pg_class c
   where c.oid = 'public.airfnb_trucks'::pg_catalog.regclass;

  v_is_trusted := current_user = v_table_owner
                  or current_user = 'service_role'
                  or public.airfnb_is_admin();

  if v_is_trusted then
    return new;
  end if;

  if (select auth.uid()) is null then
    raise exception 'authenticated supplier identity required'
      using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    if new.owner_id is distinct from (select auth.uid()) then
      raise exception 'supplier owner must match authenticated user'
        using errcode = '42501';
    end if;

    if new.status is distinct from 'draft'::public.airfnb_truck_status then
      raise exception 'new supplier profiles must start in draft'
        using errcode = '42501';
    end if;

    if new.rating_avg is distinct from 0::numeric
       or new.rating_count is distinct from 0
       or new.featured is distinct from false
       or new.subscription_tier is distinct from 'basic'
       or new.homologation_expires_at is not null
       or new.insurance_expires_at is not null
       or new.lead_response_rate is not null
       or new.last_active_at is not null then
      raise exception 'server-owned supplier fields must retain their defaults'
        using errcode = '42501';
    end if;

    return new;
  end if;

  if old.owner_id is distinct from (select auth.uid())
     or new.owner_id is distinct from old.owner_id then
    raise exception 'supplier ownership is immutable'
      using errcode = '42501';
  end if;

  if new.id is distinct from old.id
     or new.slug is distinct from old.slug
     or new.rating_avg is distinct from old.rating_avg
     or new.rating_count is distinct from old.rating_count
     or new.featured is distinct from old.featured
     or new.subscription_tier is distinct from old.subscription_tier
     or new.homologation_expires_at is distinct from old.homologation_expires_at
     or new.insurance_expires_at is distinct from old.insurance_expires_at
     or new.lead_response_rate is distinct from old.lead_response_rate
     or new.last_active_at is distinct from old.last_active_at
     or new.created_at is distinct from old.created_at then
    raise exception 'server-owned supplier fields are immutable'
      using errcode = '42501';
  end if;

  if new.status is not distinct from old.status then
    return new;
  end if;

  if (old.status = 'draft'::public.airfnb_truck_status
      and new.status = 'pending_review'::public.airfnb_truck_status)
     or (old.status = 'active'::public.airfnb_truck_status
         and new.status = 'paused'::public.airfnb_truck_status)
     or (old.status = 'paused'::public.airfnb_truck_status
         and new.status = 'active'::public.airfnb_truck_status) then
    return new;
  end if;

  raise exception 'supplier status transition is not allowed'
    using errcode = '42501';
end;
$function$;

revoke execute on function public.airfnb_guard_truck_moderation()
  from public, anon, authenticated, service_role;

do $moderation_trigger$
begin
  if (select state from airfnb_catalog_state_20260820) = 'legacy' then
    create trigger airfnb_trg_trucks_moderation
      before insert or update on public.airfnb_trucks
      for each row
      execute function public.airfnb_guard_truck_moderation();
  end if;
end
$moderation_trigger$;

-- CREATE OR REPLACE preserves the view identity and dependencies. The service
-- type is appended, so the previous 27 columns retain names/order/types.
create or replace view public.airfnb_v_truck_card
with (security_invoker = true) as
select
  truck.id,
  truck.slug,
  truck.name,
  truck.tagline,
  truck.base_city,
  truck.capacity,
  truck.base_price,
  truck.price_per_pax,
  truck.min_event_pax,
  truck.max_event_pax,
  truck.service_radius_km,
  truck.cuisine_types,
  truck.dietary_options,
  truck.catering_type,
  truck.serves,
  truck.setup_minutes,
  truck.teardown_minutes,
  truck.power_required_kw,
  truck.sanitation_required,
  truck.compatible_event_kinds,
  truck.rating_avg,
  truck.rating_count,
  truck.featured,
  truck.status,
  (
    select image.url
      from public.airfnb_truck_images as image
     where image.truck_id = truck.id
     order by
       case image.kind
         when 'truck' then 1
         when 'food' then 2
         when 'venue' then 3
         when 'team' then 4
         else 5
       end,
       case when image.is_cover then 0 else 1 end,
       image.sort_order,
       image.url
     limit 1
  ) as cover_url,
  (
    select pg_catalog.array_agg(
             ordered_image.url
             order by ordered_image.kind_rank,
                      ordered_image.is_cover_rank,
                      ordered_image.sort_order,
                      ordered_image.url
           )
      from (
        select
          image.url,
          case image.kind
            when 'truck' then 1
            when 'food' then 2
            when 'venue' then 3
            when 'team' then 4
            else 5
          end as kind_rank,
          case when image.is_cover then 0 else 1 end as is_cover_rank,
          image.sort_order
        from public.airfnb_truck_images as image
        where image.truck_id = truck.id
        order by
          case image.kind
            when 'truck' then 1
            when 'food' then 2
            when 'venue' then 3
            when 'team' then 4
            else 5
          end,
          case when image.is_cover then 0 else 1 end,
          image.sort_order,
          image.url
        limit 6
      ) as ordered_image
  ) as gallery_urls,
  array(
    select category.slug
      from public.airfnb_truck_categories as truck_category
      join public.airfnb_categories as category
        on category.id = truck_category.category_id
     where truck_category.truck_id = truck.id
     order by category.slug
  ) as category_slugs,
  truck.service_type
from public.airfnb_trucks as truck
where truck.status = 'active'::public.airfnb_truck_status;

-- The security-invoker view needs base privileges, but only for the columns it
-- reads. Row visibility remains enforced by the exact RLS policies proven
-- above. Remove table and stale column grants before adding the allowlists.
do $catalog_select_acl$
declare
  v_target regclass;
  v_column record;
begin
  foreach v_target in array array[
    'public.airfnb_trucks'::pg_catalog.regclass,
    'public.airfnb_truck_images'::pg_catalog.regclass,
    'public.airfnb_truck_categories'::pg_catalog.regclass,
    'public.airfnb_categories'::pg_catalog.regclass
  ]
  loop
    execute pg_catalog.format(
      'revoke select on table %s from public, anon, authenticated, service_role',
      v_target
    );

    for v_column in
      select attribute.attname
        from pg_catalog.pg_attribute as attribute
       where attribute.attrelid = v_target
         and attribute.attnum > 0
         and not attribute.attisdropped
    loop
      execute pg_catalog.format(
        'revoke select (%I) on table %s from public, anon, authenticated, service_role',
        v_column.attname, v_target
      );
    end loop;
  end loop;

  grant select (
    id, slug, name, tagline, base_city, capacity, base_price, price_per_pax,
    min_event_pax, max_event_pax, service_radius_km, cuisine_types,
    dietary_options, catering_type, serves, setup_minutes, teardown_minutes,
    power_required_kw, sanitation_required, compatible_event_kinds,
    rating_avg, rating_count, featured, status, service_type
  ) on table public.airfnb_trucks to anon, authenticated, service_role;

  grant select (truck_id, url, kind, is_cover, sort_order)
    on table public.airfnb_truck_images to anon, authenticated, service_role;
  grant select (truck_id, category_id)
    on table public.airfnb_truck_categories to anon, authenticated, service_role;
  grant select (id, slug)
    on table public.airfnb_categories to anon, authenticated, service_role;
end
$catalog_select_acl$;

revoke all on table public.airfnb_v_truck_card
  from public, anon, authenticated, service_role;
grant select on table public.airfnb_v_truck_card
  to anon, authenticated, service_role;

do $postconditions$
declare
  v_owner oid := (
    select relation.relowner
      from pg_catalog.pg_class as relation
     where relation.oid = 'public.airfnb_trucks'::pg_catalog.regclass
  );
  v_role name;
  v_target record;
  v_column record;
  v_expected_select boolean;
  v_expected_insert boolean;
  v_expected_update boolean;
begin
  if (select pg_catalog.array_agg(value.enumlabel order by value.enumsortorder)
        from pg_catalog.pg_enum as value
       where value.enumtypid = 'public.airfnb_service_type'::pg_catalog.regtype)
       is distinct from array['food_truck','catering','bar']::name[]
     or (select pg_catalog.count(*) from pg_catalog.pg_enum
          where enumtypid = 'public.airfnb_service_type'::pg_catalog.regtype) <> 3
     or not exists (
       select 1
         from pg_catalog.pg_attribute as attribute
         join pg_catalog.pg_attrdef as default_value
           on default_value.adrelid = attribute.attrelid
          and default_value.adnum = attribute.attnum
        where attribute.attrelid = 'public.airfnb_trucks'::pg_catalog.regclass
          and attribute.attname = 'service_type'
          and attribute.atttypid = 'public.airfnb_service_type'::pg_catalog.regtype
          and attribute.attnotnull
          and pg_catalog.pg_get_expr(default_value.adbin, default_value.adrelid)
                = '''food_truck''::airfnb_service_type'
     )
     or exists (
       select 1 from public.airfnb_trucks as truck where truck.service_type is null
     )
     or not exists (
       select 1 from pg_catalog.pg_indexes
        where schemaname = 'public'
          and tablename = 'airfnb_trucks'
          and indexname = 'airfnb_trucks_active_service_type_idx'
          and indexdef = 'CREATE INDEX airfnb_trucks_active_service_type_idx ON public.airfnb_trucks USING btree (service_type) WHERE (status = ''active''::airfnb_truck_status)'
     )
  then
    raise exception 'catalog reconciliation failed: service-type postcondition';
  end if;

  if (
    select pg_catalog.array_agg(attribute.attname order by attribute.attnum)
      from pg_catalog.pg_attribute as attribute
     where attribute.attrelid = 'public.airfnb_v_truck_card'::pg_catalog.regclass
       and attribute.attnum > 0
       and not attribute.attisdropped
  ) is distinct from array[
    'id','slug','name','tagline','base_city','capacity','base_price',
    'price_per_pax','min_event_pax','max_event_pax','service_radius_km',
    'cuisine_types','dietary_options','catering_type','serves',
    'setup_minutes','teardown_minutes','power_required_kw',
    'sanitation_required','compatible_event_kinds','rating_avg',
    'rating_count','featured','status','cover_url','gallery_urls',
    'category_slugs','service_type'
  ]::name[] or (
    select relation.reloptions is distinct from array['security_invoker=true']::text[]
           or relation.relowner <> v_owner
      from pg_catalog.pg_class as relation
     where relation.oid = 'public.airfnb_v_truck_card'::pg_catalog.regclass
  ) or pg_catalog.md5(
    pg_catalog.pg_get_viewdef('public.airfnb_v_truck_card'::pg_catalog.regclass, true)
  ) <> 'c3e262896aa919d75361132feff47380' then
    raise exception 'catalog reconciliation failed: exact card view postcondition';
  end if;

  if (
    select pg_catalog.array_agg(policy.polname order by policy.polname)
      from pg_catalog.pg_policy as policy
     where policy.polrelid = 'public.airfnb_trucks'::pg_catalog.regclass
  ) is distinct from array[
    'airfnb_trucks_owner_insert','airfnb_trucks_owner_update',
    'airfnb_trucks_public_read'
  ]::name[] or exists (
    select 1
      from pg_catalog.pg_policy as policy
     where policy.polrelid = 'public.airfnb_trucks'::pg_catalog.regclass
       and (
         policy.polname = 'airfnb_trucks_owner_insert' and (
           policy.polcmd <> 'a'
           or policy.polroles <> array[(select oid from pg_catalog.pg_roles where rolname = 'authenticated')]
           or pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
                <> '((owner_id = ( SELECT auth.uid() AS uid)) OR airfnb_is_admin())'
         )
         or policy.polname = 'airfnb_trucks_owner_update' and (
           policy.polcmd <> 'w'
           or policy.polroles <> array[(select oid from pg_catalog.pg_roles where rolname = 'authenticated')]
           or pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
                <> '((owner_id = ( SELECT auth.uid() AS uid)) OR airfnb_is_admin())'
           or pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
                <> '((owner_id = ( SELECT auth.uid() AS uid)) OR airfnb_is_admin())'
         )
       )
  ) then
    raise exception 'catalog reconciliation failed: moderation RLS postcondition';
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_proc as procedure
     where procedure.oid = 'public.airfnb_guard_truck_moderation()'::pg_catalog.regprocedure
       and procedure.proowner = v_owner
       and not procedure.prosecdef
       and procedure.provolatile = 'v'
       and procedure.proconfig = array['search_path=pg_catalog, public']::text[]
       and pg_catalog.md5(procedure.prosrc) = '9580d50b368d29269983025249704dda'
       and not exists (
         select 1
           from pg_catalog.aclexplode(
             coalesce(procedure.proacl, pg_catalog.acldefault('f', procedure.proowner))
           ) as privilege
          where privilege.grantee in (
            0,
            (select oid from pg_catalog.pg_roles where rolname = 'anon'),
            (select oid from pg_catalog.pg_roles where rolname = 'authenticated'),
            (select oid from pg_catalog.pg_roles where rolname = 'service_role')
          )
            and privilege.privilege_type = 'EXECUTE'
       )
  ) or not exists (
    select 1
      from pg_catalog.pg_trigger as trigger
     where trigger.tgrelid = 'public.airfnb_trucks'::pg_catalog.regclass
       and trigger.tgname = 'airfnb_trg_trucks_moderation'
       and not trigger.tgisinternal
       and trigger.tgenabled = 'O'
       and trigger.tgfoid = 'public.airfnb_guard_truck_moderation()'::pg_catalog.regprocedure
  ) then
    raise exception 'catalog reconciliation failed: moderation guard postcondition';
  end if;

  if exists (
    select 1
      from airfnb_catalog_function_snapshot_20260820 as original
      join pg_catalog.pg_proc as procedure on procedure.oid = original.oid
     where procedure.proowner <> original.proowner
        or procedure.proacl is distinct from original.proacl
        or procedure.prosecdef <> original.prosecdef
        or procedure.provolatile <> original.provolatile
        or procedure.proconfig is distinct from original.proconfig
        or pg_catalog.md5(procedure.prosrc) <> original.body_hash
  ) or (select pg_catalog.count(*) from airfnb_catalog_function_snapshot_20260820) <> 5
     or (
       select pg_catalog.count(*)
         from airfnb_catalog_function_snapshot_20260820 as original
         join pg_catalog.pg_proc as procedure on procedure.oid = original.oid
     ) <> 5 then
    raise exception 'catalog reconciliation failed: protected function changed';
  end if;

  if (
    select pg_catalog.md5(
             pg_catalog.string_agg(
               pg_catalog.format('%s:%s:%s', truck.id, truck.rating_avg, truck.rating_count),
               ',' order by truck.id
             )
           )
      from public.airfnb_trucks as truck
  ) <> 'b7601dc5d1de93f854aaaf10085c33f7' then
    raise exception 'catalog reconciliation failed: rating aggregate changed';
  end if;

  -- Exact table-level privileges are absent for API roles. Column ACLs carry
  -- the allowlists below; DELETE is unavailable to every API role.
  foreach v_role in array array['anon'::name, 'authenticated'::name, 'service_role'::name]
  loop
    if pg_catalog.has_table_privilege(v_role, 'public.airfnb_trucks', 'SELECT')
       or pg_catalog.has_table_privilege(v_role, 'public.airfnb_trucks', 'INSERT')
       or pg_catalog.has_table_privilege(v_role, 'public.airfnb_trucks', 'UPDATE')
       or pg_catalog.has_table_privilege(v_role, 'public.airfnb_trucks', 'DELETE') then
      raise exception 'catalog reconciliation failed: broad truck ACL remains for %', v_role;
    end if;
  end loop;

  for v_target in
    select *
      from (values
        ('public.airfnb_trucks'::pg_catalog.regclass, array[
          'id','slug','name','tagline','base_city','capacity','base_price',
          'price_per_pax','min_event_pax','max_event_pax','service_radius_km',
          'cuisine_types','dietary_options','catering_type','serves',
          'setup_minutes','teardown_minutes','power_required_kw',
          'sanitation_required','compatible_event_kinds','rating_avg',
          'rating_count','featured','status','service_type'
        ]::name[]),
        ('public.airfnb_truck_images'::pg_catalog.regclass,
         array['truck_id','url','kind','is_cover','sort_order']::name[]),
        ('public.airfnb_truck_categories'::pg_catalog.regclass,
         array['truck_id','category_id']::name[]),
        ('public.airfnb_categories'::pg_catalog.regclass,
         array['id','slug']::name[])
      ) as expected(relation_oid, select_columns)
  loop
    foreach v_role in array array['anon'::name, 'authenticated'::name, 'service_role'::name]
    loop
      if pg_catalog.has_table_privilege(v_role, v_target.relation_oid, 'SELECT') then
        raise exception 'catalog reconciliation failed: broad base SELECT remains';
      end if;

      for v_column in
        select attribute.attname
          from pg_catalog.pg_attribute as attribute
         where attribute.attrelid = v_target.relation_oid
           and attribute.attnum > 0
           and not attribute.attisdropped
      loop
        v_expected_select := v_column.attname = any(v_target.select_columns);
        if pg_catalog.has_column_privilege(
             v_role, v_target.relation_oid, v_column.attname, 'SELECT'
           ) <> v_expected_select then
          raise exception 'catalog reconciliation failed: SELECT ACL mismatch %.% for %',
            v_target.relation_oid, v_column.attname, v_role;
        end if;
      end loop;
    end loop;
  end loop;

  for v_column in
    select attribute.attname
      from pg_catalog.pg_attribute as attribute
     where attribute.attrelid = 'public.airfnb_trucks'::pg_catalog.regclass
       and attribute.attnum > 0
       and not attribute.attisdropped
  loop
    v_expected_insert := v_column.attname = any(array[
      'owner_id','slug','name','tagline','description','base_city',
      'service_radius_km','capacity','min_event_pax','max_event_pax',
      'base_price','price_per_pax','setup_minutes','power_required_kw',
      'needs_water','dimensions_m','status','cuisine_types','dietary_options',
      'teardown_minutes','sanitation_required','catering_type','serves',
      'compatible_event_kinds','service_type'
    ]::name[]);
    v_expected_update := v_column.attname = any(array[
      'name','tagline','description','base_city','service_radius_km','capacity',
      'min_event_pax','max_event_pax','base_price','price_per_pax',
      'setup_minutes','power_required_kw','needs_water','dimensions_m','status',
      'cuisine_types','dietary_options','teardown_minutes',
      'sanitation_required','catering_type','serves',
      'compatible_event_kinds','service_type'
    ]::name[]);

    if pg_catalog.has_column_privilege(
         'authenticated', 'public.airfnb_trucks', v_column.attname, 'INSERT'
       ) <> v_expected_insert
       or pg_catalog.has_column_privilege(
         'authenticated', 'public.airfnb_trucks', v_column.attname, 'UPDATE'
       ) <> v_expected_update
       or pg_catalog.has_column_privilege(
         'anon', 'public.airfnb_trucks', v_column.attname, 'INSERT'
       )
       or pg_catalog.has_column_privilege(
         'anon', 'public.airfnb_trucks', v_column.attname, 'UPDATE'
       )
       or pg_catalog.has_column_privilege(
         'service_role', 'public.airfnb_trucks', v_column.attname, 'INSERT'
       )
       or pg_catalog.has_column_privilege(
         'service_role', 'public.airfnb_trucks', v_column.attname, 'UPDATE'
       ) then
      raise exception 'catalog reconciliation failed: mutation ACL mismatch for %',
        v_column.attname;
    end if;
  end loop;

  if not pg_catalog.has_table_privilege('anon', 'public.airfnb_v_truck_card', 'SELECT')
     or not pg_catalog.has_table_privilege('authenticated', 'public.airfnb_v_truck_card', 'SELECT')
     or not pg_catalog.has_table_privilege('service_role', 'public.airfnb_v_truck_card', 'SELECT')
     or exists (
       select 1
         from pg_catalog.pg_class as relation
         cross join lateral pg_catalog.aclexplode(
           coalesce(relation.relacl, pg_catalog.acldefault('r', relation.relowner))
         ) as privilege
        where relation.oid = 'public.airfnb_v_truck_card'::pg_catalog.regclass
          and privilege.grantee = 0
          and privilege.privilege_type = 'SELECT'
     ) then
    raise exception 'catalog reconciliation failed: view ACL postcondition';
  end if;
end
$postconditions$;

commit;
