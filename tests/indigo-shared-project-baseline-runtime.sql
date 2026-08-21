\set ON_ERROR_STOP on

begin;
set local transaction read only;

select (
  (select count(*) from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname like 'airfnb_%') = 169
  and (select count(*) from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname like 'airfnb_%' and c.relkind='r') = 43
  and (select count(*) from pg_catalog.pg_type t join pg_catalog.pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typname like 'airfnb_%' and t.typtype in ('e','d')) = 24
  and (select count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'airfnb_%') = 68
  and (select count(*) from pg_catalog.pg_policies where schemaname='public' and policyname like 'airfnb_%') = 67
  and (select count(*) from pg_catalog.pg_trigger where not tgisinternal and tgname like 'airfnb_%') = 20
  and (select count(*) from pg_catalog.pg_policies where schemaname='storage' and policyname like 'airfnb_%') = 12
  and (select count(*) from storage.buckets where id like 'airfnb-%') = 5
  and (select count(*) from cron.job where jobname like 'airfnb_%') = 2
  and (select count(*) from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename like 'airfnb_%') = 6
) as exact_manifest_counts_ok
\gset
\if :exact_manifest_counts_ok
\else
  \echo exact F&B manifest counts failed
  \quit 1
\endif

select (
  pg_catalog.to_regclass('public.airfnb_membership_tombstones') is not null
  and coalesce((select relrowsecurity from pg_catalog.pg_class where oid=pg_catalog.to_regclass('public.airfnb_membership_tombstones')),false)
  and not exists (
    select 1 from pg_catalog.pg_policies
     where schemaname='public' and tablename='airfnb_membership_tombstones'
  )
  and not exists (
    select 1
      from (values ('anon'::text),('authenticated'::text),('service_role'::text)) checked_roles(role_name)
      cross join (values ('SELECT'::text),('INSERT'::text),('UPDATE'::text),('DELETE'::text),('TRUNCATE'::text),('REFERENCES'::text),('TRIGGER'::text)) checked_privileges(privilege_name)
     where pg_catalog.has_table_privilege(
       checked_roles.role_name,
       'public.airfnb_membership_tombstones',
       checked_privileges.privilege_name
     )
  )
  and pg_catalog.has_table_privilege('authenticated','public.airfnb_profiles','SELECT')
  and not pg_catalog.has_table_privilege('authenticated','public.airfnb_profiles','INSERT')
  and not pg_catalog.has_table_privilege('authenticated','public.airfnb_profiles','UPDATE')
  and not pg_catalog.has_table_privilege('authenticated','public.airfnb_profiles','DELETE')
  and not pg_catalog.has_column_privilege('authenticated','public.airfnb_profiles','role','UPDATE')
  and pg_catalog.has_column_privilege('authenticated','public.airfnb_profiles','full_name','UPDATE')
) as exact_membership_tombstone_boundary_ok
\gset
\if :exact_membership_tombstone_boundary_ok
\else
  \echo exact membership tombstone or profile ACL boundary failed
  \quit 1
\endif

select (
  (select count(*) from public.airfnb_baseline_manifest
    where singleton
      and manifest_version='20260821124724-v1'
      and catalog_hash ~ '^[0-9a-f]{32}$'
      and catalog_hash <> '00000000000000000000000000000000'
      and storage_hash ~ '^[0-9a-f]{32}$'
      and storage_hash <> '00000000000000000000000000000000'
      and seed_count=101
      and seed_hash ~ '^[0-9a-f]{32}$'
      and seed_hash <> '00000000000000000000000000000000') = 1
  and (select relrowsecurity from pg_catalog.pg_class where oid='public.airfnb_baseline_manifest'::pg_catalog.regclass)
  and not exists (
    select 1
      from (values ('anon'::text),('authenticated'::text),('service_role'::text)) checked_roles(role_name)
      cross join (values ('SELECT'::text),('INSERT'::text),('UPDATE'::text),('DELETE'::text),('TRUNCATE'::text),('REFERENCES'::text),('TRIGGER'::text)) checked_privileges(privilege_name)
     where pg_catalog.has_table_privilege(
       checked_roles.role_name,
       'public.airfnb_baseline_manifest',
       checked_privileges.privilege_name
     )
  )
  and (select count(*) from pg_catalog.pg_extension
        where extname in ('pgcrypto','pg_trgm','unaccent','postgis','pg_cron')) = 5
  and (select count(*) from pg_catalog.pg_trigger
        where tgrelid='auth.users'::pg_catalog.regclass
          and not tgisinternal and tgname like 'airfnb_%') = 0
) as sealed_manifest_and_auth_boundary_ok
\gset
\if :sealed_manifest_and_auth_boundary_ok
\else
  \echo sealed manifest or Auth boundary failed
  \quit 1
