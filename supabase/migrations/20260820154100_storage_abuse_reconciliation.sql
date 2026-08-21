-- Reconcile Storage object ownership, child-row visibility, public-ingestion
-- privileges and the rate-limit RPC after the identity/runtime/privacy/
-- messaging predecessors. Catalog base-column grants are intentionally left
-- untouched for the immediately following catalog reconciliation.

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
  v_historical boolean := false;
  v_old_candidate boolean := false;
  v_final boolean := false;
  v_rate_baseline boolean := false;
  v_rate_final boolean := false;
  v_relation record;
  v_expected_shape text;
  v_actual_shape text;
  v_rate oid := pg_catalog.to_regclass('public.airfnb_rate_limits');
  v_objects oid := pg_catalog.to_regclass('storage.objects');
begin
  select pg_catalog.max(role.oid) filter (where role.rolname = 'anon'),
         pg_catalog.max(role.oid) filter (where role.rolname = 'authenticated'),
         pg_catalog.max(role.oid) filter (where role.rolname = 'service_role')
    into v_anon, v_authenticated, v_service_role
    from pg_catalog.pg_roles as role
   where role.rolname in ('anon', 'authenticated', 'service_role');

  if v_anon is null or v_authenticated is null or v_service_role is null then
    raise exception 'storage abuse reconciliation refused: required API roles are missing';
  end if;

  for v_relation in
    select *
      from (values
        ('public', 'airfnb_trucks', '791c439172d36c4bad40b9cfdf1b34c8'),
        ('public', 'airfnb_profiles', '1b88e385e893f55f2303c917c79274c9'),
        ('public', 'airfnb_truck_images', '6c68db980e2deb4e9ce77ab1670b8f03'),
        ('public', 'airfnb_menu_items', '77d77c1594bb90e323eda65ff4512a86'),
        ('public', 'airfnb_truck_categories', '2026b21e4660e0c0e5fb6f6ce7b00973'),
        ('public', 'airfnb_rate_limits', '38b0b38a49ff0a8c012c1027300e83f6'),
        ('public', 'airfnb_partner_leads', 'f92d4863bc8a691d658e6ecccfbb0ea9'),
        ('public', 'airfnb_newsletter_subs', '7fa33e925efc4a7f05c064db6e9d3361'),
        ('public', 'airfnb_newsletter_subscribers', '8bdf44f817eb1518f8f39778617d9361'),
        ('public', 'airfnb_contact_requests', 'ca4b2ef7bb64cbfef97778b935392bb8'),
        ('storage', 'buckets', '36e93fda33ac5179ec576cfe59b0e1e9'),
        ('storage', 'objects', 'cc445c6c1378520705fb98eee0078e7d')
      ) as expected(schema_name, relation_name, shape_hash)
  loop
    v_expected_shape := v_relation.shape_hash;

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
      from pg_catalog.pg_class as relation
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = relation.relnamespace
      join pg_catalog.pg_attribute as attribute
        on attribute.attrelid = relation.oid
       and attribute.attnum > 0
       and not attribute.attisdropped
      left join pg_catalog.pg_attrdef as default_value
        on default_value.adrelid = relation.oid
       and default_value.adnum = attribute.attnum
     where namespace.nspname = v_relation.schema_name
       and relation.relname = v_relation.relation_name
       and relation.relkind = 'r';

    if v_actual_shape is distinct from v_expected_shape then
      raise exception 'storage abuse reconciliation refused: %.% shape drifted',
        v_relation.schema_name, v_relation.relation_name;
    end if;
  end loop;

  select relation.relowner
    into v_owner
    from pg_catalog.pg_class as relation
   where relation.oid = 'public.airfnb_trucks'::pg_catalog.regclass;

  if not exists (
    select 1
      from pg_catalog.pg_roles as owner_role
     where owner_role.oid = v_owner
       and owner_role.rolbypassrls
       and owner_role.rolname not in ('anon', 'authenticated', 'service_role')
  ) or exists (
    select 1
      from pg_catalog.pg_class as relation
     where relation.oid in (
       'public.airfnb_profiles'::pg_catalog.regclass,
       'public.airfnb_truck_images'::pg_catalog.regclass,
       'public.airfnb_menu_items'::pg_catalog.regclass,
       'public.airfnb_truck_categories'::pg_catalog.regclass,
       'public.airfnb_rate_limits'::pg_catalog.regclass,
       'public.airfnb_partner_leads'::pg_catalog.regclass,
       'public.airfnb_newsletter_subs'::pg_catalog.regclass,
       'public.airfnb_newsletter_subscribers'::pg_catalog.regclass,
       'public.airfnb_contact_requests'::pg_catalog.regclass,
       'storage.buckets'::pg_catalog.regclass,
       'storage.objects'::pg_catalog.regclass
     )
       and relation.relowner <> v_owner
  ) then
    raise exception 'storage abuse reconciliation refused: trusted owner alignment drifted';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_class as relation
     where relation.oid in (
       'public.airfnb_trucks'::pg_catalog.regclass,
       'public.airfnb_profiles'::pg_catalog.regclass,
       'public.airfnb_truck_images'::pg_catalog.regclass,
       'public.airfnb_menu_items'::pg_catalog.regclass,
       'public.airfnb_truck_categories'::pg_catalog.regclass,
       'public.airfnb_partner_leads'::pg_catalog.regclass,
       'public.airfnb_newsletter_subs'::pg_catalog.regclass,
       'public.airfnb_newsletter_subscribers'::pg_catalog.regclass,
       'public.airfnb_contact_requests'::pg_catalog.regclass,
       'storage.objects'::pg_catalog.regclass
     )
       and (not relation.relrowsecurity or relation.relforcerowsecurity)
  ) then
    raise exception 'storage abuse reconciliation refused: target RLS mode drifted';
  end if;

  if (
    select pg_catalog.count(*)
      from storage.buckets
     where id like 'airfnb-%'
  ) <> 5 or exists (
    select 1
      from storage.buckets as bucket
      full join (values
        ('airfnb-truck-images', 'airfnb-truck-images', true),
        ('airfnb-menu-images', 'airfnb-menu-images', true),
        ('airfnb-blog-images', 'airfnb-blog-images', true),
        ('airfnb-avatars', 'airfnb-avatars', true),
        ('airfnb-documents', 'airfnb-documents', false)
      ) as expected(id, name, public) using (id)
     where (bucket.id like 'airfnb-%' or expected.id is not null)
       and (
         bucket.id is null
         or bucket.name is distinct from expected.name
         or bucket.public is distinct from expected.public
       )
  ) then
    raise exception 'storage abuse reconciliation refused: bucket catalog drifted';
  end if;

  if exists (
    select 1
      from storage.objects as object
     where object.bucket_id in ('airfnb-truck-images', 'airfnb-documents')
       and object.name !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
  ) or exists (
    select 1
      from storage.objects as object
     where object.bucket_id = 'airfnb-avatars'
       and object.name !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
  ) then
    raise exception 'storage abuse reconciliation refused: malformed scoped object path exists';
  end if;

  if exists (
    select 1
      from public.airfnb_rate_limits as rate_limit
     where rate_limit.action !~ '^[a-z][a-z0-9_]{0,63}$'
        or rate_limit.bucket !~ '^[A-Za-z0-9][A-Za-z0-9:_-]{0,159}$'
        or rate_limit.count < 0
  ) then
    raise exception 'storage abuse reconciliation refused: incompatible rate-limit data exists';
  end if;

  -- Accept only the exact predecessor baseline or exact canonical final
  -- constraint/index contract. Same-named semantic drift is not a prestate.
  select
    (
      (select pg_catalog.count(*) from pg_catalog.pg_constraint where conrelid = v_rate) = 1
      and (select pg_catalog.count(*) from pg_catalog.pg_index where indrelid = v_rate) = 1
      and exists (
        select 1 from pg_catalog.pg_constraint as constraint_record
         where constraint_record.conrelid = v_rate
           and constraint_record.conname = 'airfnb_rate_limits_pkey'
           and constraint_record.contype = 'p'
           and pg_catalog.pg_get_constraintdef(constraint_record.oid)
                 = 'PRIMARY KEY (action, bucket)'
      )
      and exists (
        select 1
          from pg_catalog.pg_index as index_record
          join pg_catalog.pg_class as index_relation
            on index_relation.oid = index_record.indexrelid
          join pg_catalog.pg_namespace as index_namespace
            on index_namespace.oid = index_relation.relnamespace
         where index_record.indrelid = v_rate
           and index_namespace.nspname = 'public'
           and index_relation.relname = 'airfnb_rate_limits_pkey'
           and pg_catalog.pg_get_indexdef(index_record.indexrelid)
                 = 'CREATE UNIQUE INDEX airfnb_rate_limits_pkey ON public.airfnb_rate_limits USING btree (action, bucket)'
      )
    ),
    (
      (select pg_catalog.count(*) from pg_catalog.pg_constraint where conrelid = v_rate) = 4
      and (select pg_catalog.count(*) from pg_catalog.pg_index where indrelid = v_rate) = 2
      and not exists (
        select 1
          from (values
            ('airfnb_rate_limits_action_format', 'c',
             'CHECK ((action ~ ''^[a-z][a-z0-9_]{0,63}$''::text))'),
            ('airfnb_rate_limits_bucket_format', 'c',
             'CHECK ((bucket ~ ''^[A-Za-z0-9][A-Za-z0-9:_-]{0,159}$''::text))'),
            ('airfnb_rate_limits_count_range', 'c',
             'CHECK (((count >= 0) AND (count <= 2147483647)))'),
            ('airfnb_rate_limits_pkey', 'p', 'PRIMARY KEY (action, bucket)')
          ) as expected(name, constraint_type, definition)
         where not exists (
           select 1 from pg_catalog.pg_constraint as constraint_record
            where constraint_record.conrelid = v_rate
              and constraint_record.conname = expected.name
              and constraint_record.contype::text = expected.constraint_type
              and pg_catalog.pg_get_constraintdef(constraint_record.oid) = expected.definition
         )
      )
      and not exists (
        select 1
          from (values
            ('airfnb_rate_limits_pkey',
             'CREATE UNIQUE INDEX airfnb_rate_limits_pkey ON public.airfnb_rate_limits USING btree (action, bucket)'),
            ('airfnb_rate_limits_window_at_idx',
             'CREATE INDEX airfnb_rate_limits_window_at_idx ON public.airfnb_rate_limits USING btree (window_at)')
          ) as expected(name, definition)
         where not exists (
           select 1
             from pg_catalog.pg_index as index_record
             join pg_catalog.pg_class as index_relation
               on index_relation.oid = index_record.indexrelid
             join pg_catalog.pg_namespace as index_namespace
               on index_namespace.oid = index_relation.relnamespace
            where index_record.indrelid = v_rate
              and index_namespace.nspname = 'public'
              and index_relation.relname = expected.name
              and pg_catalog.pg_get_indexdef(index_record.indexrelid) = expected.definition
         )
      )
    )
    into v_rate_baseline, v_rate_final;

  if not (v_rate_baseline or v_rate_final) then
    raise exception 'storage abuse reconciliation refused: rate-limit constraint/index drifted';
  end if;

  if (
    select pg_catalog.count(*)
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'airfnb_can_manage_truck', 'airfnb_can_read_truck_child',
         'airfnb_check_rate_limit'
       )
  ) not in (1, 2, 3) or pg_catalog.to_regprocedure(
    'public.airfnb_check_rate_limit(text,text,integer,integer)'
  ) is null or exists (
    select 1
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and (
         procedure.proname = 'airfnb_can_manage_truck'
         and pg_catalog.pg_get_function_identity_arguments(procedure.oid) <> 'p_truck_text text'
         or procedure.proname = 'airfnb_can_read_truck_child'
         and pg_catalog.pg_get_function_identity_arguments(procedure.oid) <> 'p_truck_text text'
         or procedure.proname = 'airfnb_check_rate_limit'
         and pg_catalog.pg_get_function_identity_arguments(procedure.oid)
               <> 'p_action text, p_bucket text, p_limit_per_window integer, p_window_seconds integer'
       )
  ) then
    raise exception 'storage abuse reconciliation refused: target function overload drifted';
  end if;

  select
    not (select relation.relrowsecurity from pg_catalog.pg_class as relation where relation.oid = v_rate)
    and pg_catalog.to_regprocedure('public.airfnb_can_manage_truck(text)') is null
    and pg_catalog.to_regprocedure('public.airfnb_can_read_truck_child(text)') is null
    and exists (
      select 1
        from pg_catalog.pg_proc as procedure
       where procedure.oid = 'public.airfnb_check_rate_limit(text,text,integer,integer)'::pg_catalog.regprocedure
         and procedure.proowner = v_owner
         and procedure.prosecdef
         and procedure.provolatile = 'v'
         and procedure.proconfig = array['search_path=public']::text[]
         and pg_catalog.strpos(procedure.prosrc, 'v_window_at timestamptz') > 0
         and pg_catalog.strpos(procedure.prosrc, 'public.airfnb_rate_limits.count + 1') > 0
         and not pg_catalog.has_function_privilege(v_anon, procedure.oid, 'EXECUTE')
         and not pg_catalog.has_function_privilege(v_authenticated, procedure.oid, 'EXECUTE')
         and not pg_catalog.has_function_privilege(v_service_role, procedure.oid, 'EXECUTE')
    )
    and (select pg_catalog.bool_and(bucket.file_size_limit is null and bucket.allowed_mime_types is null)
           from storage.buckets as bucket where bucket.id like 'airfnb-%'),
    (select relation.relrowsecurity from pg_catalog.pg_class as relation where relation.oid = v_rate)
    and pg_catalog.to_regprocedure('public.airfnb_can_manage_truck(text)') is null
    and exists (
      select 1 from pg_catalog.pg_proc as procedure
       where procedure.oid = pg_catalog.to_regprocedure('public.airfnb_can_read_truck_child(text)')
         and procedure.proowner = v_owner
         and procedure.prosecdef
         and procedure.provolatile = 's'
         and procedure.proconfig = array['search_path=pg_catalog, public']::text[]
         and pg_catalog.md5(procedure.prosrc) = '3d9d41a7dc6e3f52091dddeba50a1884'
         and pg_catalog.has_function_privilege(v_anon, procedure.oid, 'EXECUTE')
         and pg_catalog.has_function_privilege(v_authenticated, procedure.oid, 'EXECUTE')
         and not pg_catalog.has_function_privilege(v_service_role, procedure.oid, 'EXECUTE')
    )
    and exists (
      select 1 from pg_catalog.pg_proc as procedure
       where procedure.oid = 'public.airfnb_check_rate_limit(text,text,integer,integer)'::pg_catalog.regprocedure
         and procedure.proowner = v_owner
         and procedure.prosecdef
         and procedure.provolatile = 'v'
         and procedure.proconfig = array['search_path=pg_catalog, public']::text[]
         and pg_catalog.md5(procedure.prosrc) = '4c11600d1e054c11a972171d36dc7b8e'
         and not pg_catalog.has_function_privilege(v_anon, procedure.oid, 'EXECUTE')
         and not pg_catalog.has_function_privilege(v_authenticated, procedure.oid, 'EXECUTE')
         and pg_catalog.has_function_privilege(v_service_role, procedure.oid, 'EXECUTE')
    ),
    (select relation.relrowsecurity from pg_catalog.pg_class as relation where relation.oid = v_rate)
    and exists (
      select 1 from pg_catalog.pg_proc as procedure
       where procedure.oid = pg_catalog.to_regprocedure('public.airfnb_can_manage_truck(text)')
         and pg_catalog.strpos(procedure.prosrc, 'truck.owner_id = (select auth.uid())') > 0
         and procedure.proconfig = array['search_path=""']::text[]
    )
    and exists (
      select 1 from pg_catalog.pg_proc as procedure
       where procedure.oid = pg_catalog.to_regprocedure('public.airfnb_can_read_truck_child(text)')
         and pg_catalog.strpos(procedure.prosrc, 'truck.status = ''active''') > 0
         and procedure.proconfig = array['search_path=""']::text[]
    )
    and exists (
      select 1 from pg_catalog.pg_proc as procedure
       where procedure.oid = 'public.airfnb_check_rate_limit(text,text,integer,integer)'::pg_catalog.regprocedure
         and pg_catalog.strpos(procedure.prosrc, '2147483647') > 0
         and procedure.proconfig = array['search_path=""']::text[]
    )
    and (select pg_catalog.bool_and(
           case when bucket.id = 'airfnb-documents'
             then bucket.file_size_limit = 8388608
              and bucket.allowed_mime_types = array['application/pdf']::text[]
           else bucket.file_size_limit = 2097152
              and bucket.allowed_mime_types = array['image/jpeg','image/png','image/webp']::text[]
           end
         ) from storage.buckets as bucket where bucket.id like 'airfnb-%')
    into v_historical, v_old_candidate, v_final;

  if v_old_candidate and not (
    select pg_catalog.bool_and(
      case when bucket.id = 'airfnb-documents'
        then bucket.file_size_limit = 8388608
         and bucket.allowed_mime_types = array['application/pdf']::text[]
      else bucket.file_size_limit = 2097152
         and bucket.allowed_mime_types = array['image/jpeg','image/png','image/webp']::text[]
      end
    ) from storage.buckets as bucket where bucket.id like 'airfnb-%'
  ) then
    v_old_candidate := false;
  end if;

  if (v_historical::integer + v_old_candidate::integer + v_final::integer) <> 1 then
    raise exception 'storage abuse reconciliation refused: mixed or unknown prestate';
  end if;

  if (v_final and not v_rate_final)
     or ((v_historical or v_old_candidate) and not v_rate_baseline) then
    raise exception 'storage abuse reconciliation refused: rate-limit structure does not match prestate';
  end if;

  -- The three child tables must have exactly their read/write pair. Historical
  -- reads used true; old/final reads use the safe helper. Base ACLs are not
  -- widened here.
  if exists (
    select 1
      from (values
        ('airfnb_truck_images', 'airfnb_truck_images_read', 'r'),
        ('airfnb_truck_images', 'airfnb_truck_images_write', '*'),
        ('airfnb_menu_items', 'airfnb_menu_items_read', 'r'),
        ('airfnb_menu_items', 'airfnb_menu_items_write', '*'),
        ('airfnb_truck_categories', 'airfnb_truck_cat_read', 'r'),
        ('airfnb_truck_categories', 'airfnb_truck_cat_write', '*')
      ) as expected(table_name, policy_name, command)
     where not exists (
       select 1
         from pg_catalog.pg_policy as policy
         join pg_catalog.pg_class as relation on relation.oid = policy.polrelid
         join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
        where namespace.nspname = 'public'
          and relation.relname = expected.table_name
          and policy.polname = expected.policy_name
          and policy.polcmd = expected.command
          and policy.polpermissive
     )
  ) or (
    select pg_catalog.count(*)
      from pg_catalog.pg_policy as policy
     where policy.polrelid in (
       'public.airfnb_truck_images'::pg_catalog.regclass,
       'public.airfnb_menu_items'::pg_catalog.regclass,
       'public.airfnb_truck_categories'::pg_catalog.regclass
     )
  ) <> 6 then
    raise exception 'storage abuse reconciliation refused: child-table policy set drifted';
  end if;

  if v_historical and exists (
    select 1
      from pg_catalog.pg_policy as policy
     where policy.polrelid in (
       'public.airfnb_truck_images'::pg_catalog.regclass,
       'public.airfnb_menu_items'::pg_catalog.regclass,
       'public.airfnb_truck_categories'::pg_catalog.regclass
     )
       and policy.polcmd = 'r'
       and (
         policy.polroles <> array[0::oid]
         or pg_catalog.pg_get_expr(policy.polqual, policy.polrelid) <> 'true'
       )
  ) then
    raise exception 'storage abuse reconciliation refused: historical child reads drifted';
  end if;

  if not v_historical and exists (
    select 1
      from pg_catalog.pg_policy as policy
     where policy.polrelid in (
       'public.airfnb_truck_images'::pg_catalog.regclass,
       'public.airfnb_menu_items'::pg_catalog.regclass,
       'public.airfnb_truck_categories'::pg_catalog.regclass
     )
       and policy.polcmd = 'r'
       and (
         policy.polroles <> array[v_anon, v_authenticated]
         or pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
              <> 'airfnb_can_read_truck_child((truck_id)::text)'
       )
  ) then
    raise exception 'storage abuse reconciliation refused: guarded child reads drifted';
  end if;

  if (v_historical or v_old_candidate) and exists (
    select 1
      from pg_catalog.pg_policy as policy
      join pg_catalog.pg_class as relation on relation.oid = policy.polrelid
     where policy.polrelid in (
       'public.airfnb_truck_images'::pg_catalog.regclass,
       'public.airfnb_menu_items'::pg_catalog.regclass,
       'public.airfnb_truck_categories'::pg_catalog.regclass
     )
       and policy.polcmd = '*'
       and (
         policy.polroles <> array[0::oid]
         or pg_catalog.md5(pg_catalog.pg_get_expr(policy.polqual, policy.polrelid))
              <> case relation.relname
                when 'airfnb_truck_images' then '08cb62d3748cd637bb8b064378155136'
                when 'airfnb_menu_items' then '4f3193f255b284cf68d1580e3f1e4e9a'
                when 'airfnb_truck_categories' then '6ea8cf06b3e1aa6568261911c55c53eb'
              end
         or (
           relation.relname in ('airfnb_truck_images', 'airfnb_menu_items')
           and policy.polwithcheck is not null
         )
         or (
           relation.relname = 'airfnb_truck_categories'
           and pg_catalog.md5(pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid))
                 <> '6ea8cf06b3e1aa6568261911c55c53eb'
         )
       )
  ) then
    raise exception 'storage abuse reconciliation refused: predecessor child writes drifted';
  end if;

  if v_final and exists (
    select 1
      from pg_catalog.pg_policy as policy
     where policy.polrelid in (
       'public.airfnb_truck_images'::pg_catalog.regclass,
       'public.airfnb_menu_items'::pg_catalog.regclass,
       'public.airfnb_truck_categories'::pg_catalog.regclass
     )
       and policy.polcmd = '*'
       and (
         policy.polroles <> array[v_authenticated]
         or pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
              <> 'airfnb_can_manage_truck((truck_id)::text)'
         or pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
              <> 'airfnb_can_manage_truck((truck_id)::text)'
       )
  ) then
    raise exception 'storage abuse reconciliation refused: final child writes drifted';
  end if;

  if (
    select pg_catalog.count(*) from pg_catalog.pg_policy where polrelid = v_objects
  ) <> 12 or exists (
    select 1
      from pg_catalog.pg_policy as policy
     where policy.polrelid = v_objects
       and policy.polname not in (
         'airfnb_avatars_public_read', 'airfnb_avatars_owner_insert',
         'airfnb_avatars_owner_update', 'airfnb_avatars_owner_delete',
         'airfnb_truck_images_public_read', 'airfnb_truck_images_owner_insert',
         'airfnb_truck_images_owner_update', 'airfnb_truck_images_owner_delete',
         'airfnb_documents_owner_read', 'airfnb_documents_owner_insert',
         'airfnb_documents_owner_update', 'airfnb_documents_owner_delete'
       )
  ) then
    raise exception 'storage abuse reconciliation refused: Storage policy set drifted';
  end if;

  if v_historical and not exists (
    select 1 from pg_catalog.pg_policy as policy
     where policy.polrelid = v_objects
       and policy.polname = 'airfnb_truck_images_public_read'
       and policy.polroles = array[0::oid]
       and pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
             = '(bucket_id = ''airfnb-truck-images''::text)'
  ) then
    raise exception 'storage abuse reconciliation refused: historical Storage read drifted';
  end if;

  if v_old_candidate and not exists (
    select 1 from pg_catalog.pg_policy as policy
     where policy.polrelid = v_objects
       and policy.polname = 'airfnb_truck_images_public_read'
       and policy.polroles = array[v_anon, v_authenticated]
       and pg_catalog.md5(pg_catalog.pg_get_expr(policy.polqual, policy.polrelid))
             = '676849dfa3c465ee89323337c0e9f8fa'
  ) then
    raise exception 'storage abuse reconciliation refused: old Storage read drifted';
  end if;

  if (v_historical or v_old_candidate) and exists (
    select 1
      from pg_catalog.pg_policy as policy
     where policy.polrelid = v_objects
       and policy.polname <> 'airfnb_truck_images_public_read'
       and (
         pg_catalog.md5(coalesce(pg_catalog.pg_get_expr(policy.polqual, policy.polrelid), ''))
           <> case policy.polname
             when 'airfnb_avatars_owner_delete' then '8eb0e029d31d931fddd6ed35614465b1'
             when 'airfnb_avatars_owner_insert' then 'd41d8cd98f00b204e9800998ecf8427e'
             when 'airfnb_avatars_owner_update' then '8eb0e029d31d931fddd6ed35614465b1'
             when 'airfnb_avatars_public_read' then 'fcd347e8b9d3088f19f111acff2f3bce'
             when 'airfnb_documents_owner_delete' then '176626b4b00f7c779b8f81fb8d0c9731'
             when 'airfnb_documents_owner_insert' then 'd41d8cd98f00b204e9800998ecf8427e'
             when 'airfnb_documents_owner_read' then '176626b4b00f7c779b8f81fb8d0c9731'
             when 'airfnb_documents_owner_update' then '176626b4b00f7c779b8f81fb8d0c9731'
             when 'airfnb_truck_images_owner_delete' then 'b4d063ba2a8da253c9eb22870f7eeecc'
             when 'airfnb_truck_images_owner_insert' then 'd41d8cd98f00b204e9800998ecf8427e'
             when 'airfnb_truck_images_owner_update' then 'b4d063ba2a8da253c9eb22870f7eeecc'
           end
         or pg_catalog.md5(coalesce(pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid), ''))
           <> case policy.polname
             when 'airfnb_avatars_owner_insert' then 'd00935ff3df8071cd785cce414581c3f'
             when 'airfnb_avatars_owner_update' then '8eb0e029d31d931fddd6ed35614465b1'
             when 'airfnb_documents_owner_insert' then '176626b4b00f7c779b8f81fb8d0c9731'
             when 'airfnb_documents_owner_update' then '176626b4b00f7c779b8f81fb8d0c9731'
             when 'airfnb_truck_images_owner_insert' then 'b4d063ba2a8da253c9eb22870f7eeecc'
             when 'airfnb_truck_images_owner_update' then 'b4d063ba2a8da253c9eb22870f7eeecc'
             else 'd41d8cd98f00b204e9800998ecf8427e'
           end
       )
  ) then
    raise exception 'storage abuse reconciliation refused: predecessor Storage policy drifted';
  end if;

  if v_final and exists (
    select 1
      from (values
        ('airfnb_avatars_public_read', 'r', array[v_anon, v_authenticated],
         $expr$(bucket_id = 'airfnb-avatars'::text)$expr$, null::text),
        ('airfnb_avatars_owner_insert', 'a', array[v_authenticated], null::text,
         $expr$((bucket_id = 'airfnb-avatars'::text) AND (auth.uid() IS NOT NULL) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND (split_part(name, '/'::text, 1) = (auth.uid())::text))$expr$),
        ('airfnb_avatars_owner_update', 'w', array[v_authenticated],
         $expr$((bucket_id = 'airfnb-avatars'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND (split_part(name, '/'::text, 1) = (auth.uid())::text))$expr$,
         $expr$((bucket_id = 'airfnb-avatars'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND (split_part(name, '/'::text, 1) = (auth.uid())::text))$expr$),
        ('airfnb_avatars_owner_delete', 'd', array[v_authenticated],
         $expr$((bucket_id = 'airfnb-avatars'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND (split_part(name, '/'::text, 1) = (auth.uid())::text))$expr$, null::text),
        ('airfnb_truck_images_public_read', 'r', array[v_anon, v_authenticated],
         $expr$((bucket_id = 'airfnb-truck-images'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND airfnb_can_read_truck_child(split_part(name, '/'::text, 1)))$expr$, null::text),
        ('airfnb_truck_images_owner_insert', 'a', array[v_authenticated], null::text,
         $expr$((bucket_id = 'airfnb-truck-images'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND airfnb_can_manage_truck(split_part(name, '/'::text, 1)))$expr$),
        ('airfnb_truck_images_owner_update', 'w', array[v_authenticated],
         $expr$((bucket_id = 'airfnb-truck-images'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND airfnb_can_manage_truck(split_part(name, '/'::text, 1)))$expr$,
         $expr$((bucket_id = 'airfnb-truck-images'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND airfnb_can_manage_truck(split_part(name, '/'::text, 1)))$expr$),
        ('airfnb_truck_images_owner_delete', 'd', array[v_authenticated],
         $expr$((bucket_id = 'airfnb-truck-images'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND airfnb_can_manage_truck(split_part(name, '/'::text, 1)))$expr$, null::text),
        ('airfnb_documents_owner_read', 'r', array[v_authenticated],
         $expr$((bucket_id = 'airfnb-documents'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND airfnb_can_manage_truck(split_part(name, '/'::text, 1)))$expr$, null::text),
        ('airfnb_documents_owner_insert', 'a', array[v_authenticated], null::text,
         $expr$((bucket_id = 'airfnb-documents'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND airfnb_can_manage_truck(split_part(name, '/'::text, 1)))$expr$),
        ('airfnb_documents_owner_update', 'w', array[v_authenticated],
         $expr$((bucket_id = 'airfnb-documents'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND airfnb_can_manage_truck(split_part(name, '/'::text, 1)))$expr$,
         $expr$((bucket_id = 'airfnb-documents'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND airfnb_can_manage_truck(split_part(name, '/'::text, 1)))$expr$),
        ('airfnb_documents_owner_delete', 'd', array[v_authenticated],
         $expr$((bucket_id = 'airfnb-documents'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND airfnb_can_manage_truck(split_part(name, '/'::text, 1)))$expr$, null::text)
      ) as expected(policy_name, command, roles, using_expression, check_expression)
     where not exists (
       select 1
         from pg_catalog.pg_policy as policy
        where policy.polrelid = v_objects
          and policy.polname = expected.policy_name
          and policy.polpermissive
          and policy.polcmd::text = expected.command
          and policy.polroles = expected.roles
          and pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
                is not distinct from expected.using_expression
          and pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
                is not distinct from expected.check_expression
     )
  ) then
    raise exception 'storage abuse reconciliation refused: final Storage policy drifted';
  end if;

  if v_historical then
    if exists (
      select 1
        from (values
          ('airfnb_partner_leads', 'airfnb_partner_leads_insert'),
          ('airfnb_newsletter_subs', 'airfnb_newsletter_anyone_insert'),
          ('airfnb_newsletter_subscribers', 'airfnb_newsletter_insert_any'),
          ('airfnb_contact_requests', 'airfnb_contact_insert_any')
        ) as expected(table_name, policy_name)
       where not exists (
         select 1
           from pg_catalog.pg_policy as policy
           join pg_catalog.pg_class as relation on relation.oid = policy.polrelid
          where relation.relname = expected.table_name
            and policy.polname = expected.policy_name
            and policy.polcmd = 'a'
            and policy.polroles = array[0::oid]
            and pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid) = 'true'
       )
    ) then
      raise exception 'storage abuse reconciliation refused: historical ingestion policy drifted';
    end if;

    if exists (
      select 1
        from (values
          ('public.airfnb_partner_leads'::pg_catalog.regclass),
          ('public.airfnb_newsletter_subs'::pg_catalog.regclass),
          ('public.airfnb_newsletter_subscribers'::pg_catalog.regclass),
          ('public.airfnb_contact_requests'::pg_catalog.regclass)
        ) as target(relation_oid)
       where not pg_catalog.has_table_privilege(v_anon, target.relation_oid, 'INSERT')
          or not pg_catalog.has_table_privilege(v_authenticated, target.relation_oid, 'INSERT')
    ) then
      raise exception 'storage abuse reconciliation refused: historical ingestion ACL drifted';
    end if;
  elsif exists (
    select 1
      from pg_catalog.pg_policy as policy
     where policy.polname in (
       'airfnb_partner_leads_insert', 'airfnb_newsletter_anyone_insert',
       'airfnb_newsletter_insert_any', 'airfnb_contact_insert_any'
     )
  ) then
    raise exception 'storage abuse reconciliation refused: public ingestion policy reappeared';
  end if;

  if exists (
    select 1
      from (values
        ('public.airfnb_partner_leads'::pg_catalog.regclass, 'airfnb_partner_leads_admin_read', 'r'),
        ('public.airfnb_partner_leads'::pg_catalog.regclass, 'airfnb_partner_leads_admin_update', 'w'),
        ('public.airfnb_newsletter_subs'::pg_catalog.regclass, 'airfnb_newsletter_admin_read', 'r'),
        ('public.airfnb_newsletter_subscribers'::pg_catalog.regclass, 'airfnb_newsletter_admin_read', 'r'),
        ('public.airfnb_contact_requests'::pg_catalog.regclass, 'airfnb_contact_admin_read', 'r')
      ) as expected(relation_oid, policy_name, command)
     where not exists (
       select 1
         from pg_catalog.pg_policy as policy
        where policy.polrelid = expected.relation_oid
          and policy.polname = expected.policy_name
          and policy.polcmd = expected.command
          and policy.polroles = array[0::oid]
          and pg_catalog.pg_get_expr(policy.polqual, policy.polrelid) = 'airfnb_is_admin()'
          and (
            expected.command <> 'w'
            or pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid) = 'airfnb_is_admin()'
          )
     )
  ) then
    raise exception 'storage abuse reconciliation refused: admin ingestion policy drifted';
  end if;

  create temporary table airfnb_storage_abuse_state_20260820 (
    state text primary key
  ) on commit drop;
  insert into airfnb_storage_abuse_state_20260820(state)
  values (case when v_final then 'final' when v_old_candidate then 'old' else 'historical' end);
end
$preconditions$;

-- Preserve the catalog-facing relation and column ACL state. This ticket must
-- not pre-empt the following security-invoker catalog migration.
create temporary table airfnb_storage_catalog_acl_20260820 on commit drop as
select relation.oid as relation_oid,
       relation.relacl,
       pg_catalog.array_agg(
         pg_catalog.format('%s=%s', attribute.attnum, coalesce(attribute.attacl::text, ''))
         order by attribute.attnum
       ) as column_acl
  from pg_catalog.pg_class as relation
  join pg_catalog.pg_attribute as attribute
    on attribute.attrelid = relation.oid
   and attribute.attnum > 0
   and not attribute.attisdropped
 where relation.oid in (
   'public.airfnb_trucks'::pg_catalog.regclass,
   'public.airfnb_truck_images'::pg_catalog.regclass,
   'public.airfnb_menu_items'::pg_catalog.regclass,
   'public.airfnb_truck_categories'::pg_catalog.regclass
 )
 group by relation.oid, relation.relacl;

update storage.buckets
   set public = expected.public,
       file_size_limit = expected.file_size_limit,
       allowed_mime_types = expected.allowed_mime_types
  from (values
    ('airfnb-truck-images', true, 2097152::bigint, array['image/jpeg','image/png','image/webp']::text[]),
    ('airfnb-menu-images', true, 2097152::bigint, array['image/jpeg','image/png','image/webp']::text[]),
    ('airfnb-blog-images', true, 2097152::bigint, array['image/jpeg','image/png','image/webp']::text[]),
    ('airfnb-avatars', true, 2097152::bigint, array['image/jpeg','image/png','image/webp']::text[]),
    ('airfnb-documents', false, 8388608::bigint, array['application/pdf']::text[])
  ) as expected(id, public, file_size_limit, allowed_mime_types)
 where storage.buckets.id = expected.id
   and (
     storage.buckets.public,
     storage.buckets.file_size_limit,
     storage.buckets.allowed_mime_types
   ) is distinct from (
     expected.public,
     expected.file_size_limit,
     expected.allowed_mime_types
   );

create or replace function public.airfnb_can_manage_truck(p_truck_text text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_truck_id uuid;
begin
  if p_truck_text is null
     or p_truck_text !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    return false;
  end if;

  v_truck_id := p_truck_text::uuid;
  return exists (
    select 1
      from public.airfnb_trucks as truck
     where truck.id = v_truck_id
       and (
         truck.owner_id = (select auth.uid())
         or public.airfnb_is_admin()
       )
  );
end
$function$;

create or replace function public.airfnb_can_read_truck_child(p_truck_text text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_truck_id uuid;
begin
  if p_truck_text is null
     or p_truck_text !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    return false;
  end if;

  v_truck_id := p_truck_text::uuid;
  return exists (
    select 1
      from public.airfnb_trucks as truck
     where truck.id = v_truck_id
       and (
         truck.status = 'active'
         or truck.owner_id = (select auth.uid())
         or public.airfnb_is_admin()
       )
  );
end
$function$;

revoke execute on function public.airfnb_can_manage_truck(text)
  from public, anon, authenticated, service_role;
grant execute on function public.airfnb_can_manage_truck(text)
  to authenticated;

revoke execute on function public.airfnb_can_read_truck_child(text)
  from public, anon, authenticated, service_role;
grant execute on function public.airfnb_can_read_truck_child(text)
  to anon, authenticated;

do $child_policies$
begin
  if (select state from airfnb_storage_abuse_state_20260820) <> 'final' then
    drop policy "airfnb_truck_images_read" on public.airfnb_truck_images;
    drop policy "airfnb_truck_images_write" on public.airfnb_truck_images;
    create policy "airfnb_truck_images_read"
      on public.airfnb_truck_images for select to anon, authenticated
      using (public.airfnb_can_read_truck_child(truck_id::text));
    create policy "airfnb_truck_images_write"
      on public.airfnb_truck_images for all to authenticated
      using (public.airfnb_can_manage_truck(truck_id::text))
      with check (public.airfnb_can_manage_truck(truck_id::text));

    drop policy "airfnb_menu_items_read" on public.airfnb_menu_items;
    drop policy "airfnb_menu_items_write" on public.airfnb_menu_items;
    create policy "airfnb_menu_items_read"
      on public.airfnb_menu_items for select to anon, authenticated
      using (public.airfnb_can_read_truck_child(truck_id::text));
    create policy "airfnb_menu_items_write"
      on public.airfnb_menu_items for all to authenticated
      using (public.airfnb_can_manage_truck(truck_id::text))
      with check (public.airfnb_can_manage_truck(truck_id::text));

    drop policy "airfnb_truck_cat_read" on public.airfnb_truck_categories;
    drop policy "airfnb_truck_cat_write" on public.airfnb_truck_categories;
    create policy "airfnb_truck_cat_read"
      on public.airfnb_truck_categories for select to anon, authenticated
      using (public.airfnb_can_read_truck_child(truck_id::text));
    create policy "airfnb_truck_cat_write"
      on public.airfnb_truck_categories for all to authenticated
      using (public.airfnb_can_manage_truck(truck_id::text))
      with check (public.airfnb_can_manage_truck(truck_id::text));
  end if;
end
$child_policies$;

do $storage_policies$
begin
  if (select state from airfnb_storage_abuse_state_20260820) <> 'final' then
    drop policy "airfnb_avatars_public_read" on storage.objects;
    drop policy "airfnb_avatars_owner_insert" on storage.objects;
    drop policy "airfnb_avatars_owner_update" on storage.objects;
    drop policy "airfnb_avatars_owner_delete" on storage.objects;
    create policy "airfnb_avatars_public_read"
      on storage.objects for select to anon, authenticated
      using (bucket_id = 'airfnb-avatars');
    create policy "airfnb_avatars_owner_insert"
      on storage.objects for insert to authenticated
      with check (
        bucket_id = 'airfnb-avatars'
        and auth.uid() is not null
        and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
        and split_part(name, '/', 1) = auth.uid()::text
      );
    create policy "airfnb_avatars_owner_update"
      on storage.objects for update to authenticated
      using (
        bucket_id = 'airfnb-avatars'
        and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
        and split_part(name, '/', 1) = auth.uid()::text
      )
      with check (
        bucket_id = 'airfnb-avatars'
        and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
        and split_part(name, '/', 1) = auth.uid()::text
      );
    create policy "airfnb_avatars_owner_delete"
      on storage.objects for delete to authenticated
      using (
        bucket_id = 'airfnb-avatars'
        and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
        and split_part(name, '/', 1) = auth.uid()::text
      );

    drop policy "airfnb_truck_images_public_read" on storage.objects;
    drop policy "airfnb_truck_images_owner_insert" on storage.objects;
    drop policy "airfnb_truck_images_owner_update" on storage.objects;
    drop policy "airfnb_truck_images_owner_delete" on storage.objects;
    create policy "airfnb_truck_images_public_read"
      on storage.objects for select to anon, authenticated
      using (
        bucket_id = 'airfnb-truck-images'
        and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
        and public.airfnb_can_read_truck_child(split_part(name, '/', 1))
      );
    create policy "airfnb_truck_images_owner_insert"
      on storage.objects for insert to authenticated
      with check (
        bucket_id = 'airfnb-truck-images'
        and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
        and public.airfnb_can_manage_truck(split_part(name, '/', 1))
      );
    create policy "airfnb_truck_images_owner_update"
      on storage.objects for update to authenticated
      using (
        bucket_id = 'airfnb-truck-images'
        and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
        and public.airfnb_can_manage_truck(split_part(name, '/', 1))
      )
      with check (
        bucket_id = 'airfnb-truck-images'
        and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
        and public.airfnb_can_manage_truck(split_part(name, '/', 1))
      );
    create policy "airfnb_truck_images_owner_delete"
      on storage.objects for delete to authenticated
      using (
        bucket_id = 'airfnb-truck-images'
        and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
        and public.airfnb_can_manage_truck(split_part(name, '/', 1))
      );

    drop policy "airfnb_documents_owner_read" on storage.objects;
    drop policy "airfnb_documents_owner_insert" on storage.objects;
    drop policy "airfnb_documents_owner_update" on storage.objects;
    drop policy "airfnb_documents_owner_delete" on storage.objects;
    create policy "airfnb_documents_owner_read"
      on storage.objects for select to authenticated
      using (
        bucket_id = 'airfnb-documents'
        and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
        and public.airfnb_can_manage_truck(split_part(name, '/', 1))
      );
    create policy "airfnb_documents_owner_insert"
      on storage.objects for insert to authenticated
      with check (
        bucket_id = 'airfnb-documents'
        and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
        and public.airfnb_can_manage_truck(split_part(name, '/', 1))
      );
    create policy "airfnb_documents_owner_update"
      on storage.objects for update to authenticated
      using (
        bucket_id = 'airfnb-documents'
        and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
        and public.airfnb_can_manage_truck(split_part(name, '/', 1))
      )
      with check (
        bucket_id = 'airfnb-documents'
        and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
        and public.airfnb_can_manage_truck(split_part(name, '/', 1))
      );
    create policy "airfnb_documents_owner_delete"
      on storage.objects for delete to authenticated
      using (
        bucket_id = 'airfnb-documents'
        and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
        and public.airfnb_can_manage_truck(split_part(name, '/', 1))
      );
  end if;
end
$storage_policies$;

alter table public.airfnb_rate_limits enable row level security;

do $rate_constraints$
begin
  if (select state from airfnb_storage_abuse_state_20260820) <> 'final' then
    alter table public.airfnb_rate_limits
      add constraint airfnb_rate_limits_action_format
      check (action ~ '^[a-z][a-z0-9_]{0,63}$');
    alter table public.airfnb_rate_limits
      add constraint airfnb_rate_limits_bucket_format
      check (bucket ~ '^[A-Za-z0-9][A-Za-z0-9:_-]{0,159}$');
    alter table public.airfnb_rate_limits
      add constraint airfnb_rate_limits_count_range
      check (count between 0 and 2147483647);
    execute 'create index airfnb_rate_limits_window_at_idx on public.airfnb_rate_limits (window_at)';
  end if;
end
$rate_constraints$;

do $rate_policy_cleanup$
declare
  v_policy record;
begin
  for v_policy in
    select policy.polname
      from pg_catalog.pg_policy as policy
     where policy.polrelid = 'public.airfnb_rate_limits'::pg_catalog.regclass
  loop
    execute pg_catalog.format(
      'drop policy %I on public.airfnb_rate_limits', v_policy.polname
    );
  end loop;
end
$rate_policy_cleanup$;

revoke all on table public.airfnb_rate_limits
  from public, anon, authenticated, service_role;

create or replace function public.airfnb_check_rate_limit(
  p_action text,
  p_bucket text,
  p_limit_per_window integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_count integer;
  v_now timestamptz := pg_catalog.statement_timestamp();
begin
  if p_action is null
     or p_action !~ '^[a-z][a-z0-9_]{0,63}$'
     or p_bucket is null
     or p_bucket !~ '^[A-Za-z0-9][A-Za-z0-9:_-]{0,159}$'
     or p_limit_per_window is null
     or p_limit_per_window < 1
     or p_limit_per_window > 10000
     or p_window_seconds is null
     or p_window_seconds < 1
     or p_window_seconds > 2678400 then
    raise exception using
      errcode = '22023',
      message = 'invalid rate-limit parameters';
  end if;

  delete from public.airfnb_rate_limits
   where window_at <= v_now - pg_catalog.make_interval(secs => 2678400);

  insert into public.airfnb_rate_limits (action, bucket, count, window_at)
  values (p_action, p_bucket, 1, v_now)
  on conflict (action, bucket) do update
    set count = case
      when public.airfnb_rate_limits.window_at
             <= v_now - pg_catalog.make_interval(secs => p_window_seconds)
        then 1
      else least(
        public.airfnb_rate_limits.count::bigint + 1,
        2147483647::bigint
      )::integer
    end,
    window_at = case
      when public.airfnb_rate_limits.window_at
             <= v_now - pg_catalog.make_interval(secs => p_window_seconds)
        then v_now
      else public.airfnb_rate_limits.window_at
    end
  returning count into v_count;

  return v_count <= p_limit_per_window;
end
$function$;

revoke execute on function public.airfnb_check_rate_limit(text, text, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.airfnb_check_rate_limit(text, text, integer, integer)
  to service_role;

drop policy if exists airfnb_partner_leads_insert
  on public.airfnb_partner_leads;
drop policy if exists "airfnb_newsletter_anyone_insert"
  on public.airfnb_newsletter_subs;
drop policy if exists "airfnb_newsletter_insert_any"
  on public.airfnb_newsletter_subscribers;
drop policy if exists "airfnb_contact_insert_any"
  on public.airfnb_contact_requests;

revoke insert on table public.airfnb_partner_leads
  from public, anon, authenticated;
revoke insert on table public.airfnb_newsletter_subs
  from public, anon, authenticated;
revoke insert on table public.airfnb_newsletter_subscribers
  from public, anon, authenticated;
revoke insert on table public.airfnb_contact_requests
  from public, anon, authenticated;

revoke all on table public.airfnb_partner_leads from service_role;
revoke all on table public.airfnb_newsletter_subs from service_role;
revoke all on table public.airfnb_newsletter_subscribers from service_role;
revoke all on table public.airfnb_contact_requests from service_role;
grant insert on table public.airfnb_partner_leads to service_role;
grant select, insert, update on table public.airfnb_newsletter_subs to service_role;
grant insert on table public.airfnb_newsletter_subscribers to service_role;
grant insert on table public.airfnb_contact_requests to service_role;

do $postconditions$
declare
  v_anon oid := (select oid from pg_catalog.pg_roles where rolname = 'anon');
  v_authenticated oid := (select oid from pg_catalog.pg_roles where rolname = 'authenticated');
  v_service_role oid := (select oid from pg_catalog.pg_roles where rolname = 'service_role');
  v_owner oid := (select relowner from pg_catalog.pg_class where oid = 'public.airfnb_trucks'::pg_catalog.regclass);
  v_function oid;
begin
  if exists (
    select 1
      from storage.buckets as bucket
      full join (values
        ('airfnb-truck-images', 'airfnb-truck-images', true, 2097152::bigint, array['image/jpeg','image/png','image/webp']::text[]),
        ('airfnb-menu-images', 'airfnb-menu-images', true, 2097152::bigint, array['image/jpeg','image/png','image/webp']::text[]),
        ('airfnb-blog-images', 'airfnb-blog-images', true, 2097152::bigint, array['image/jpeg','image/png','image/webp']::text[]),
        ('airfnb-avatars', 'airfnb-avatars', true, 2097152::bigint, array['image/jpeg','image/png','image/webp']::text[]),
        ('airfnb-documents', 'airfnb-documents', false, 8388608::bigint, array['application/pdf']::text[])
      ) as expected(id, name, public, file_size_limit, allowed_mime_types) using (id)
     where (bucket.id like 'airfnb-%' or expected.id is not null)
       and (
         bucket.id is null
         or bucket.name is distinct from expected.name
         or bucket.public is distinct from expected.public
         or bucket.file_size_limit is distinct from expected.file_size_limit
         or bucket.allowed_mime_types is distinct from expected.allowed_mime_types
       )
  ) then
    raise exception 'storage abuse reconciliation failed: bucket postcondition';
  end if;

  foreach v_function in array array[
    'public.airfnb_can_manage_truck(text)'::pg_catalog.regprocedure::oid,
    'public.airfnb_can_read_truck_child(text)'::pg_catalog.regprocedure::oid,
    'public.airfnb_check_rate_limit(text,text,integer,integer)'::pg_catalog.regprocedure::oid
  ]
  loop
    if not exists (
      select 1
        from pg_catalog.pg_proc as procedure
       where procedure.oid = v_function
         and procedure.proowner = v_owner
         and procedure.prosecdef
         and procedure.proconfig = array['search_path=""']::text[]
         and not exists (
           select 1
             from pg_catalog.aclexplode(
               coalesce(procedure.proacl, pg_catalog.acldefault('f', procedure.proowner))
             ) as privilege
            where privilege.grantee = 0
              and privilege.privilege_type = 'EXECUTE'
         )
    ) then
      raise exception 'storage abuse reconciliation failed: function owner/config/ACL postcondition';
    end if;
  end loop;

  if pg_catalog.has_function_privilege(v_anon, 'public.airfnb_can_manage_truck(text)', 'EXECUTE')
     or not pg_catalog.has_function_privilege(v_authenticated, 'public.airfnb_can_manage_truck(text)', 'EXECUTE')
     or pg_catalog.has_function_privilege(v_service_role, 'public.airfnb_can_manage_truck(text)', 'EXECUTE')
     or not pg_catalog.has_function_privilege(v_anon, 'public.airfnb_can_read_truck_child(text)', 'EXECUTE')
     or not pg_catalog.has_function_privilege(v_authenticated, 'public.airfnb_can_read_truck_child(text)', 'EXECUTE')
     or pg_catalog.has_function_privilege(v_service_role, 'public.airfnb_can_read_truck_child(text)', 'EXECUTE')
     or pg_catalog.has_function_privilege(v_anon, 'public.airfnb_check_rate_limit(text,text,integer,integer)', 'EXECUTE')
     or pg_catalog.has_function_privilege(v_authenticated, 'public.airfnb_check_rate_limit(text,text,integer,integer)', 'EXECUTE')
     or not pg_catalog.has_function_privilege(v_service_role, 'public.airfnb_check_rate_limit(text,text,integer,integer)', 'EXECUTE')
  then
    raise exception 'storage abuse reconciliation failed: exact function grants';
  end if;

  if exists (
    select 1
      from airfnb_storage_catalog_acl_20260820 as original
      join pg_catalog.pg_class as relation on relation.oid = original.relation_oid
      cross join lateral (
        select pg_catalog.array_agg(
                 pg_catalog.format('%s=%s', attribute.attnum, coalesce(attribute.attacl::text, ''))
                 order by attribute.attnum
               ) as column_acl
          from pg_catalog.pg_attribute as attribute
         where attribute.attrelid = relation.oid
           and attribute.attnum > 0
           and not attribute.attisdropped
      ) as current_acl
     where relation.relacl is distinct from original.relacl
        or current_acl.column_acl is distinct from original.column_acl
  ) then
    raise exception 'storage abuse reconciliation failed: catalog base ACL changed';
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
      from pg_catalog.pg_policy as policy
     where policy.polrelid in (
       'public.airfnb_truck_images'::pg_catalog.regclass,
       'public.airfnb_menu_items'::pg_catalog.regclass,
       'public.airfnb_truck_categories'::pg_catalog.regclass
     )
       and (
         not policy.polpermissive
         or (
           policy.polcmd = 'r'
           and (
             policy.polroles <> array[v_anon, v_authenticated]
             or pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
                  <> 'airfnb_can_read_truck_child((truck_id)::text)'
             or policy.polwithcheck is not null
           )
         )
         or (
           policy.polcmd = '*'
           and (
             policy.polroles <> array[v_authenticated]
             or pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
                  <> 'airfnb_can_manage_truck((truck_id)::text)'
             or pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
                  <> 'airfnb_can_manage_truck((truck_id)::text)'
           )
         )
       )
  ) then
    raise exception 'storage abuse reconciliation failed: child RLS postcondition';
  end if;

  if (
    select pg_catalog.count(*) from pg_catalog.pg_policy
     where polrelid = 'storage.objects'::pg_catalog.regclass
  ) <> 12 or exists (
    select 1 from pg_catalog.pg_policy
     where polrelid = 'storage.objects'::pg_catalog.regclass
       and polname not in (
         'airfnb_avatars_public_read', 'airfnb_avatars_owner_insert',
         'airfnb_avatars_owner_update', 'airfnb_avatars_owner_delete',
         'airfnb_truck_images_public_read', 'airfnb_truck_images_owner_insert',
         'airfnb_truck_images_owner_update', 'airfnb_truck_images_owner_delete',
         'airfnb_documents_owner_read', 'airfnb_documents_owner_insert',
         'airfnb_documents_owner_update', 'airfnb_documents_owner_delete'
       )
  ) or exists (
    select 1 from pg_catalog.pg_policy
     where polrelid = 'storage.objects'::pg_catalog.regclass
       and (
         polname like 'airfnb_menu_images_%'
         or polname like 'airfnb_blog_images_%'
       )
  ) or exists (
    select 1
      from (values
        ('airfnb_avatars_public_read', 'r', array[v_anon, v_authenticated],
         $expr$(bucket_id = 'airfnb-avatars'::text)$expr$, null::text),
        ('airfnb_avatars_owner_insert', 'a', array[v_authenticated], null::text,
         $expr$((bucket_id = 'airfnb-avatars'::text) AND (auth.uid() IS NOT NULL) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND (split_part(name, '/'::text, 1) = (auth.uid())::text))$expr$),
        ('airfnb_avatars_owner_update', 'w', array[v_authenticated],
         $expr$((bucket_id = 'airfnb-avatars'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND (split_part(name, '/'::text, 1) = (auth.uid())::text))$expr$,
         $expr$((bucket_id = 'airfnb-avatars'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND (split_part(name, '/'::text, 1) = (auth.uid())::text))$expr$),
        ('airfnb_avatars_owner_delete', 'd', array[v_authenticated],
         $expr$((bucket_id = 'airfnb-avatars'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND (split_part(name, '/'::text, 1) = (auth.uid())::text))$expr$, null::text),
        ('airfnb_truck_images_public_read', 'r', array[v_anon, v_authenticated],
         $expr$((bucket_id = 'airfnb-truck-images'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND airfnb_can_read_truck_child(split_part(name, '/'::text, 1)))$expr$, null::text),
        ('airfnb_truck_images_owner_insert', 'a', array[v_authenticated], null::text,
         $expr$((bucket_id = 'airfnb-truck-images'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND airfnb_can_manage_truck(split_part(name, '/'::text, 1)))$expr$),
        ('airfnb_truck_images_owner_update', 'w', array[v_authenticated],
         $expr$((bucket_id = 'airfnb-truck-images'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND airfnb_can_manage_truck(split_part(name, '/'::text, 1)))$expr$,
         $expr$((bucket_id = 'airfnb-truck-images'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND airfnb_can_manage_truck(split_part(name, '/'::text, 1)))$expr$),
        ('airfnb_truck_images_owner_delete', 'd', array[v_authenticated],
         $expr$((bucket_id = 'airfnb-truck-images'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND airfnb_can_manage_truck(split_part(name, '/'::text, 1)))$expr$, null::text),
        ('airfnb_documents_owner_read', 'r', array[v_authenticated],
         $expr$((bucket_id = 'airfnb-documents'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND airfnb_can_manage_truck(split_part(name, '/'::text, 1)))$expr$, null::text),
        ('airfnb_documents_owner_insert', 'a', array[v_authenticated], null::text,
         $expr$((bucket_id = 'airfnb-documents'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND airfnb_can_manage_truck(split_part(name, '/'::text, 1)))$expr$),
        ('airfnb_documents_owner_update', 'w', array[v_authenticated],
         $expr$((bucket_id = 'airfnb-documents'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND airfnb_can_manage_truck(split_part(name, '/'::text, 1)))$expr$,
         $expr$((bucket_id = 'airfnb-documents'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND airfnb_can_manage_truck(split_part(name, '/'::text, 1)))$expr$),
        ('airfnb_documents_owner_delete', 'd', array[v_authenticated],
         $expr$((bucket_id = 'airfnb-documents'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND airfnb_can_manage_truck(split_part(name, '/'::text, 1)))$expr$, null::text)
      ) as expected(policy_name, command, roles, using_expression, check_expression)
     where not exists (
       select 1
         from pg_catalog.pg_policy as policy
        where policy.polrelid = 'storage.objects'::pg_catalog.regclass
          and policy.polname = expected.policy_name
          and policy.polpermissive
          and policy.polcmd::text = expected.command
          and policy.polroles = expected.roles
          and pg_catalog.pg_get_expr(policy.polqual, policy.polrelid)
                is not distinct from expected.using_expression
          and pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
                is not distinct from expected.check_expression
     )
  ) then
    raise exception 'storage abuse reconciliation failed: Storage policy postcondition';
  end if;

  if (
    select pg_catalog.count(*) from pg_catalog.pg_constraint
     where conrelid = 'public.airfnb_rate_limits'::pg_catalog.regclass
  ) <> 4 or exists (
    select 1
      from (values
        ('airfnb_rate_limits_action_format', 'c',
         'CHECK ((action ~ ''^[a-z][a-z0-9_]{0,63}$''::text))'),
        ('airfnb_rate_limits_bucket_format', 'c',
         'CHECK ((bucket ~ ''^[A-Za-z0-9][A-Za-z0-9:_-]{0,159}$''::text))'),
        ('airfnb_rate_limits_count_range', 'c',
         'CHECK (((count >= 0) AND (count <= 2147483647)))'),
        ('airfnb_rate_limits_pkey', 'p', 'PRIMARY KEY (action, bucket)')
      ) as expected(name, constraint_type, definition)
     where not exists (
       select 1 from pg_catalog.pg_constraint as constraint_record
        where constraint_record.conrelid = 'public.airfnb_rate_limits'::pg_catalog.regclass
          and constraint_record.conname = expected.name
          and constraint_record.contype::text = expected.constraint_type
          and pg_catalog.pg_get_constraintdef(constraint_record.oid) = expected.definition
     )
  ) or (
    select pg_catalog.count(*) from pg_catalog.pg_index
     where indrelid = 'public.airfnb_rate_limits'::pg_catalog.regclass
  ) <> 2 or exists (
    select 1
      from (values
        ('airfnb_rate_limits_pkey',
         'CREATE UNIQUE INDEX airfnb_rate_limits_pkey ON public.airfnb_rate_limits USING btree (action, bucket)'),
        ('airfnb_rate_limits_window_at_idx',
         'CREATE INDEX airfnb_rate_limits_window_at_idx ON public.airfnb_rate_limits USING btree (window_at)')
      ) as expected(name, definition)
     where not exists (
       select 1
         from pg_catalog.pg_index as index_record
         join pg_catalog.pg_class as index_relation
           on index_relation.oid = index_record.indexrelid
         join pg_catalog.pg_namespace as index_namespace
           on index_namespace.oid = index_relation.relnamespace
        where index_record.indrelid = 'public.airfnb_rate_limits'::pg_catalog.regclass
          and index_namespace.nspname = 'public'
          and index_relation.relname = expected.name
          and pg_catalog.pg_get_indexdef(index_record.indexrelid) = expected.definition
     )
  ) then
    raise exception 'storage abuse reconciliation failed: rate-limit constraint/index postcondition';
  end if;

  if not (select relrowsecurity from pg_catalog.pg_class where oid = 'public.airfnb_rate_limits'::pg_catalog.regclass)
     or exists (select 1 from pg_catalog.pg_policy where polrelid = 'public.airfnb_rate_limits'::pg_catalog.regclass)
     or exists (
       select 1
         from unnest(array['SELECT','INSERT','UPDATE','DELETE']) as privilege(name)
        where pg_catalog.has_table_privilege(v_anon, 'public.airfnb_rate_limits', privilege.name)
           or pg_catalog.has_table_privilege(v_authenticated, 'public.airfnb_rate_limits', privilege.name)
           or pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_rate_limits', privilege.name)
     )
     or not exists (
       select 1 from pg_catalog.pg_indexes
        where schemaname = 'public' and tablename = 'airfnb_rate_limits'
          and indexname = 'airfnb_rate_limits_window_at_idx'
     )
  then
    raise exception 'storage abuse reconciliation failed: RPC-only rate-limit state';
  end if;

  if exists (
    select 1 from pg_catalog.pg_policy
     where polname in (
       'airfnb_partner_leads_insert', 'airfnb_newsletter_anyone_insert',
       'airfnb_newsletter_insert_any', 'airfnb_contact_insert_any'
     )
  ) or exists (
    select 1
      from (values
        ('public.airfnb_partner_leads'::pg_catalog.regclass),
        ('public.airfnb_newsletter_subs'::pg_catalog.regclass),
        ('public.airfnb_newsletter_subscribers'::pg_catalog.regclass),
        ('public.airfnb_contact_requests'::pg_catalog.regclass)
      ) as target(relation_oid)
     where pg_catalog.has_table_privilege(v_anon, target.relation_oid, 'INSERT')
        or pg_catalog.has_table_privilege(v_authenticated, target.relation_oid, 'INSERT')
  ) then
    raise exception 'storage abuse reconciliation failed: direct public ingestion remains';
  end if;

  if not pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_partner_leads', 'INSERT')
     or pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_partner_leads', 'SELECT')
     or pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_partner_leads', 'UPDATE')
     or pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_partner_leads', 'DELETE')
     or not pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_newsletter_subs', 'SELECT')
     or not pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_newsletter_subs', 'INSERT')
     or not pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_newsletter_subs', 'UPDATE')
     or pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_newsletter_subs', 'DELETE')
     or not pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_newsletter_subscribers', 'INSERT')
     or pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_newsletter_subscribers', 'SELECT')
     or pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_newsletter_subscribers', 'UPDATE')
     or pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_newsletter_subscribers', 'DELETE')
     or not pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_contact_requests', 'INSERT')
     or pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_contact_requests', 'SELECT')
     or pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_contact_requests', 'UPDATE')
     or pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_contact_requests', 'DELETE') then
    raise exception 'storage abuse reconciliation failed: service-role ingestion ACL';
  end if;
end
$postconditions$;

commit;