\endif

select (
  (select count(*)
     from pg_catalog.pg_proc p
     join pg_catalog.pg_namespace n on n.oid=p.pronamespace
     cross join lateral pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
     join pg_catalog.pg_roles r on r.oid=acl.grantee
    where n.nspname='public' and p.proname like 'airfnb_%'
      and acl.privilege_type='EXECUTE' and r.rolname='anon') = 7
  and (select count(*)
     from pg_catalog.pg_proc p
     join pg_catalog.pg_namespace n on n.oid=p.pronamespace
     cross join lateral pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
     join pg_catalog.pg_roles r on r.oid=acl.grantee
    where n.nspname='public' and p.proname like 'airfnb_%'
      and acl.privilege_type='EXECUTE' and r.rolname='authenticated') = 43
  and (select count(*)
     from pg_catalog.pg_proc p
     join pg_catalog.pg_namespace n on n.oid=p.pronamespace
     cross join lateral pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
     join pg_catalog.pg_roles r on r.oid=acl.grantee
    where n.nspname='public' and p.proname like 'airfnb_%'
      and acl.privilege_type='EXECUTE' and r.rolname='service_role') = 11
  and not exists (
    select 1
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid=p.pronamespace
      cross join lateral pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
     where n.nspname='public' and p.proname like 'airfnb_%'
       and acl.privilege_type='EXECUTE' and acl.grantee=0
  )
  and not exists (
    select 1
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public'
       and p.proname in ('airfnb_assign_ics_token','airfnb_event_request_visibility_sync','airfnb_make_ics_token','airfnb_platform_settings_touch')
       and p.proconfig is null
  )
) as exact_destination_acl_hardening_ok
\gset
\if :exact_destination_acl_hardening_ok
\else
  \echo destination default-privilege hardening failed
  \quit 1
\endif

select (
  (select count(*) from public.airfnb_blog_categories)
  + (select count(*) from public.airfnb_blog_posts)
  + (select count(*) from public.airfnb_categories)
  + (select count(*) from public.airfnb_faqs)
  + (select count(*) from public.airfnb_menu_items)
  + (select count(*) from public.airfnb_platform_settings)
  + (select count(*) from public.airfnb_service_providers)
  + (select count(*) from public.airfnb_truck_categories)
  + (select count(*) from public.airfnb_truck_images)
  + (select count(*) from public.airfnb_trucks)
  = 101
  and (
    (select count(*) from public.airfnb_blog_categories)
    + (select count(*) from public.airfnb_blog_posts)
    + (select count(*) from public.airfnb_categories)
    + (select count(*) from public.airfnb_faqs)
    + (select count(*) from public.airfnb_menu_items)
    + (select count(*) from public.airfnb_platform_settings)
    + (select count(*) from public.airfnb_service_providers)
    + (select count(*) from public.airfnb_truck_categories)
    + (select count(*) from public.airfnb_truck_images)
    + (select count(*) from public.airfnb_trucks)
    + (select count(*) from public.airfnb_baseline_manifest)
    + (select count(*) from cron.job where jobname like 'airfnb_%')
  ) = 104
) as exact_seed_counts_ok
\gset
\if :exact_seed_counts_ok
\else
  \echo exact 101-row seed manifest failed
  \quit 1
\endif

select (
  (select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'id',id,'name',name,'public',public,'file_size_limit',file_size_limit,
      'allowed_mime_types',allowed_mime_types
    ) order by id)
   from storage.buckets where id like 'airfnb-%')
  = '[
    {"id":"airfnb-avatars","name":"airfnb-avatars","public":true,"file_size_limit":2097152,"allowed_mime_types":["image/jpeg","image/png","image/webp"]},
    {"id":"airfnb-blog-images","name":"airfnb-blog-images","public":true,"file_size_limit":2097152,"allowed_mime_types":["image/jpeg","image/png","image/webp"]},
    {"id":"airfnb-documents","name":"airfnb-documents","public":false,"file_size_limit":8388608,"allowed_mime_types":["application/pdf"]},
    {"id":"airfnb-menu-images","name":"airfnb-menu-images","public":true,"file_size_limit":2097152,"allowed_mime_types":["image/jpeg","image/png","image/webp"]},
    {"id":"airfnb-truck-images","name":"airfnb-truck-images","public":true,"file_size_limit":2097152,"allowed_mime_types":["image/jpeg","image/png","image/webp"]}
  ]'::jsonb
) as exact_buckets_ok
\gset
\if :exact_buckets_ok
\else
  \echo exact bucket contract failed
  \quit 1
\endif

select (
  (select count(*) from cron.job where jobname='airfnb_expire_lockfees' and schedule='*/10 * * * *' and command='select public.airfnb_expire_stale_lock_fees();') = 1
  and (select count(*) from cron.job where jobname='airfnb_expire_requests' and schedule='0 * * * *' and command='select public.airfnb_expire_stale_requests();') = 1
  and (select pg_catalog.array_agg(tablename order by tablename)
       from pg_catalog.pg_publication_tables
       where pubname='supabase_realtime' and schemaname='public' and tablename like 'airfnb_%')
      = array['airfnb_applications','airfnb_bookings','airfnb_event_requests','airfnb_lock_fees','airfnb_messages','airfnb_notifications']::name[]
) as exact_jobs_and_realtime_ok
\gset
\if :exact_jobs_and_realtime_ok
\else
  \echo exact jobs or Realtime membership failed
  \quit 1
\endif

select (
  (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc where oid=pg_catalog.to_regprocedure('public.airfnb_ensure_profile(text,text)'))='9b03c272bb453651123bac3a77a9f938'
  and (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc where oid=pg_catalog.to_regprocedure('public.airfnb_claim_role(public.airfnb_user_role)'))='2755fff7e06bdad768d499ff6305c10f'
  and (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc where oid=pg_catalog.to_regprocedure('public.airfnb_guard_profile_role()'))='30225c87def1bebf86c9a443ffead831'
  and (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc where oid=pg_catalog.to_regprocedure('public.airfnb_self_delete()'))='8d2849ef2dc3fbfbc59c6d6d7fe2aeaf'
  and (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc where oid=pg_catalog.to_regprocedure('public.airfnb_self_delete_storage_prefixes()'))='ff72982e6ade07065de6d385f79997a1'
  and not pg_catalog.has_function_privilege('anon','public.airfnb_ensure_profile(text,text)','execute')
  and pg_catalog.has_function_privilege('authenticated','public.airfnb_ensure_profile(text,text)','execute')
  and not pg_catalog.has_function_privilege('service_role','public.airfnb_ensure_profile(text,text)','execute')
  and not pg_catalog.has_function_privilege('anon','public.airfnb_claim_role(public.airfnb_user_role)','execute')
  and pg_catalog.has_function_privilege('authenticated','public.airfnb_claim_role(public.airfnb_user_role)','execute')
  and not pg_catalog.has_function_privilege('service_role','public.airfnb_claim_role(public.airfnb_user_role)','execute')
  and not pg_catalog.has_function_privilege('anon','public.airfnb_guard_profile_role()','execute')
  and not pg_catalog.has_function_privilege('authenticated','public.airfnb_guard_profile_role()','execute')
  and not pg_catalog.has_function_privilege('service_role','public.airfnb_guard_profile_role()','execute')
  and not pg_catalog.has_function_privilege('anon','public.airfnb_self_delete()','execute')
  and pg_catalog.has_function_privilege('authenticated','public.airfnb_self_delete()','execute')
  and not pg_catalog.has_function_privilege('service_role','public.airfnb_self_delete()','execute')
  and not pg_catalog.has_function_privilege('anon','public.airfnb_self_delete_storage_prefixes()','execute')
  and pg_catalog.has_function_privilege('authenticated','public.airfnb_self_delete_storage_prefixes()','execute')
  and not pg_catalog.has_function_privilege('service_role','public.airfnb_self_delete_storage_prefixes()','execute')
) as exact_auth_functions_ok
\gset
\if :exact_auth_functions_ok
\else
  \echo exact Auth-boundary functions failed
  \quit 1
\endif

select (
  (select count(*)
     from pg_catalog.pg_index index_row
     join pg_catalog.pg_class index_class on index_class.oid=index_row.indexrelid
     join pg_catalog.pg_namespace index_namespace on index_namespace.oid=index_class.relnamespace
     join pg_catalog.pg_opclass operator_class on operator_class.oid=index_row.indclass[0]
     join pg_catalog.pg_namespace operator_namespace on operator_namespace.oid=operator_class.opcnamespace
    where index_namespace.nspname='public'
      and index_class.relname='airfnb_trucks_base_city_trgm_idx'
      and operator_namespace.nspname='extensions'
      and operator_class.opcname='gin_trgm_ops') = 1
) as extension_opclass_schema_ok
\gset
\if :extension_opclass_schema_ok
\else
  \echo pg_trgm operator class is not bound to extensions.gin_trgm_ops
  \quit 1
\endif

rollback;
