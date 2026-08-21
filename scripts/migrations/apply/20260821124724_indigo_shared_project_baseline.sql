-- Out-of-band installer for the complete F&B Tailor schema in the shared
-- Indigo Supabase project. This file is deliberately outside
-- supabase/migrations and must never be applied by supabase db push.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local idle_in_transaction_session_timeout = '180s';
set local check_function_bodies = off;

-- Serialize this out-of-band installer/rollback pair and prevent a normal
-- migration from changing the sealed predecessor while this transaction runs.
select pg_catalog.pg_advisory_xact_lock(
  1095122502,
  pg_catalog.hashtext('airfnb-indigo-baseline-installer')
);
lock table supabase_migrations.schema_migrations in share mode;

do $preflight$
declare
  v_history_count bigint;
  v_history_latest text;
  v_history_hash text;
  v_available_extensions bigint;
  v_public_relations bigint;
  v_public_types bigint;
  v_public_functions bigint;
  v_public_policies bigint;
  v_public_triggers bigint;
  v_storage_policies bigint;
  v_buckets bigint;
  v_jobs bigint;
  v_publication_members bigint;
  v_actual_catalog_hash text;
  v_expected_catalog_hash text;
  v_actual_storage_hash text;
  v_expected_storage_hash text;
  v_actual_seed_count bigint;
  v_expected_seed_count bigint;
  v_actual_seed_hash text;
  v_expected_seed_hash text;
  v_empty boolean := false;
begin
  if (select count(*) from pg_catalog.pg_roles where rolname in ('anon','authenticated','service_role')) <> 3
     or pg_catalog.to_regclass('auth.users') is null
     or pg_catalog.to_regclass('storage.buckets') is null
     or pg_catalog.to_regclass('storage.objects') is null
     or pg_catalog.to_regclass('supabase_migrations.schema_migrations') is null
     or not exists (select 1 from pg_catalog.pg_publication where pubname = 'supabase_realtime')
     or not exists (select 1 from pg_catalog.pg_extension where extname='pgcrypto') then
    raise exception 'indigo baseline refused: required Supabase roles, schemas, pgcrypto or publication are missing';
  end if;

  select count(*), max(version),
         pg_catalog.md5(pg_catalog.string_agg(version, ',' order by version))
    into v_history_count, v_history_latest, v_history_hash
    from supabase_migrations.schema_migrations;
  if v_history_count <> 85
     or v_history_latest is distinct from '20260821171040'
     or v_history_hash is distinct from '1f0eebdf3bcee57d873c3d4f87f260a9' then
    raise exception 'indigo baseline refused: migration history is not the exact 85-version Indigo predecessor';
  end if;

  select count(distinct extension_name) into v_available_extensions
    from (
      select name as extension_name from pg_catalog.pg_available_extensions
      union all
      select extname from pg_catalog.pg_extension
    ) available_or_installed
   where extension_name in ('pg_trgm','unaccent','postgis','pg_cron');
  if v_available_extensions <> 4 then
    raise exception 'indigo baseline refused: pg_trgm, unaccent, postgis and pg_cron must be available';
  end if;

  select count(*) into v_public_relations
    from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname like 'airfnb_%';
  select count(*) into v_public_types
    from pg_catalog.pg_type t join pg_catalog.pg_namespace n on n.oid=t.typnamespace
   where n.nspname='public' and t.typname like 'airfnb_%' and t.typtype in ('e','d');
  select count(*) into v_public_functions
    from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname like 'airfnb_%';
  select count(*) into v_public_policies from pg_catalog.pg_policies
   where schemaname='public' and policyname like 'airfnb_%';
  select count(*) into v_public_triggers from pg_catalog.pg_trigger
   where not tgisinternal and tgname like 'airfnb_%';
  select count(*) into v_storage_policies from pg_catalog.pg_policies
   where schemaname='storage' and policyname like 'airfnb_%';
  select count(*) into v_buckets from storage.buckets where id like 'airfnb-%';
  if pg_catalog.to_regclass('cron.job') is null then
    v_jobs := 0;
  else
    execute 'select count(*) from cron.job where jobname like ''airfnb_%''' into v_jobs;
  end if;
  select count(*) into v_publication_members from pg_catalog.pg_publication_tables
   where pubname='supabase_realtime' and schemaname='public' and tablename like 'airfnb_%';

  v_empty := v_public_relations=0 and v_public_types=0 and v_public_functions=0
    and v_public_policies=0 and v_public_triggers=0 and v_storage_policies=0
    and v_buckets=0 and v_jobs=0 and v_publication_members=0;

  if v_empty then
    perform pg_catalog.set_config('airfnb.baseline_mode', 'install', true);
    return;
  end if;

  if pg_catalog.to_regclass('public.airfnb_baseline_manifest') is null
     or not exists (
       select 1 from pg_catalog.pg_attribute
        where attrelid=pg_catalog.to_regclass('public.airfnb_baseline_manifest')
          and attname in ('catalog_hash','storage_hash','seed_count','seed_hash') and not attisdropped
        group by attrelid having count(*)=4
     )
     or v_public_relations <> 169
     or v_public_types <> 24
     or v_public_functions <> 68
     or v_public_policies <> 67
     or v_public_triggers <> 20
     or v_storage_policies <> 12
     or v_buckets <> 5
     or v_jobs <> 2
     or v_publication_members <> 6
     or pg_catalog.to_regprocedure('public.airfnb_ensure_profile(text,text)') is null
     or pg_catalog.to_regprocedure('public.airfnb_claim_role(public.airfnb_user_role)') is null
     or pg_catalog.to_regprocedure('public.airfnb_apply_referral(text)') is null
     or pg_catalog.to_regprocedure('public.airfnb_self_delete()') is null
     or pg_catalog.to_regprocedure('public.airfnb_self_delete_storage_prefixes()') is null
     or pg_catalog.to_regprocedure('public.airfnb_guard_profile_role()') is null
     or pg_catalog.to_regclass('public.airfnb_membership_tombstones') is null
     or (select count(*) from pg_catalog.pg_extension where extname in ('pgcrypto','pg_trgm','unaccent','postgis','pg_cron')) <> 5
     or pg_catalog.to_regclass('cron.job') is null
     or exists (select 1 from pg_catalog.pg_trigger where tgrelid='auth.users'::pg_catalog.regclass and not tgisinternal and tgname like 'airfnb_%') then
    raise exception 'indigo baseline refused: F&B collision or final-state drift detected';
  end if;

  select pg_catalog.md5(pg_catalog.string_agg(entry, E'\n' order by entry))
    into v_actual_catalog_hash
    from (
      select pg_catalog.jsonb_build_array('relation',c.relname,c.relkind,c.relpersistence,c.relrowsecurity,c.relforcerowsecurity,c.relreplident,pg_catalog.pg_get_userbyid(c.relowner),coalesce(c.relacl::text,''),case when c.relkind in ('v','m') then pg_catalog.pg_get_viewdef(c.oid,true) else '' end)::text as entry
        from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname like 'airfnb_%'
      union all
      select pg_catalog.jsonb_build_array('attribute',c.relname,a.attnum,a.attname,pg_catalog.format_type(a.atttypid,a.atttypmod),a.attnotnull,a.attidentity,a.attgenerated,coalesce(pg_catalog.pg_get_expr(d.adbin,d.adrelid),''),coalesce(a.attacl::text,''))::text
        from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace join pg_catalog.pg_attribute a on a.attrelid=c.oid left join pg_catalog.pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum where n.nspname='public' and c.relname like 'airfnb_%' and a.attnum>0 and not a.attisdropped
      union all
      select pg_catalog.jsonb_build_array('constraint',c.relname,k.conname,k.contype,pg_catalog.pg_get_constraintdef(k.oid,true))::text
        from pg_catalog.pg_constraint k join pg_catalog.pg_class c on c.oid=k.conrelid join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname like 'airfnb_%'
      union all
      select pg_catalog.jsonb_build_array('index',c.relname,pg_catalog.pg_get_indexdef(c.oid))::text
        from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname like 'airfnb_%' and c.relkind='i'
      union all
      select pg_catalog.jsonb_build_array('function',p.proname,pg_catalog.pg_get_function_identity_arguments(p.oid),pg_catalog.pg_get_function_result(p.oid),l.lanname,p.provolatile,p.prosecdef,p.proleakproof,p.proisstrict,p.proparallel,pg_catalog.pg_get_userbyid(p.proowner),coalesce(p.proconfig::text,''),coalesce(p.proacl::text,''),p.prosrc)::text
        from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace join pg_catalog.pg_language l on l.oid=p.prolang where n.nspname='public' and p.proname like 'airfnb_%'
      union all
      select pg_catalog.jsonb_build_array('type',t.typname,t.typtype,t.typcategory,t.typnotnull,pg_catalog.pg_get_userbyid(t.typowner),coalesce(t.typacl::text,''))::text
        from pg_catalog.pg_type t join pg_catalog.pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typname like 'airfnb_%'
      union all
      select pg_catalog.jsonb_build_array('enum',t.typname,e.enumsortorder,e.enumlabel)::text
        from pg_catalog.pg_type t join pg_catalog.pg_namespace n on n.oid=t.typnamespace join pg_catalog.pg_enum e on e.enumtypid=t.oid where n.nspname='public' and t.typname like 'airfnb_%'
      union all
      select pg_catalog.jsonb_build_array('policy',schemaname,tablename,policyname,permissive,roles,cmd,coalesce(qual,''),coalesce(with_check,''))::text
        from pg_catalog.pg_policies where (schemaname='public' or schemaname='storage') and policyname like 'airfnb_%'
      union all
      select pg_catalog.jsonb_build_array('trigger',n.nspname,c.relname,t.tgname,pg_catalog.pg_get_triggerdef(t.oid,true))::text
        from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid=t.tgrelid join pg_catalog.pg_namespace n on n.oid=c.relnamespace where not t.tgisinternal and t.tgname like 'airfnb_%'
      union all
      select pg_catalog.jsonb_build_array('bucket',id,name,public,file_size_limit,allowed_mime_types)::text from storage.buckets where id like 'airfnb-%'
      union all
      select pg_catalog.jsonb_build_array('job',jobname,schedule,command)::text from cron.job where jobname like 'airfnb_%'
      union all
      select pg_catalog.jsonb_build_array('publication',pubname,schemaname,tablename)::text from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename like 'airfnb_%'
    ) manifest_entries;
  execute 'select catalog_hash from public.airfnb_baseline_manifest where singleton and manifest_version=''20260821124724-v1''' into v_expected_catalog_hash;
  if v_expected_catalog_hash is null or v_actual_catalog_hash is distinct from v_expected_catalog_hash then
    raise exception 'indigo baseline refused: F&B collision or final-state drift detected';
  end if;
  select pg_catalog.md5(pg_catalog.string_agg(entry, E'\n' order by entry))
    into v_actual_storage_hash
    from (
      select pg_catalog.jsonb_build_array('bucket',id,name,public,file_size_limit,allowed_mime_types)::text as entry
        from storage.buckets where id like 'airfnb-%'
      union all
      select pg_catalog.jsonb_build_array('policy',schemaname,tablename,policyname,permissive,roles,cmd,coalesce(qual,''),coalesce(with_check,''))::text
        from pg_catalog.pg_policies where schemaname='storage' and policyname like 'airfnb_%'
    ) storage_entries;
  execute 'select storage_hash from public.airfnb_baseline_manifest where singleton and manifest_version=''20260821124724-v1''' into v_expected_storage_hash;
  if v_expected_storage_hash is null or v_actual_storage_hash is distinct from v_expected_storage_hash then
    raise exception 'indigo baseline refused: F&B collision or final-state drift detected';
  end if;
  select pg_catalog.count(*),pg_catalog.md5(pg_catalog.string_agg(entry,E'\n' order by entry))
    into v_actual_seed_count,v_actual_seed_hash
    from (
      select pg_catalog.jsonb_build_array('airfnb_blog_categories',pg_catalog.to_jsonb(seed_row))::text as entry from public.airfnb_blog_categories seed_row
      union all select pg_catalog.jsonb_build_array('airfnb_blog_posts',pg_catalog.to_jsonb(seed_row))::text from public.airfnb_blog_posts seed_row
      union all select pg_catalog.jsonb_build_array('airfnb_categories',pg_catalog.to_jsonb(seed_row))::text from public.airfnb_categories seed_row
      union all select pg_catalog.jsonb_build_array('airfnb_faqs',pg_catalog.to_jsonb(seed_row))::text from public.airfnb_faqs seed_row
      union all select pg_catalog.jsonb_build_array('airfnb_menu_items',pg_catalog.to_jsonb(seed_row))::text from public.airfnb_menu_items seed_row
      union all select pg_catalog.jsonb_build_array('airfnb_platform_settings',pg_catalog.to_jsonb(seed_row))::text from public.airfnb_platform_settings seed_row
      union all select pg_catalog.jsonb_build_array('airfnb_service_providers',pg_catalog.to_jsonb(seed_row))::text from public.airfnb_service_providers seed_row
      union all select pg_catalog.jsonb_build_array('airfnb_truck_categories',pg_catalog.to_jsonb(seed_row))::text from public.airfnb_truck_categories seed_row
      union all select pg_catalog.jsonb_build_array('airfnb_truck_images',pg_catalog.to_jsonb(seed_row))::text from public.airfnb_truck_images seed_row
      union all select pg_catalog.jsonb_build_array('airfnb_trucks',pg_catalog.to_jsonb(seed_row))::text from public.airfnb_trucks seed_row
    ) seed_entries;
  execute 'select seed_count,seed_hash from public.airfnb_baseline_manifest where singleton and manifest_version=''20260821124724-v1'''
    into v_expected_seed_count,v_expected_seed_hash;
  if v_actual_seed_count <> 101
     or v_expected_seed_count <> 101
     or v_actual_seed_hash is distinct from v_expected_seed_hash then
    raise exception 'indigo baseline refused: F&B seed drift detected';
  end if;
  if v_expected_catalog_hash = 'c7587da9523bd65c2f30e24073c76eac' then
    -- The first production install exposed the destination project's broad
    -- DEFAULT PRIVILEGES. Accept exactly that sealed catalogue once so this
    -- same installer can revoke the inherited grants and reseal atomically.
    perform pg_catalog.set_config('airfnb.baseline_mode', 'harden', true);
  else
    perform pg_catalog.set_config('airfnb.baseline_mode', 'final', true);
  end if;
end
$preflight$;

do $dependencies$
begin
  if pg_catalog.current_setting('airfnb.baseline_mode') = 'install' then
    execute 'create extension if not exists pg_trgm with schema extensions';
    execute 'create extension if not exists unaccent with schema extensions';
    execute 'create extension if not exists postgis with schema extensions';
    execute 'create extension if not exists pg_cron';
  end if;
  if (select count(*) from pg_catalog.pg_extension where extname in ('pgcrypto','pg_trgm','unaccent','postgis','pg_cron')) <> 5
     or pg_catalog.to_regclass('cron.job') is null then
    raise exception 'indigo baseline refused: required extensions did not install atomically';
  end if;
end
$dependencies$;

lock table storage.buckets in share row exclusive mode;
lock table storage.objects in share row exclusive mode;
-- Managed Supabase does not grant direct LOCK privilege on cron.job to the
-- Management API role. Serialize this installer and its rollback with the
-- same transaction-scoped advisory key instead.
select pg_catalog.pg_advisory_xact_lock(
  1095122502,
  pg_catalog.hashtext('airfnb-indigo-cron-catalog')
);

do $install$
begin
  if pg_catalog.current_setting('airfnb.baseline_mode') in ('final','harden') then
    return;
  end if;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_application_status AS ENUM (
    'submitted',
    'shortlisted',
    'accepted',
    'rejected',
    'withdrawn',
    'expired'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_booking_status AS ENUM (
    'inquiry',
    'proposal_sent',
    'accepted',
    'pending_lock_fee',
    'confirmed',
    'paid',
    'in_progress',
    'completed',
    'cancelled',
    'refunded'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_catering_type AS ENUM (
    'food',
    'drinks',
    'food_and_drinks'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_deal_type AS ENUM (
    'fixed',
    'percent',
    'mixed'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_dietary_tag AS ENUM (
    'vegan',
    'vegetarian',
    'gluten_free',
    'lactose_free',
    'nut_free',
    'halal',
    'kosher',
    'spicy'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_discovery_mode AS ENUM (
    'curated',
    'broadcast',
    'auto_match'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_energy_need AS ENUM (
    'nao_preciso',
    'ate_3kw',
    '3_a_10kw',
    'mais_10kw'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_event_kind AS ENUM (
    'wedding',
    'birthday',
    'corporate',
    'festival',
    'conference',
    'private',
    'other'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_lock_fee_status AS ENUM (
    'pending',
    'paid',
    'expired',
    'refunded',
    'waived'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_partner_lead_kind AS ENUM (
    'venues',
    'guest_mgmt',
    'music',
    'marketing'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_payment_direction AS ENUM (
    'organizer_to_platform',
    'truck_to_platform',
    'platform_to_truck'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_payment_kind AS ENUM (
    'lock_fee',
    'event_payment',
    'payout',
    'refund'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_payment_method AS ENUM (
    'stripe',
    'mbway',
    'multibanco',
    'manual'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_payment_status AS ENUM (
    'pending',
    'paid',
    'failed',
    'refunded'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_post_status AS ENUM (
    'draft',
    'scheduled',
    'published',
    'archived'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_request_status AS ENUM (
    'draft',
    'open',
    'reviewing',
    'awarded',
    'closed',
    'expired',
    'cancelled'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_sanitation_level AS ENUM (
    'nao_necessario',
    'wc_proximo',
    'wc_dedicado'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_selection_mode AS ENUM (
    'open_to_offers',
    'pick_myself',
    'assisted'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_service_kind AS ENUM (
    'venue',
    'entertainment',
    'planning',
    'marketing',
    'rental'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_service_type AS ENUM (
    'food_truck',
    'catering',
    'bar'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_truck_document_kind AS ENUM (
    'asae',
    'comercial',
    'financas',
    'outros'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_truck_image_kind AS ENUM (
    'truck',
    'food',
    'team',
    'venue',
    'other'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_truck_status AS ENUM (
    'draft',
    'pending_review',
    'active',
    'paused',
    'archived'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TYPE public.airfnb_user_role AS ENUM (
    'organizer',
    'owner',
    'admin',
    'staff'
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_accept_application(p_application uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
declare
  v_application public.airfnb_applications%rowtype;
  v_request public.airfnb_event_requests%rowtype;
  v_actor uuid := auth.uid();
  v_signed_service_role boolean := coalesce(
    current_setting('request.jwt.claim.role', true), ''
  ) = 'service_role';
  v_booking_id uuid;
  v_lock_fee_id uuid;
  v_conversation_id uuid;
  v_fee jsonb;
  v_total numeric;
  v_platform numeric;
  v_organizer numeric;
  v_accepted integer;
  v_decided_at timestamptz := pg_catalog.statement_timestamp();
  v_due_until timestamptz;
begin
  select * into v_application
    from public.airfnb_applications
   where id = p_application
   for update;
  if not found then
    raise exception using errcode = '22023', message = 'application not found';
  end if;
  if v_application.status is null
     or v_application.status not in ('submitted', 'shortlisted') then
    raise exception using errcode = '55000',
      message = 'application is not eligible for acceptance';
  end if;

  select * into v_request
    from public.airfnb_event_requests
   where id = v_application.request_id
   for update;
  if not found then
    raise exception using errcode = '55000', message = 'request not found';
  end if;

  if not v_signed_service_role and (
    v_actor is null or (
      v_actor is distinct from v_request.organizer_id
      and not public.airfnb_is_admin()
    )
  ) then
    raise exception using errcode = '42501', message = 'not authorized';
  end if;
  if v_request.slots_needed is null or v_request.slots_needed not between 1 and 10
     or v_request.application_response_window_hours is null
     or v_request.application_response_window_hours <= 0 then
    raise exception using errcode = '22023',
      message = 'request acceptance settings are invalid';
  end if;

  select pg_catalog.count(*)::integer into v_accepted
    from public.airfnb_applications as accepted_application
   where accepted_application.request_id = v_request.id
     and accepted_application.status = 'accepted';
  if v_accepted >= v_request.slots_needed then
    raise exception using errcode = '55000',
      message = 'request has no remaining slots';
  end if;
  if v_request.status is null or v_request.status not in ('open', 'reviewing') then
    raise exception using errcode = '55000',
      message = 'request is not accepting applications';
  end if;

  v_fee := public.airfnb_calculate_lock_fee(v_application.id);
  if pg_catalog.jsonb_typeof(v_fee) is distinct from 'object'
     or not v_fee ?& array['platform_fee','organizer_share','total'] then
    raise exception using errcode = '22023', message = 'lock fee split is invalid';
  end if;
  v_platform := (v_fee ->> 'platform_fee')::numeric;
  v_organizer := (v_fee ->> 'organizer_share')::numeric;
  v_total := (v_fee ->> 'total')::numeric;
  if v_platform is null or v_organizer is null or v_total is null
     or v_platform::text in ('NaN','Infinity','-Infinity')
     or v_organizer::text in ('NaN','Infinity','-Infinity')
     or v_total::text in ('NaN','Infinity','-Infinity')
     or v_platform < 0 or v_organizer < 0 or v_total < 0
     or v_total is distinct from v_platform + v_organizer then
    raise exception using errcode = '22023', message = 'lock fee split is invalid';
  end if;
  v_due_until := v_decided_at
    + pg_catalog.make_interval(hours => v_request.application_response_window_hours);

  update public.airfnb_applications
     set status = 'accepted', decided_at = v_decided_at
   where id = v_application.id;

  insert into public.airfnb_bookings(
    event_id, organizer_id, status, starts_at, ends_at, pax_count,
    total_amount, currency, notes, application_id
  ) values (
    null, v_request.organizer_id, 'pending_lock_fee', v_request.start_at,
    v_request.end_at, v_request.expected_pax, v_application.proposed_price,
    'EUR', v_request.notes, v_application.id
  ) returning id into v_booking_id;

  insert into public.airfnb_booking_trucks(booking_id, truck_id, agreed_price)
  values (v_booking_id, v_application.truck_id, v_application.proposed_price);

  insert into public.airfnb_lock_fees(
    application_id, amount, platform_fee, organizer_share,
    due_until, status, currency
  ) values (
    v_application.id, v_total, v_platform, v_organizer,
    v_due_until, 'pending', 'EUR'
  ) returning id into v_lock_fee_id;

  insert into public.airfnb_conversations(booking_id, application_id)
  values (v_booking_id, v_application.id)
  returning id into v_conversation_id;

  insert into public.airfnb_conversation_participants(conversation_id, user_id)
  select v_conversation_id, v_request.organizer_id
  union
  select v_conversation_id, truck.owner_id
    from public.airfnb_trucks as truck
   where truck.id = v_application.truck_id;

  insert into public.airfnb_notifications(user_id, kind, payload)
  select truck.owner_id,
         'application.accepted',
         pg_catalog.jsonb_build_object(
           'application_id', v_application.id,
           'request_id', v_request.id,
           'lock_fee_id', v_lock_fee_id,
           'total', v_total,
           'platform_fee', v_platform,
           'organizer_share', v_organizer,
           'deal_type', v_application.deal_type,
           'fixed_to_organizer', v_application.proposed_fixed_to_organizer,
           'revenue_share_pct', v_application.proposed_revenue_share_pct,
           'due_until', v_due_until
         )
    from public.airfnb_trucks as truck
   where truck.id = v_application.truck_id;

  v_accepted := v_accepted + 1;
  if v_accepted = v_request.slots_needed then
    update public.airfnb_event_requests
       set status = 'awarded', awarded_at = coalesce(awarded_at, v_decided_at)
     where id = v_request.id;
  end if;

  return pg_catalog.jsonb_build_object(
    'booking_id', v_booking_id,
    'lock_fee_id', v_lock_fee_id,
    'lock_fee', v_fee,
    'conversation_id', v_conversation_id
  );
end
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_admin_approve_truck(p_truck uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
begin
  if not public.airfnb_is_admin() then
    raise exception 'not authorized';
  end if;
  update public.airfnb_trucks
     set status = 'active', updated_at = now()
   where id = p_truck and status = 'pending_review';
end $$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_admin_metrics() RETURNS TABLE(trucks_total integer, trucks_active integer, trucks_pending integer, organizers_total integer, requests_open integer, bookings_confirmed integer, lockfees_paid_count integer, lockfees_paid_total numeric, revenue_platform numeric)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select
    (select count(*)::int from public.airfnb_trucks),
    (select count(*)::int from public.airfnb_trucks where status = 'active'),
    (select count(*)::int from public.airfnb_trucks where status = 'pending_review'),
    (select count(*)::int from public.airfnb_profiles where role in ('organizer','owner','admin','staff')),
    (select count(*)::int from public.airfnb_event_requests where status in ('open','reviewing')),
    (select count(*)::int from public.airfnb_bookings where status in ('confirmed','completed')),
    (select count(*)::int from public.airfnb_lock_fees where status = 'paid'),
    (select coalesce(sum(amount),       0) from public.airfnb_lock_fees where status = 'paid'),
    (select coalesce(sum(platform_fee), 0) from public.airfnb_lock_fees where status = 'paid')
  where public.airfnb_is_admin();
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_admin_pending_trucks(p_limit integer DEFAULT 50) RETURNS TABLE(id uuid, slug text, name text, base_city text, owner_id uuid, owner_name text, cover_url text, description text, created_at timestamp with time zone)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select t.id, t.slug, t.name, t.base_city, t.owner_id, p.display_name,
         (select url from public.airfnb_truck_images i where i.truck_id = t.id and i.is_cover order by sort_order limit 1),
         t.description,
         t.created_at
    from public.airfnb_trucks t
    left join public.airfnb_profiles p on p.id = t.owner_id
   where t.status = 'pending_review' and public.airfnb_is_admin()
   order by t.created_at desc
   limit greatest(1, p_limit);
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_admin_reject_truck(p_truck uuid, p_reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
begin
  if not public.airfnb_is_admin() then
    raise exception 'not authorized';
  end if;
  update public.airfnb_trucks
     set status = 'archived', updated_at = now()
   where id = p_truck and status = 'pending_review';

  -- Notify the owner with the reason
  insert into public.airfnb_notifications (user_id, kind, payload)
    select owner_id, 'truck.rejected',
           jsonb_build_object('truck_id', p_truck, 'reason', p_reason)
      from public.airfnb_trucks where id = p_truck;
end $$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_applications_rate_limit() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_max int;
begin
  -- Clamp to >= 1 so an admin setting of 0 doesn't block every insert.
  v_max := greatest(1, public.airfnb_setting_int('rate_limit.applications_per_day_per_truck', 50));
  if not public.airfnb_check_rate_limit(
       'application_submit',
       new.truck_id::text,
       v_max,
       86400
     ) then
    raise exception 'Rate limit exceeded: max % candidaturas por truck por dia', v_max;
  end if;
  return new;
end $$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_apply_referral(p_code text) RETURNS boolean
    LANGUAGE plpgsql VOLATILE SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_assign_ics_token() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if new.ics_token is null then
    new.ics_token := public.airfnb_make_ics_token();
  end if;
  return new;
end $$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_assign_referral_code() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
begin
  if new.referral_code is null then
    new.referral_code := public.airfnb_generate_referral_code();
  end if;
  return new;
end
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_booking_by_ics_token(p_token text) RETURNS TABLE(id uuid, title text, starts_at timestamp with time zone, ends_at timestamp with time zone, city text, organizer_id uuid, truck_names text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select
    b.id,
    coalesce(e.title, 'Air F&B event'),
    b.starts_at,
    coalesce(b.ends_at, b.starts_at + interval '4 hours'),
    coalesce(er.city, null),
    b.organizer_id,
    (select string_agg(t.name, ', ' order by t.name)
       from public.airfnb_booking_trucks bt
       join public.airfnb_trucks t on t.id = bt.truck_id
      where bt.booking_id = b.id)
    from public.airfnb_bookings b
    left join public.airfnb_events e on e.id = b.event_id
    left join public.airfnb_applications a on a.id = b.application_id
    left join public.airfnb_event_requests er on er.id = a.request_id
   where b.ics_token = p_token
   limit 1;
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_booking_service_context(p_booking uuid DEFAULT NULL::uuid) RETURNS TABLE(booking_id uuid, booking_status public.airfnb_booking_status, starts_at timestamp with time zone, ends_at timestamp with time zone, pax_count integer, total_amount numeric, currency character, ics_token text, application_id uuid, request_id uuid, request_title text, request_city text, event_title text, organizer_display_name text, truck_id uuid, truck_name text, truck_slug text, truck_base_city text, agreed_price numeric, is_organizer boolean, is_owned boolean)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if auth.uid() is null
     or coalesce(pg_catalog.current_setting('request.jwt.claim.role', true), '') = 'service_role' then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;

  return query
  select booking.id,
         booking.status,
         booking.starts_at,
         booking.ends_at,
         booking.pax_count,
         booking.total_amount,
         booking.currency,
         booking.ics_token,
         booking.application_id,
         request.id,
         request.title,
         request.city,
         event_row.title,
         organizer.display_name,
         truck.id,
         truck.name,
         truck.slug,
         truck.base_city,
         booking_truck.agreed_price,
         booking.organizer_id = auth.uid(),
         truck.owner_id = auth.uid()
    from public.airfnb_bookings as booking
    join public.airfnb_booking_trucks as booking_truck
      on booking_truck.booking_id = booking.id
    join public.airfnb_trucks as truck on truck.id = booking_truck.truck_id
    left join public.airfnb_applications as application
      on application.id = booking.application_id
    left join public.airfnb_event_requests as request
      on request.id = application.request_id
    left join public.airfnb_events as event_row on event_row.id = booking.event_id
    left join public.airfnb_profiles as organizer on organizer.id = booking.organizer_id
   where (p_booking is null or booking.id = p_booking)
     and (
       booking.organizer_id = auth.uid()
       or truck.owner_id = auth.uid()
     )
   order by booking.starts_at, booking.id, truck.id;
end
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_calculate_lock_fee(p_application uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_platform_fee    numeric;
  v_organizer_share numeric;
begin
  -- Read from settings table; fall back to the historical 25/25 split.
  -- Clamp to >= 0 so an admin typo (negative number) can't produce a
  -- negative lock-fee. (p_application is still part of the signature
  -- so callers don't change, but the calculation no longer depends on
  -- application data.)
  v_platform_fee    := greatest(0, public.airfnb_setting_int('lock_fee.platform_fee',    25));
  v_organizer_share := greatest(0, public.airfnb_setting_int('lock_fee.organizer_share', 25));

  return jsonb_build_object(
    'platform_fee',    v_platform_fee,
    'organizer_share', v_organizer_share,
    'total',           v_platform_fee + v_organizer_share
  );
end $$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_can_manage_truck(p_truck_text text) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $_$
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
$_$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_can_read_truck_child(p_truck_text text) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $_$
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
$_$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_can_submit_application(p_request uuid, p_truck uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select auth.uid() is not null
    and exists (
      select 1
        from public.airfnb_trucks as truck
        join public.airfnb_event_requests as request_row
          on request_row.id = p_request
       where truck.id = p_truck
         and truck.owner_id = auth.uid()
         and truck.status = 'active'::public.airfnb_truck_status
         and request_row.status = 'open'::public.airfnb_request_status
         and request_row.start_at > pg_catalog.now()
         and (
           request_row.applications_deadline is null
           or request_row.applications_deadline > pg_catalog.now()
         )
         and (
           request_row.visibility = 'public'
           or exists (
             select 1
               from public.airfnb_request_invitations as invitation
              where invitation.request_id = request_row.id
                and invitation.truck_id = truck.id
           )
         )
    )
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_check_rate_limit(p_action text, p_bucket text, p_limit_per_window integer, p_window_seconds integer) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
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
$_$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_profiles (
    id uuid NOT NULL,
    role public.airfnb_user_role,
    full_name text,
    display_name text,
    phone text,
    avatar_url text,
    locale text DEFAULT 'pt-PT'::text,
    vat_number text,
    company_name text,
    marketing_opt_in boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    onboarding_completed boolean DEFAULT false,
    organizer_rating_avg numeric(2,1) DEFAULT 0,
    organizer_rating_count integer DEFAULT 0,
    referral_code text,
    referred_by uuid,
    referrals_count integer DEFAULT 0,
    address_line text,
    billing_address_line text
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_membership_tombstones (
    user_id uuid NOT NULL,
    deleted_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    storage_truck_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_claim_role(p_role public.airfnb_user_role) RETURNS public.airfnb_profiles
    LANGUAGE plpgsql VOLATILE SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_conversation_peers() RETURNS TABLE(conversation_id uuid, user_id uuid, display_name text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_conversation_summaries() RETURNS TABLE(conversation_id uuid, last_message_body text, last_message_at timestamp with time zone, last_message_sender uuid, unread_count integer)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  with my_parts as (
    select conversation_id, last_read_at
      from public.airfnb_conversation_participants
     where user_id = auth.uid()
  )
  select
    mp.conversation_id,
    last_msg.body       as last_message_body,
    last_msg.created_at as last_message_at,
    last_msg.sender_id  as last_message_sender,
    (select count(*)::int
       from public.airfnb_messages m
      where m.conversation_id = mp.conversation_id
        and m.sender_id is distinct from auth.uid()
        and (mp.last_read_at is null or m.created_at > mp.last_read_at)
    ) as unread_count
  from my_parts mp
  -- LATERAL pulls the last message as ONE row, so body/sender/created_at
  -- are guaranteed to come from the same record. Three separate subqueries
  -- could return mismatched fields on created_at ties.
  left join lateral (
    select m.body, m.created_at, m.sender_id
      from public.airfnb_messages m
     where m.conversation_id = mp.conversation_id
     order by m.created_at desc, m.id desc
     limit 1
  ) last_msg on true;
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_ensure_profile(p_full_name text DEFAULT NULL::text, p_locale text DEFAULT 'pt-PT'::text) RETURNS public.airfnb_profiles
    LANGUAGE plpgsql VOLATILE SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_event_request_notify_admins() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if new.assistance_requested = true then
    insert into public.airfnb_notifications (user_id, kind, payload)
      select id, 'request.assistance_requested', jsonb_build_object(
        'request_id',    new.id,
        'request_title', new.title,
        'organizer_id',  new.organizer_id,
        'city',          new.city,
        'expected_pax',  new.expected_pax,
        'start_at',      new.start_at
      )
        from public.airfnb_profiles
       where role in ('admin', 'staff');
  end if;
  return new;
end $$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_event_request_visibility_sync() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if new.discovery_mode = 'curated' then
    new.visibility := 'invite_only';
  elsif new.discovery_mode in ('broadcast', 'auto_match') and new.visibility is null then
    new.visibility := 'public';
  end if;
  return new;
end $$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_event_requests_rate_limit() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_max int;
begin
  -- Clamp to >= 1 so an admin setting of 0 doesn't block every insert.
  v_max := greatest(1, public.airfnb_setting_int('rate_limit.event_requests_per_day', 10));
  if not public.airfnb_check_rate_limit(
       'event_request_create',
       new.organizer_id::text,
       v_max,
       86400
     ) then
    raise exception 'Rate limit exceeded: max % pedidos publicados por dia', v_max;
  end if;
  return new;
end $$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_expire_stale_lock_fees() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare n int := 0;
begin
  with expired as (
    update public.airfnb_lock_fees
       set status = 'expired'
     where status = 'pending' and due_until < now()
     returning id, application_id
  ),
  app_updates as (
    update public.airfnb_applications a
       set status = 'expired', decided_at = now()
      from expired e
     where a.id = e.application_id
     returning a.id, a.truck_id
  ),
  booking_updates as (
    update public.airfnb_bookings b
       set status = 'cancelled',
           cancellation_reason = 'lock_fee_expired'
      from expired e
     where b.application_id = e.application_id and b.status = 'pending_lock_fee'
     returning b.id
  )
  select count(*) into n from expired;
  return n;
end $$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_expire_stale_requests() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare n int;
begin
  with x as (
    update public.airfnb_event_requests
       set status = 'expired'
     where status = 'open'
       and applications_deadline is not null
       and applications_deadline < now()
     returning id
  )
  select count(*) into n from x;
  return n;
end $$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_find_matching_requests(p_truck uuid, p_limit integer DEFAULT 20) RETURNS TABLE(request_id uuid, title text, city text, start_at timestamp with time zone, expected_pax integer, budget_min numeric, budget_max numeric, match_score numeric)
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select r.id, r.title, r.city, r.start_at, r.expected_pax, r.budget_min, r.budget_max,
         public.airfnb_match_score(p_truck, r.id) as match_score
    from public.airfnb_event_requests r
   where r.status = 'open'
     and (r.applications_deadline is null or r.applications_deadline > now())
     and not exists (
       select 1 from public.airfnb_applications a
       where a.request_id = r.id and a.truck_id = p_truck
     )
   order by match_score desc, r.start_at asc
   limit greatest(1, p_limit);
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_find_matching_trucks(p_request uuid, p_limit integer DEFAULT 12) RETURNS TABLE(truck_id uuid, name text, base_city text, rating_avg numeric, match_score numeric)
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select t.id, t.name, t.base_city, t.rating_avg,
         public.airfnb_match_score(t.id, p_request) as match_score
    from public.airfnb_trucks t
   where t.status = 'active'
   order by match_score desc, t.rating_avg desc
   limit greatest(1, p_limit);
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_generate_referral_code() RETURNS text
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
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
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_guard_profile_role() RETURNS trigger
    LANGUAGE plpgsql VOLATILE
    SET search_path TO 'pg_catalog', 'public'
    AS $$
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
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_guard_truck_moderation() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
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
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_invitation_candidates(p_request uuid) RETURNS TABLE(truck_id uuid, slug text, name text, base_city text, cover_url text, capacity integer, rating_avg numeric, rating_count integer, cuisine_types text[], category_slugs text[], already_invited boolean)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if auth.uid() is null
     or coalesce(pg_catalog.current_setting('request.jwt.claim.role', true), '') = 'service_role' then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;

  return query
  with request_row as (
    select request.id,
           coalesce(nullif(pg_catalog.btrim(request.city), ''),
                    nullif(pg_catalog.btrim(request.locality), '')) as wanted_city,
           request.expected_pax,
           request.desired_cuisines
      from public.airfnb_event_requests as request
     where request.id = p_request
       and request.organizer_id = auth.uid()
       and request.status in (
         'open'::public.airfnb_request_status,
         'reviewing'::public.airfnb_request_status
       )
  )
  select truck.id,
         truck.slug,
         truck.name,
         truck.base_city,
         (
           select image.url
             from public.airfnb_truck_images as image
            where image.truck_id = truck.id
            order by case image.kind
                       when 'truck' then 1 when 'food' then 2
                       when 'venue' then 3 when 'team' then 4 else 5
                     end,
                     case when image.is_cover then 0 else 1 end,
                     image.sort_order,
                     image.id
            limit 1
         ),
         truck.capacity,
         truck.rating_avg,
         truck.rating_count,
         truck.cuisine_types,
         array(
           select category.slug
             from public.airfnb_truck_categories as truck_category
             join public.airfnb_categories as category
               on category.id = truck_category.category_id
            where truck_category.truck_id = truck.id
            order by category.slug
         ),
         exists (
           select 1
             from public.airfnb_request_invitations as invitation
            where invitation.request_id = request_row.id
              and invitation.truck_id = truck.id
         )
    from request_row
    join public.airfnb_trucks as truck
      on truck.status = 'active'::public.airfnb_truck_status
   where (
       request_row.wanted_city is null
       or pg_catalog.strpos(
            pg_catalog.lower(coalesce(truck.base_city, '')),
            pg_catalog.lower(request_row.wanted_city)
          ) > 0
     )
     and (request_row.expected_pax is null or truck.capacity >= request_row.expected_pax)
     and (
       coalesce(pg_catalog.cardinality(request_row.desired_cuisines), 0) = 0
       or truck.cuisine_types && request_row.desired_cuisines
     )
   order by truck.rating_avg desc nulls last, truck.id
   limit 80;
end
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_invite_request_services(p_request uuid, p_trucks uuid[]) RETURNS TABLE(truck_id uuid)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_request_owner uuid;
  v_request_status public.airfnb_request_status;
  v_request_title text;
  v_request_city text;
  v_request_locality text;
  v_request_expected_pax integer;
  v_request_desired_cuisines text[];
  v_trucks uuid[];
  v_city text;
  v_expected integer;
  v_inserted uuid;
begin
  if v_uid is null
     or coalesce(pg_catalog.current_setting('request.jwt.claim.role', true), '') = 'service_role' then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;

  if p_request is null then
    raise exception using errcode = '22023', message = 'request is required';
  end if;

  select pg_catalog.array_agg(input.truck_id order by input.truck_id)
    into v_trucks
    from (
      select distinct item as truck_id
        from pg_catalog.unnest(coalesce(p_trucks, array[]::uuid[])) as item
       where item is not null
    ) as input;

  if coalesce(pg_catalog.cardinality(v_trucks), 0) = 0 then
    raise exception using errcode = '22023', message = 'at least one service is required';
  end if;
  if pg_catalog.cardinality(v_trucks) > 80 then
    raise exception using errcode = '22023', message = 'too many services';
  end if;

  select request.organizer_id, request.status, request.title,
         request.city, request.locality, request.expected_pax,
         request.desired_cuisines
    into v_request_owner, v_request_status, v_request_title,
         v_request_city, v_request_locality, v_request_expected_pax,
         v_request_desired_cuisines
    from public.airfnb_event_requests as request
   where request.id = p_request
   for update;

  if not found or v_request_owner <> v_uid then
    raise exception using errcode = '42501', message = 'request is not manageable';
  end if;
  if v_request_status not in (
       'open'::public.airfnb_request_status,
       'reviewing'::public.airfnb_request_status
     ) then
    raise exception using errcode = '22023', message = 'request is not open for invitations';
  end if;

  -- Consistent lock ordering prevents a status edit from racing eligibility
  -- and prevents two multi-service invitation calls from deadlocking.
  perform 1
    from public.airfnb_trucks as truck
   where truck.id = any(v_trucks)
   order by truck.id
   for share;

  v_city := coalesce(nullif(pg_catalog.btrim(v_request_city), ''),
                     nullif(pg_catalog.btrim(v_request_locality), ''));

  select pg_catalog.count(*)::integer
    into v_expected
    from public.airfnb_trucks as truck
   where truck.id = any(v_trucks)
     and truck.status = 'active'::public.airfnb_truck_status
     and (
       v_city is null
       or pg_catalog.strpos(
            pg_catalog.lower(coalesce(truck.base_city, '')),
            pg_catalog.lower(v_city)
          ) > 0
     )
     and (v_request_expected_pax is null or truck.capacity >= v_request_expected_pax)
     and (
       coalesce(pg_catalog.cardinality(v_request_desired_cuisines), 0) = 0
       or truck.cuisine_types && v_request_desired_cuisines
     );

  if v_expected <> pg_catalog.cardinality(v_trucks) then
    raise exception using errcode = '22023', message = 'one or more services are not eligible';
  end if;

  for v_inserted in
    insert into public.airfnb_request_invitations(request_id, truck_id, invited_by)
    select p_request, input.truck_id, v_uid
      from pg_catalog.unnest(v_trucks) as input(truck_id)
     order by input.truck_id
    on conflict on constraint airfnb_request_invitations_pkey do nothing
    returning airfnb_request_invitations.truck_id
  loop
    insert into public.airfnb_notifications(user_id, kind, payload)
    select truck.owner_id,
           'request.invited',
           pg_catalog.jsonb_build_object(
             'request_id', p_request,
             'request_title', v_request_title,
             'truck_id', truck.id,
             'truck_name', truck.name
           )
      from public.airfnb_trucks as truck
     where truck.id = v_inserted;

    truck_id := v_inserted;
    return next;
  end loop;
end
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_is_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (select 1 from public.airfnb_profiles where id = auth.uid() and role in ('admin','staff'))
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_is_truck_owner(p_truck_text text) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
declare
  v_uuid uuid;
begin
  if p_truck_text is null or p_truck_text !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    return false;
  end if;
  v_uuid := p_truck_text::uuid;
  return exists (
    select 1 from public.airfnb_trucks
     where id = v_uuid and owner_id = auth.uid()
  );
end $_$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_is_truck_owner(p_truck_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.airfnb_trucks
     where id = p_truck_id
       and owner_id = auth.uid()
  );
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_make_ics_token() RETURNS text
    LANGUAGE plpgsql
    AS $$
declare v_t text;
begin
  loop
    v_t := upper(substr(encode(gen_random_bytes(12), 'base64'), 1, 16));
    v_t := regexp_replace(v_t, '[+/=0OIL]', 'X', 'g');
    exit when not exists (select 1 from public.airfnb_bookings where ics_token = v_t);
  end loop;
  return v_t;
end $$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_mark_conversation_read(p_conversation uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'conversation access denied';
  end if;

  update public.airfnb_conversation_participants cp
     set last_read_at = greatest(
       coalesce(cp.last_read_at, '-infinity'::timestamptz),
       statement_timestamp()
     )
   where cp.conversation_id = p_conversation
     and cp.user_id = v_actor;

  if not found then
    raise exception using errcode = '42501', message = 'conversation access denied';
  end if;
end;
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_match_category_availability_score(p_truck uuid, p_request uuid) RETURNS numeric
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_match_score(p_truck uuid, p_request uuid) RETURNS numeric
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
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
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_match_scores_batch(p_truck_ids uuid[], p_request_ids uuid[]) RETURNS TABLE(truck_id uuid, request_id uuid, score numeric)
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select t.id, r.id, public.airfnb_match_score(t.id, r.id) as score
    from public.airfnb_trucks t
    cross join public.airfnb_event_requests r
   where t.id  = any(p_truck_ids)
     and r.id  = any(p_request_ids)
     and public.airfnb_match_score(t.id, r.id) > 0
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_notify_application_received() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_organizer uuid;
  v_truck_name text;
begin
  select organizer_id into v_organizer
    from public.airfnb_event_requests
   where id = new.request_id;
  if v_organizer is null then return new; end if;

  select name into v_truck_name
    from public.airfnb_trucks
   where id = new.truck_id;

  insert into public.airfnb_notifications (user_id, kind, payload)
  values (
    v_organizer,
    'application.received',
    jsonb_build_object(
      'application_id', new.id,
      'request_id',     new.request_id,
      'truck_id',       new.truck_id,
      'truck_name',     v_truck_name,
      'proposed_price', new.proposed_price
    )
  );
  return new;
end $$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_organizer_rating_recompute() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
declare
  v_organizer_id uuid;
begin
  for v_organizer_id in
    select distinct candidate
      from unnest(array[
        case when tg_op <> 'INSERT' then old.organizer_id else null end,
        case when tg_op <> 'DELETE' then new.organizer_id else null end
      ]) candidate
     where candidate is not null
     order by candidate
  loop
    update public.airfnb_profiles p
       set organizer_rating_avg = coalesce((
             select round(avg(r.rating_overall)::numeric, 1)
               from public.airfnb_organizer_reviews r
              where r.organizer_id = v_organizer_id
           ), 0),
           organizer_rating_count = (
             select count(*)
               from public.airfnb_organizer_reviews r
              where r.organizer_id = v_organizer_id
           )
     where p.id = v_organizer_id;
  end loop;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_own_application_truck() RETURNS TABLE(truck_id uuid, truck_name text, truck_status public.airfnb_truck_status)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select truck.id, truck.name, truck.status
    from public.airfnb_trucks as truck
   where auth.uid() is not null
     and coalesce(
       pg_catalog.current_setting('request.jwt.claim.role', true), ''
     ) <> 'service_role'
     and truck.owner_id = auth.uid()
   order by truck.created_at, truck.id
   limit 1
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_platform_settings_touch() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at := now();
  return new;
end $$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_prepare_organizer_review() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
declare
  v_actor uuid := auth.uid();
  v_organizer uuid;
  v_status public.airfnb_booking_status;
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;
  if new.rating_reliability is null
     or new.rating_communication is null
     or new.rating_payment is null
     or new.rating_reliability not between 1 and 5
     or new.rating_communication not between 1 and 5
     or new.rating_payment not between 1 and 5 then
    raise exception using errcode = '23514', message = 'organizer review ratings must be between 1 and 5';
  end if;

  select b.organizer_id, b.status
    into v_organizer, v_status
    from public.airfnb_bookings b
   where b.id = new.booking_id;
  if not found or v_status not in ('confirmed', 'completed') then
    raise exception using errcode = '23514', message = 'booking is not reviewable';
  end if;
  if not exists (
    select 1
      from public.airfnb_booking_trucks bt
      join public.airfnb_trucks t on t.id = bt.truck_id
     where bt.booking_id = new.booking_id
       and bt.truck_id = new.truck_id
       and t.owner_id = v_actor
  ) then
    raise exception using errcode = '42501', message = 'only a participating truck owner may review this organizer';
  end if;

  new.organizer_id := v_organizer;
  new.rating_overall := round((new.rating_reliability + new.rating_communication + new.rating_payment)::numeric / 3, 1);
  new.is_verified := true;
  new.reply_body := null;
  new.reply_at := null;
  new.created_at := statement_timestamp();
  return new;
end;
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_prepare_truck_review() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
declare
  v_actor uuid := auth.uid();
  v_organizer uuid;
  v_status public.airfnb_booking_status;
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;
  if new.rating_food is null
     or new.rating_service is null
     or new.rating_value is null
     or new.rating_food not between 1 and 5
     or new.rating_service not between 1 and 5
     or new.rating_value not between 1 and 5 then
    raise exception using errcode = '23514', message = 'truck review ratings must be between 1 and 5';
  end if;

  select b.organizer_id, b.status
    into v_organizer, v_status
    from public.airfnb_bookings b
   where b.id = new.booking_id;
  if not found or v_status not in ('confirmed', 'completed') then
    raise exception using errcode = '23514', message = 'booking is not reviewable';
  end if;
  if v_organizer is distinct from v_actor then
    raise exception using errcode = '42501', message = 'only the booking organizer may review this truck';
  end if;
  if not exists (
    select 1
      from public.airfnb_booking_trucks bt
     where bt.booking_id = new.booking_id
       and bt.truck_id = new.truck_id
  ) then
    raise exception using errcode = '23514', message = 'truck did not participate in this booking';
  end if;

  new.organizer_id := v_organizer;
  new.rating_overall := round((new.rating_food + new.rating_service + new.rating_value)::numeric / 3, 1);
  new.is_verified := true;
  new.reply_body := null;
  new.reply_at := null;
  new.created_at := statement_timestamp();
  return new;
end;
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_event_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organizer_id uuid NOT NULL,
    title text NOT NULL,
    kind public.airfnb_event_kind,
    description text,
    start_at timestamp with time zone NOT NULL,
    end_at timestamp with time zone,
    city text,
    address_id uuid,
    expected_pax integer NOT NULL,
    slots_needed integer,
    budget_min numeric(10,2),
    budget_max numeric(10,2),
    desired_categories integer[] DEFAULT '{}'::integer[],
    dietary_requirements public.airfnb_dietary_tag[] DEFAULT '{}'::public.airfnb_dietary_tag[],
    applications_deadline timestamp with time zone,
    power_available boolean DEFAULT false,
    water_available boolean DEFAULT false,
    notes text,
    status public.airfnb_request_status DEFAULT 'open'::public.airfnb_request_status,
    visibility text DEFAULT 'public'::text,
    awarded_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    discovery_mode public.airfnb_discovery_mode DEFAULT 'broadcast'::public.airfnb_discovery_mode,
    accepted_deal_types text[] DEFAULT ARRAY['fixed'::text, 'percent'::text, 'mixed'::text],
    min_fixed_fee numeric(10,2),
    min_revenue_share_pct numeric(5,2),
    recommended_slots integer,
    slot_breakdown jsonb,
    application_response_window_hours integer DEFAULT 48,
    contact_name text,
    contact_email text,
    contact_phone text,
    address_line text,
    locality text,
    budget_estimate numeric(10,2),
    budget_flexible boolean DEFAULT false,
    catering_type public.airfnb_catering_type DEFAULT 'food_and_drinks'::public.airfnb_catering_type,
    desired_cuisines text[] DEFAULT '{}'::text[],
    setup_minutes integer,
    teardown_minutes integer,
    energy_need public.airfnb_energy_need,
    energy_assistance boolean DEFAULT false,
    sanitation_level public.airfnb_sanitation_level,
    extra_services text[] DEFAULT '{}'::text[],
    selection_mode public.airfnb_selection_mode DEFAULT 'open_to_offers'::public.airfnb_selection_mode,
    assistance_requested boolean DEFAULT false,
    water_provided text[] DEFAULT '{}'::text[] NOT NULL,
    wc_provided text[] DEFAULT '{}'::text[] NOT NULL,
    CONSTRAINT airfnb_event_requests_expected_pax_check CHECK ((expected_pax > 0)),
    CONSTRAINT airfnb_event_requests_slots_needed_check CHECK (((slots_needed >= 1) AND (slots_needed <= 10))),
    CONSTRAINT airfnb_event_requests_visibility_check CHECK ((visibility = ANY (ARRAY['public'::text, 'invite_only'::text])))
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_private_event_requests(p_request_id uuid DEFAULT NULL::uuid) RETURNS SETOF public.airfnb_event_requests
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select request_row.*
    from public.airfnb_event_requests as request_row
   where auth.uid() is not null
     and (p_request_id is null or request_row.id = p_request_id)
     and (
       request_row.organizer_id = auth.uid()
       or (
         p_request_id is not null
         and public.airfnb_is_admin()
       )
     )
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_public_service_detail(p_slug text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_payload jsonb;
  v_slug text := pg_catalog.btrim(coalesce(p_slug, ''));
begin
  if v_slug = '' or pg_catalog.length(v_slug) > 200 then
    return null;
  end if;

  select pg_catalog.jsonb_build_object(
           'id', truck.id,
           'slug', truck.slug,
           'name', truck.name,
           'tagline', truck.tagline,
           'description', truck.description,
           'base_city', truck.base_city,
           'service_radius_km', truck.service_radius_km,
           'capacity', truck.capacity,
           'min_event_pax', truck.min_event_pax,
           'max_event_pax', truck.max_event_pax,
           'base_price', truck.base_price,
           'price_per_pax', truck.price_per_pax,
           'setup_minutes', truck.setup_minutes,
           'teardown_minutes', truck.teardown_minutes,
           'power_required_kw', truck.power_required_kw,
           'needs_water', truck.needs_water,
           'dimensions_m', truck.dimensions_m,
           'sanitation_required', truck.sanitation_required,
           'catering_type', truck.catering_type,
           'serves', truck.serves,
           'cuisine_types', truck.cuisine_types,
           'dietary_options', truck.dietary_options,
           'compatible_event_kinds', truck.compatible_event_kinds,
           'service_type', truck.service_type,
           'status', truck.status,
           'rating_avg', truck.rating_avg,
           'rating_count', truck.rating_count,
           'lead_response_rate', truck.lead_response_rate,
           'homologation_state', case
             when truck.homologation_expires_at is null then 'unknown'
             when truck.homologation_expires_at < current_date then 'expired'
             when truck.homologation_expires_at <= current_date + 30 then 'expiring'
             else 'valid'
           end,
           'insurance_state', case
             when truck.insurance_expires_at is null then 'unknown'
             when truck.insurance_expires_at < current_date then 'expired'
             when truck.insurance_expires_at <= current_date + 30 then 'expiring'
             else 'valid'
           end,
           'owner', pg_catalog.jsonb_build_object(
             'display_name', profile.display_name,
             'avatar_url', profile.avatar_url,
             'member_since_year', extract(year from profile.created_at)::integer
           ),
           'images', coalesce((
             select pg_catalog.jsonb_agg(
                      pg_catalog.jsonb_build_object(
                        'id', image_row.id,
                        'url', image_row.url,
                        'alt', image_row.alt,
                        'is_cover', image_row.is_cover,
                        'sort_order', image_row.sort_order,
                        'kind', image_row.kind
                      ) order by image_row.kind_rank,
                                 image_row.is_cover_rank,
                                 image_row.sort_order,
                                 image_row.id
                    )
               from (
                 select image.id,
                        image.url,
                        image.alt,
                        image.is_cover,
                        image.sort_order,
                        image.kind,
                        case image.kind
                          when 'truck' then 1 when 'food' then 2
                          when 'venue' then 3 when 'team' then 4 else 5
                        end as kind_rank,
                        case when image.is_cover then 0 else 1 end as is_cover_rank
                   from public.airfnb_truck_images as image
                  where image.truck_id = truck.id
                  order by kind_rank, is_cover_rank, image.sort_order, image.id
                  limit 12
               ) as image_row
           ), '[]'::jsonb),
           'menu_items', coalesce((
             select pg_catalog.jsonb_agg(
                      pg_catalog.jsonb_build_object(
                        'id', menu_row.id,
                        'name', menu_row.name,
                        'description', menu_row.description,
                        'price', menu_row.price,
                        'category', menu_row.category
                      ) order by menu_row.sort_order, menu_row.id
                    )
               from (
                 select menu.id, menu.name, menu.description, menu.price,
                        menu.category, menu.sort_order
                   from public.airfnb_menu_items as menu
                  where menu.truck_id = truck.id
                  order by menu.sort_order, menu.id
                  limit 100
               ) as menu_row
           ), '[]'::jsonb),
           'categories', coalesce((
             select pg_catalog.jsonb_agg(
                      pg_catalog.jsonb_build_object(
                        'slug', category_row.slug,
                        'name_pt', category_row.name_pt,
                        'icon', category_row.icon
                      ) order by category_row.slug
                    )
               from (
                 select category.slug, category.name_pt, category.icon
                   from public.airfnb_truck_categories as truck_category
                   join public.airfnb_categories as category
                     on category.id = truck_category.category_id
                  where truck_category.truck_id = truck.id
                  order by category.slug
                  limit 50
               ) as category_row
           ), '[]'::jsonb),
           'document_states', coalesce((
             select pg_catalog.jsonb_agg(
                      pg_catalog.jsonb_build_object(
                        'kind', document_row.kind,
                        'state', document_row.state
                      ) order by document_row.kind
                    )
               from (
                 select document.kind,
                        case
                          when document.expires_at is null then 'unknown'
                          when document.expires_at < current_date then 'expired'
                          when document.expires_at <= current_date + 30 then 'expiring'
                          else 'valid'
                        end as state
                   from public.airfnb_truck_documents as document
                  where document.truck_id = truck.id
                  order by document.kind, document.id
                  limit 8
               ) as document_row
           ), '[]'::jsonb)
         )
    into v_payload
    from public.airfnb_trucks as truck
    join public.airfnb_profiles as profile on profile.id = truck.owner_id
   where truck.slug = v_slug
     and truck.status = 'active'::public.airfnb_truck_status;

  return v_payload;
end
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_recalc_truck_rating() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
declare
  v_truck_id uuid;
begin
  for v_truck_id in
    select distinct candidate
      from unnest(array[
        case when tg_op <> 'INSERT' then old.truck_id else null end,
        case when tg_op <> 'DELETE' then new.truck_id else null end
      ]) candidate
     where candidate is not null
     order by candidate
  loop
    update public.airfnb_trucks t
       set rating_avg = coalesce((
             select round(avg(r.rating_overall)::numeric, 1)
               from public.airfnb_reviews r
              where r.truck_id = v_truck_id
           ), 0),
           rating_count = (
             select count(*)
               from public.airfnb_reviews r
              where r.truck_id = v_truck_id
           )
     where t.id = v_truck_id;
  end loop;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_recommend_slots(p_kind public.airfnb_event_kind, p_pax integer) RETURNS integer
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  select greatest(1, ceil(p_pax::numeric / case p_kind
    when 'wedding'    then 120
    when 'corporate'  then 150
    when 'festival'   then 200
    when 'conference' then 100
    when 'birthday'   then 130
    when 'private'    then 130
    else 150
  end))::int;
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_recommend_trucks_for_request(p_request uuid, p_limit integer DEFAULT 12) RETURNS TABLE(truck_id uuid, name text, base_city text, rating_avg numeric, match_score numeric, already_invited boolean, already_applied boolean)
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select
    t.id, t.name, t.base_city, t.rating_avg,
    public.airfnb_match_score(t.id, p_request) as match_score,
    exists (
      select 1 from public.airfnb_request_invitations ri
      where ri.request_id = p_request and ri.truck_id = t.id
    ) as already_invited,
    exists (
      select 1 from public.airfnb_applications a
      where a.request_id = p_request and a.truck_id = t.id
    ) as already_applied
    from public.airfnb_trucks t
   where t.status = 'active'
   order by match_score desc, t.rating_avg desc
   limit greatest(1, p_limit);
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_reconcile_stripe_event(p_event_id text, p_event_type text, p_event_created_at timestamp with time zone, p_application_id uuid, p_lock_fee_id uuid, p_booking_id uuid, p_payment_intent text, p_amount_minor bigint, p_currency text, p_payment_status text, p_refunded_amount_minor bigint DEFAULT 0) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_event_type text := pg_catalog.lower(pg_catalog.btrim(p_event_type));
  v_event_id text := pg_catalog.btrim(p_event_id);
  v_provider_ref text := pg_catalog.btrim(p_payment_intent);
  v_currency char(3);
  v_payment_status text := pg_catalog.lower(pg_catalog.btrim(p_payment_status));
  v_amount numeric(10,2);
  v_refunded_amount numeric(10,2);
  v_event_inserted boolean;
  v_existing_event public.airfnb_stripe_events%rowtype;
  v_application public.airfnb_applications%rowtype;
  v_lock_fee public.airfnb_lock_fees%rowtype;
  v_booking public.airfnb_bookings%rowtype;
  v_payment public.airfnb_payments%rowtype;
  v_payment_found boolean := false;
  v_result text;
begin
  if v_event_id is null or v_event_id = '' or pg_catalog.length(v_event_id) > 255 then
    raise exception using errcode = '22023', message = 'stripe event id is invalid';
  end if;
  if v_event_type is null or v_event_type not in ('checkout.session.completed','charge.refunded') then
    raise exception using errcode = '22023', message = 'unsupported stripe event type';
  end if;
  if p_event_created_at is null or p_event_created_at > pg_catalog.now() + interval '5 minutes' then
    raise exception using errcode = '22023', message = 'invalid stripe event time';
  end if;
  if p_application_id is null or p_lock_fee_id is null or p_booking_id is null then
    raise exception using errcode = '22023', message = 'application, lock fee and booking ids are required';
  end if;
  if v_provider_ref is null or v_provider_ref = '' or pg_catalog.length(v_provider_ref) > 255 then
    raise exception using errcode = '22023', message = 'stripe payment intent is invalid';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 or p_amount_minor > 9999999999 then
    raise exception using errcode = '22023', message = 'stripe amount is invalid';
  end if;
  if p_refunded_amount_minor is null or p_refunded_amount_minor < 0
     or p_refunded_amount_minor > p_amount_minor then
    raise exception using errcode = '22023', message = 'invalid cumulative refunded amount';
  end if;
  if p_currency is null or pg_catalog.btrim(p_currency) not in ('EUR','eur') then
    raise exception using errcode = '22023', message = 'stripe currency must be EUR';
  end if;

  v_currency := 'EUR'::char(3);
  v_amount := (p_amount_minor::numeric / 100)::numeric(10,2);
  v_refunded_amount := (p_refunded_amount_minor::numeric / 100)::numeric(10,2);

  if v_event_type = 'checkout.session.completed' then
    if v_payment_status <> 'paid' or p_refunded_amount_minor <> 0 then
      raise exception using errcode = '22023', message = 'checkout session is not a paid, non-refund event';
    end if;
  elsif v_payment_status <> 'succeeded' or p_refunded_amount_minor = 0 then
    raise exception using errcode = '22023', message = 'refund charge is not a succeeded refund event';
  end if;

  -- An already committed event can be validated without taking row locks on
  -- its foreign-key targets. A concurrent not-yet-committed event is handled
  -- again after the business-row serialization below.
  select * into v_existing_event from public.airfnb_stripe_events
   where event_id = v_event_id;
  if found then
    if v_existing_event.event_type is distinct from v_event_type
       or v_existing_event.event_created_at is distinct from p_event_created_at
       or v_existing_event.provider_ref is distinct from v_provider_ref
       or v_existing_event.application_id is distinct from p_application_id
       or v_existing_event.lock_fee_id is distinct from p_lock_fee_id
       or v_existing_event.booking_id is distinct from p_booking_id
       or v_existing_event.amount_minor is distinct from p_amount_minor
       or pg_catalog.btrim(v_existing_event.currency::text) is distinct from v_currency::text
       or v_existing_event.payment_status is distinct from v_payment_status
       or v_existing_event.refunded_amount_minor is distinct from p_refunded_amount_minor then
      raise exception using errcode = '23505', message = 'stripe event id conflicts with existing binding';
    end if;
    return pg_catalog.jsonb_build_object(
      'ok',true,'duplicate_event',true,'result',v_existing_event.processing_result,'event_id',v_event_id
    );
  end if;

  -- Lock order is deliberately stable across all calls. Business rows are
  -- locked before the ledger insert so its foreign-key key-share locks cannot
  -- deadlock while two distinct Stripe events reconcile the same payment.
  select * into v_lock_fee from public.airfnb_lock_fees
   where id = p_lock_fee_id for update;
  if not found then raise exception using errcode='P0002', message='lock fee not found'; end if;

  select * into v_application from public.airfnb_applications
   where id = p_application_id for update;
  if not found then raise exception using errcode='P0002', message='application not found'; end if;

  select * into v_booking from public.airfnb_bookings
   where id = p_booking_id for update;
  if not found then raise exception using errcode='P0002', message='booking not found'; end if;

  if v_application.status <> 'accepted'::public.airfnb_application_status
     or v_lock_fee.application_id <> v_application.id
     or v_booking.application_id is distinct from v_application.id then
    raise exception using errcode='23514', message='immutable marketplace binding is invalid';
  end if;
  if v_lock_fee.created_at is null or v_booking.created_at is null
     or p_event_created_at < v_lock_fee.created_at
     or p_event_created_at < v_booking.created_at then
    raise exception using errcode='22023', message='stripe event predates marketplace binding';
  end if;
  if v_lock_fee.amount is distinct from v_amount
     or pg_catalog.upper(pg_catalog.btrim(v_lock_fee.currency::text)) <> 'EUR'
     or v_booking.currency is null
     or pg_catalog.upper(pg_catalog.btrim(v_booking.currency::text)) <> 'EUR' then
    raise exception using errcode='22023', message='stripe amount or currency mismatch';
  end if;

  select * into v_payment from public.airfnb_payments
   where provider_ref = v_provider_ref for update;
  v_payment_found := found;

  insert into public.airfnb_stripe_events(
    event_id,event_type,event_created_at,provider_ref,application_id,
    lock_fee_id,booking_id,amount_minor,currency,payment_status,
    refunded_amount_minor
  ) values (
    v_event_id,v_event_type,p_event_created_at,v_provider_ref,p_application_id,
    p_lock_fee_id,p_booking_id,p_amount_minor,v_currency,v_payment_status,
    p_refunded_amount_minor
  ) on conflict (event_id) do nothing
  returning true into v_event_inserted;

  if not coalesce(v_event_inserted, false) then
    select * into v_existing_event from public.airfnb_stripe_events
     where event_id = v_event_id for update;
    if v_existing_event.event_type is distinct from v_event_type
       or v_existing_event.event_created_at is distinct from p_event_created_at
       or v_existing_event.provider_ref is distinct from v_provider_ref
       or v_existing_event.application_id is distinct from p_application_id
       or v_existing_event.lock_fee_id is distinct from p_lock_fee_id
       or v_existing_event.booking_id is distinct from p_booking_id
       or v_existing_event.amount_minor is distinct from p_amount_minor
       or pg_catalog.btrim(v_existing_event.currency::text) is distinct from v_currency::text
       or v_existing_event.payment_status is distinct from v_payment_status
       or v_existing_event.refunded_amount_minor is distinct from p_refunded_amount_minor then
      raise exception using errcode = '23505', message = 'stripe event id conflicts with existing binding';
    end if;
    return pg_catalog.jsonb_build_object(
      'ok',true,'duplicate_event',true,'result',v_existing_event.processing_result,'event_id',v_event_id
    );
  end if;

  if v_payment_found and (
       v_payment.application_id is distinct from v_application.id
       or v_payment.lock_fee_id is distinct from v_lock_fee.id
       or v_payment.booking_id is distinct from v_booking.id
       or v_payment.amount is distinct from v_amount
       or pg_catalog.upper(pg_catalog.btrim(v_payment.currency::text)) <> 'EUR'
       or v_payment.method <> 'stripe'::public.airfnb_payment_method
       or v_payment.direction <> 'truck_to_platform'::public.airfnb_payment_direction
       or v_payment.kind <> 'lock_fee'::public.airfnb_payment_kind
     ) then
    raise exception using errcode='23505', message='payment intent conflicts with existing binding';
  end if;

  if v_lock_fee.provider_ref is not null and v_lock_fee.provider_ref <> v_provider_ref then
    raise exception using errcode='23505', message='lock fee conflicts with another payment intent';
  end if;

  if v_event_type = 'checkout.session.completed' then
    if p_event_created_at > v_lock_fee.due_until then
      raise exception using errcode='22023', message='lock fee payment arrived after due time';
    end if;
    if v_payment_found then
      if v_payment.status not in ('paid'::public.airfnb_payment_status,'refunded'::public.airfnb_payment_status)
         or v_lock_fee.status not in ('paid'::public.airfnb_lock_fee_status,'refunded'::public.airfnb_lock_fee_status)
         or v_booking.status not in ('confirmed'::public.airfnb_booking_status,'refunded'::public.airfnb_booking_status) then
        raise exception using errcode='23514', message='payment replay conflicts with marketplace state';
      end if;
      v_result := 'payment_replay';
    else
      if v_lock_fee.status <> 'pending'::public.airfnb_lock_fee_status
         or v_booking.status <> 'pending_lock_fee'::public.airfnb_booking_status
         or v_lock_fee.provider_ref is not null then
        raise exception using errcode='55000', message='payment is not pending';
      end if;
      if exists (select 1 from public.airfnb_payments where lock_fee_id = v_lock_fee.id) then
        raise exception using errcode='23505', message='lock fee already has a payment';
      end if;

      update public.airfnb_lock_fees
         set status='paid'::public.airfnb_lock_fee_status,
             paid_at=p_event_created_at,
             provider_ref=v_provider_ref,
             provider_event_log=provider_event_log || pg_catalog.jsonb_build_array(
               pg_catalog.jsonb_build_object('id',v_event_id,'type',v_event_type,'created_at',p_event_created_at)
             )
       where id=v_lock_fee.id;
      insert into public.airfnb_payments(
        booking_id,application_id,lock_fee_id,amount,currency,method,status,
        direction,kind,provider_ref,paid_at,refunded_amount,last_provider_event_at
      ) values (
        v_booking.id,v_application.id,v_lock_fee.id,v_amount,v_currency,
        'stripe'::public.airfnb_payment_method,'paid'::public.airfnb_payment_status,
        'truck_to_platform'::public.airfnb_payment_direction,
        'lock_fee'::public.airfnb_payment_kind,v_provider_ref,p_event_created_at,0,p_event_created_at
      );
      update public.airfnb_bookings set status='confirmed'::public.airfnb_booking_status
       where id=v_booking.id;
      v_result := 'payment_confirmed';
    end if;
  else
    if not v_payment_found then
      raise exception using errcode='55000', message='refund arrived before payment';
    end if;
    if v_payment.status not in ('paid'::public.airfnb_payment_status,'refunded'::public.airfnb_payment_status)
       or v_payment.paid_at is null or p_event_created_at < v_payment.paid_at
       or v_lock_fee.status not in ('paid'::public.airfnb_lock_fee_status,'refunded'::public.airfnb_lock_fee_status)
       or v_booking.status not in ('confirmed'::public.airfnb_booking_status,'refunded'::public.airfnb_booking_status) then
      raise exception using errcode='23514', message='refund conflicts with marketplace state';
    end if;

    if v_refunded_amount < v_payment.refunded_amount then
      v_result := 'stale_refund_ignored';
    elsif v_refunded_amount = v_payment.refunded_amount then
      v_result := 'refund_replay';
    elsif v_refunded_amount < v_amount then
      if v_payment.status='refunded'::public.airfnb_payment_status
         or v_lock_fee.status='refunded'::public.airfnb_lock_fee_status
         or v_booking.status='refunded'::public.airfnb_booking_status then
        raise exception using errcode='23514', message='partial refund conflicts with terminal state';
      end if;
      update public.airfnb_payments
         set refunded_amount=v_refunded_amount,
             last_provider_event_at=greatest(
               coalesce(last_provider_event_at,p_event_created_at),p_event_created_at
             )
       where id=v_payment.id;
      update public.airfnb_lock_fees
         set provider_event_log=provider_event_log || pg_catalog.jsonb_build_array(
           pg_catalog.jsonb_build_object('id',v_event_id,'type',v_event_type,
             'created_at',p_event_created_at,'refunded_amount',v_refunded_amount)
         )
       where id=v_lock_fee.id;
      v_result := 'partial_refund_recorded';
    else
      update public.airfnb_payments
         set status='refunded'::public.airfnb_payment_status,
             refunded_amount=v_amount,
             last_provider_event_at=greatest(
               coalesce(last_provider_event_at,p_event_created_at),p_event_created_at
             )
       where id=v_payment.id;
      update public.airfnb_lock_fees
         set status='refunded'::public.airfnb_lock_fee_status,
             refunded_at=coalesce(refunded_at,p_event_created_at),
             provider_event_log=provider_event_log || pg_catalog.jsonb_build_array(
               pg_catalog.jsonb_build_object('id',v_event_id,'type',v_event_type,
                 'created_at',p_event_created_at,'refunded_amount',v_amount)
             )
       where id=v_lock_fee.id;
      update public.airfnb_bookings set status='refunded'::public.airfnb_booking_status
       where id=v_booking.id;
      v_result := 'full_refund_reconciled';
    end if;
  end if;

  update public.airfnb_stripe_events
     set processing_result=v_result, processed_at=pg_catalog.now()
   where event_id=v_event_id;

  return pg_catalog.jsonb_build_object(
    'ok',true,'duplicate_event',false,'result',v_result,'event_id',v_event_id,
    'application_id',v_application.id,'lock_fee_id',v_lock_fee.id,
    'booking_id',v_booking.id,'payment_intent',v_provider_ref,
    'refunded_amount',v_refunded_amount
  );
end
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_reject_application(p_application uuid, p_reason text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
declare
  v_application public.airfnb_applications%rowtype;
  v_request public.airfnb_event_requests%rowtype;
  v_actor uuid := auth.uid();
  v_signed_service_role boolean := coalesce(
    current_setting('request.jwt.claim.role', true), ''
  ) = 'service_role';
begin
  select * into v_application
    from public.airfnb_applications
   where id = p_application
   for update;
  if not found then
    raise exception using errcode = '22023', message = 'application not found';
  end if;

  select * into v_request
    from public.airfnb_event_requests
   where id = v_application.request_id
   for update;
  if not found then
    raise exception using errcode = '55000', message = 'request not found';
  end if;

  if not v_signed_service_role and (
    v_actor is null or (
      v_actor is distinct from v_request.organizer_id
      and not public.airfnb_is_admin()
    )
  ) then
    raise exception using errcode = '42501', message = 'not authorized';
  end if;
  if v_request.status is null or v_request.status not in ('open', 'reviewing', 'awarded') then
    raise exception using errcode = '55000',
      message = 'request cannot reject applications';
  end if;
  if v_application.status is null
     or v_application.status not in ('submitted', 'shortlisted') then
    raise exception using errcode = '55000',
      message = 'application is not eligible for rejection';
  end if;

  update public.airfnb_applications
     set status = 'rejected', decided_at = pg_catalog.statement_timestamp()
   where id = v_application.id;

  insert into public.airfnb_notifications(user_id, kind, payload)
  select truck.owner_id,
         'application.rejected',
         pg_catalog.jsonb_build_object(
           'application_id', v_application.id,
           'request_id', v_request.id,
           'reason', p_reason
         )
    from public.airfnb_trucks as truck
   where truck.id = v_application.truck_id;
end
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_reply_to_organizer_review(p_review uuid, p_reply text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
declare
  v_actor uuid := auth.uid();
  v_reply text := nullif(btrim(p_reply), '');
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;
  if v_reply is null or char_length(v_reply) > 2000 then
    raise exception using errcode = '22023', message = 'reply must contain between 1 and 2000 characters';
  end if;

  update public.airfnb_organizer_reviews r
     set reply_body = v_reply,
         reply_at = statement_timestamp()
   where r.id = p_review
     and r.organizer_id = v_actor;
  if not found then
    raise exception using errcode = '42501', message = 'only the reviewed organizer may reply';
  end if;
end;
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_reply_to_truck_review(p_review uuid, p_reply text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
declare
  v_actor uuid := auth.uid();
  v_reply text := nullif(btrim(p_reply), '');
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;
  if v_reply is null or char_length(v_reply) > 2000 then
    raise exception using errcode = '22023', message = 'reply must contain between 1 and 2000 characters';
  end if;

  update public.airfnb_reviews r
     set reply_body = v_reply,
         reply_at = statement_timestamp()
   where r.id = p_review
     and exists (
       select 1
         from public.airfnb_trucks t
        where t.id = r.truck_id
          and t.owner_id = v_actor
     );
  if not found then
    raise exception using errcode = '42501', message = 'only the reviewed truck owner may reply';
  end if;
end;
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_request_application_service_context(p_request uuid) RETURNS TABLE(application_id uuid, application_status public.airfnb_application_status, proposed_price numeric, cover_message text, deal_type public.airfnb_deal_type, proposed_fixed_to_organizer numeric, proposed_revenue_share_pct numeric, created_at timestamp with time zone, truck_id uuid, truck_name text, truck_slug text, truck_base_city text, truck_rating_avg numeric, truck_rating_count integer)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if auth.uid() is null
     or coalesce(pg_catalog.current_setting('request.jwt.claim.role', true), '') = 'service_role' then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;

  return query
  select application.id,
         application.status,
         application.proposed_price,
         application.cover_message,
         application.deal_type,
         application.proposed_fixed_to_organizer,
         application.proposed_revenue_share_pct,
         application.created_at,
         truck.id,
         truck.name,
         truck.slug,
         truck.base_city,
         truck.rating_avg,
         truck.rating_count
    from public.airfnb_event_requests as request
    join public.airfnb_applications as application
      on application.request_id = request.id
    join public.airfnb_trucks as truck on truck.id = application.truck_id
   where request.id = p_request
     and (
       request.organizer_id = auth.uid()
       or public.airfnb_is_admin()
     )
   order by application.created_at desc, application.id;
end
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_self_delete() RETURNS void
    LANGUAGE plpgsql VOLATILE SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_self_delete_storage_prefixes() RETURNS uuid[]
    LANGUAGE plpgsql VOLATILE SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_set_recommended_slots() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
begin
  if new.recommended_slots is null and new.kind is not null and new.expected_pax is not null then
    new.recommended_slots := public.airfnb_recommend_slots(new.kind, new.expected_pax);
  end if;
  if new.slots_needed is null then
    new.slots_needed := coalesce(new.recommended_slots, 1);
  end if;
  return new;
end $$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_setting_int(p_key text, p_fallback integer) RETURNS integer
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_raw text;
  v_parsed int;
begin
  select value into v_raw
    from public.airfnb_platform_settings
   where key = p_key;
  if v_raw is null or btrim(v_raw) = '' then
    return p_fallback;
  end if;
  begin
    v_parsed := btrim(v_raw)::int;
  exception when others then
    return p_fallback;
  end;
  return v_parsed;
end $$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_shortlist_application(p_application uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
declare
  v_application public.airfnb_applications%rowtype;
  v_request public.airfnb_event_requests%rowtype;
  v_actor uuid := auth.uid();
  v_signed_service_role boolean := coalesce(
    current_setting('request.jwt.claim.role', true), ''
  ) = 'service_role';
begin
  select * into v_application
    from public.airfnb_applications
   where id = p_application
   for update;
  if not found then
    raise exception using errcode = '22023', message = 'application not found';
  end if;

  select * into v_request
    from public.airfnb_event_requests
   where id = v_application.request_id
   for update;
  if not found then
    raise exception using errcode = '55000', message = 'request not found';
  end if;

  if not v_signed_service_role and (
    v_actor is null or (
      v_actor is distinct from v_request.organizer_id
      and not public.airfnb_is_admin()
    )
  ) then
    raise exception using errcode = '42501', message = 'not authorized';
  end if;
  if v_request.status is null or v_request.status not in ('open', 'reviewing') then
    raise exception using errcode = '55000',
      message = 'request is not reviewing applications';
  end if;
  if v_application.status is null or v_application.status <> 'submitted' then
    raise exception using errcode = '55000',
      message = 'application is not eligible for shortlist';
  end if;

  update public.airfnb_applications
     set status = 'shortlisted', shortlisted_at = pg_catalog.statement_timestamp()
   where id = v_application.id;

  insert into public.airfnb_notifications(user_id, kind, payload)
  select truck.owner_id,
         'application.shortlisted',
         pg_catalog.jsonb_build_object(
           'application_id', v_application.id,
           'request_id', v_request.id,
           'request_title', v_request.title
         )
    from public.airfnb_trucks as truck
   where truck.id = v_application.truck_id;
end
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_supplier_export_data() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_payload jsonb;
begin
  if auth.uid() is null
     or coalesce(pg_catalog.current_setting('request.jwt.claim.role', true), '') = 'service_role' then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;

  select pg_catalog.jsonb_build_object(
           'trucks_as_owner', coalesce((
             select pg_catalog.jsonb_agg(
                      pg_catalog.jsonb_build_object(
                        'id', service.id,
                        'slug', service.slug,
                        'name', service.name,
                        'tagline', service.tagline,
                        'description', service.description,
                        'base_city', service.base_city,
                        'service_radius_km', service.service_radius_km,
                        'capacity', service.capacity,
                        'min_event_pax', service.min_event_pax,
                        'max_event_pax', service.max_event_pax,
                        'base_price', service.base_price,
                        'price_per_pax', service.price_per_pax,
                        'setup_minutes', service.setup_minutes,
                        'teardown_minutes', service.teardown_minutes,
                        'power_required_kw', service.power_required_kw,
                        'needs_water', service.needs_water,
                        'dimensions_m', service.dimensions_m,
                        'sanitation_required', service.sanitation_required,
                        'catering_type', service.catering_type,
                        'serves', service.serves,
                        'cuisine_types', service.cuisine_types,
                        'dietary_options', service.dietary_options,
                        'compatible_event_kinds', service.compatible_event_kinds,
                        'service_type', service.service_type,
                        'status', service.status,
                        'rating_avg', service.rating_avg,
                        'rating_count', service.rating_count,
                        'featured', service.featured,
                        'homologation_expires_at', service.homologation_expires_at,
                        'insurance_expires_at', service.insurance_expires_at,
                        'lead_response_rate', service.lead_response_rate,
                        'last_active_at', service.last_active_at,
                        'subscription_tier', service.subscription_tier,
                        'created_at', service.created_at,
                        'updated_at', service.updated_at
                      ) order by service.created_at, service.id
                    )
               from (
                 select service_row.id, service_row.slug, service_row.name,
                        service_row.tagline, service_row.description,
                        service_row.base_city, service_row.service_radius_km,
                        service_row.capacity, service_row.min_event_pax,
                        service_row.max_event_pax, service_row.base_price,
                        service_row.price_per_pax, service_row.setup_minutes,
                        service_row.power_required_kw, service_row.needs_water,
                        service_row.dimensions_m, service_row.status,
                        service_row.rating_avg, service_row.rating_count,
                        service_row.featured,
                        service_row.homologation_expires_at,
                        service_row.insurance_expires_at,
                        service_row.created_at, service_row.updated_at,
                        service_row.lead_response_rate,
                        service_row.last_active_at,
                        service_row.subscription_tier,
                        service_row.cuisine_types,
                        service_row.dietary_options,
                        service_row.teardown_minutes,
                        service_row.sanitation_required,
                        service_row.catering_type, service_row.serves,
                        service_row.compatible_event_kinds,
                        service_row.service_type
                   from public.airfnb_supplier_services(null) as service_row
                  limit 10000
               ) as service
           ), '[]'::jsonb),
           'applications_as_owner', coalesce((
             select pg_catalog.jsonb_agg(
                      pg_catalog.jsonb_build_object(
                        'id', application.id,
                        'request_id', application.request_id,
                        'truck_id', application.truck_id,
                        'proposed_price', application.proposed_price,
                        'cover_message', application.cover_message,
                        'menu_pitch', application.menu_pitch,
                        'estimated_servings', application.estimated_servings,
                        'available_confirmed', application.available_confirmed,
                        'status', application.status,
                        'deal_type', application.deal_type,
                        'proposed_fixed_to_organizer', application.proposed_fixed_to_organizer,
                        'proposed_revenue_share_pct', application.proposed_revenue_share_pct,
                        'shortlisted_at', application.shortlisted_at,
                        'decided_at', application.decided_at,
                        'withdrawn_at', application.withdrawn_at,
                        'created_at', application.created_at,
                        'updated_at', application.updated_at
                      ) order by application.created_at, application.id
                    )
               from (
                 select app.id, app.request_id, app.truck_id,
                        app.proposed_price, app.cover_message, app.menu_pitch,
                        app.estimated_servings, app.available_confirmed,
                        app.status, app.deal_type,
                        app.proposed_fixed_to_organizer,
                        app.proposed_revenue_share_pct,
                        app.shortlisted_at, app.decided_at, app.withdrawn_at,
                        app.created_at, app.updated_at
                   from public.airfnb_applications as app
                   join public.airfnb_trucks as truck on truck.id = app.truck_id
                  where truck.owner_id = auth.uid()
                  order by app.created_at, app.id
                  limit 10000
               ) as application
           ), '[]'::jsonb),
           'reviews_left_for_organizers', coalesce((
             select pg_catalog.jsonb_agg(
                      pg_catalog.jsonb_build_object(
                        'id', review.id,
                        'booking_id', review.booking_id,
                        'truck_id', review.truck_id,
                        'organizer_id', review.organizer_id,
                        'rating_reliability', review.rating_reliability,
                        'rating_communication', review.rating_communication,
                        'rating_payment', review.rating_payment,
                        'rating_overall', review.rating_overall,
                        'body', review.body,
                        'created_at', review.created_at
                      ) order by review.created_at, review.id
                    )
               from (
                 select organizer_review.id, organizer_review.booking_id,
                        organizer_review.truck_id, organizer_review.organizer_id,
                        organizer_review.rating_reliability,
                        organizer_review.rating_communication,
                        organizer_review.rating_payment,
                        organizer_review.rating_overall,
                        organizer_review.body, organizer_review.created_at
                   from public.airfnb_organizer_reviews as organizer_review
                   join public.airfnb_trucks as truck
                     on truck.id = organizer_review.truck_id
                  where truck.owner_id = auth.uid()
                  order by organizer_review.created_at, organizer_review.id
                  limit 10000
               ) as review
           ), '[]'::jsonb),
           'lock_fees', coalesce((
             select pg_catalog.jsonb_agg(
                      pg_catalog.jsonb_build_object(
                        'id', lock_fee.id,
                        'application_id', lock_fee.application_id,
                        'amount', lock_fee.amount,
                        'platform_fee', lock_fee.platform_fee,
                        'organizer_share', lock_fee.organizer_share,
                        'currency', lock_fee.currency,
                        'due_until', lock_fee.due_until,
                        'status', lock_fee.status,
                        'paid_at', lock_fee.paid_at,
                        'provider_ref', lock_fee.provider_ref,
                        'refunded_at', lock_fee.refunded_at,
                        'created_at', lock_fee.created_at
                      ) order by lock_fee.created_at, lock_fee.id
                    )
               from (
                 select fee.id, fee.application_id, fee.amount,
                        fee.platform_fee, fee.organizer_share, fee.currency,
                        fee.due_until, fee.status, fee.paid_at,
                        fee.provider_ref, fee.refunded_at, fee.created_at
                   from public.airfnb_lock_fees as fee
                   join public.airfnb_applications as application
                     on application.id = fee.application_id
                   join public.airfnb_trucks as truck
                     on truck.id = application.truck_id
                  where truck.owner_id = auth.uid()
                  order by fee.created_at, fee.id
                  limit 10000
               ) as lock_fee
           ), '[]'::jsonb)
         )
    into v_payload;

  return v_payload;
end
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_supplier_lock_fee(p_application uuid) RETURNS TABLE(application_id uuid, application_status public.airfnb_application_status, proposed_price numeric, deal_type public.airfnb_deal_type, truck_id uuid, truck_name text, request_id uuid, request_title text, start_at timestamp with time zone, city text, lock_fee_id uuid, amount numeric, platform_fee numeric, organizer_share numeric, currency character, due_until timestamp with time zone, lock_fee_status public.airfnb_lock_fee_status)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select application.id,
         application.status,
         application.proposed_price,
         application.deal_type,
         truck.id,
         truck.name,
         request_row.id,
         request_row.title,
         request_row.start_at,
         request_row.city,
         lock_fee.id,
         lock_fee.amount,
         lock_fee.platform_fee,
         lock_fee.organizer_share,
         lock_fee.currency,
         lock_fee.due_until,
         lock_fee.status
    from public.airfnb_applications as application
    join public.airfnb_trucks as truck on truck.id = application.truck_id
    join public.airfnb_event_requests as request_row
      on request_row.id = application.request_id
    join public.airfnb_lock_fees as lock_fee
      on lock_fee.application_id = application.id
   where auth.uid() is not null
     and coalesce(
       pg_catalog.current_setting('request.jwt.claim.role', true), ''
     ) <> 'service_role'
     and truck.owner_id = auth.uid()
     and application.id = p_application
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_supplier_services(p_truck uuid DEFAULT NULL::uuid) RETURNS TABLE(id uuid, slug text, name text, tagline text, description text, base_city text, service_radius_km integer, capacity integer, min_event_pax integer, max_event_pax integer, base_price numeric, price_per_pax numeric, setup_minutes integer, power_required_kw numeric, needs_water boolean, dimensions_m numeric[], status public.airfnb_truck_status, rating_avg numeric, rating_count integer, featured boolean, homologation_expires_at date, insurance_expires_at date, created_at timestamp with time zone, updated_at timestamp with time zone, lead_response_rate numeric, last_active_at timestamp with time zone, subscription_tier text, cuisine_types text[], dietary_options public.airfnb_dietary_tag[], teardown_minutes integer, sanitation_required text, catering_type text, serves text, compatible_event_kinds public.airfnb_event_kind[], service_type public.airfnb_service_type)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select truck.id,
         truck.slug,
         truck.name,
         truck.tagline,
         truck.description,
         truck.base_city,
         truck.service_radius_km,
         truck.capacity,
         truck.min_event_pax,
         truck.max_event_pax,
         truck.base_price,
         truck.price_per_pax,
         truck.setup_minutes,
         truck.power_required_kw,
         truck.needs_water,
         truck.dimensions_m,
         truck.status,
         truck.rating_avg,
         truck.rating_count,
         truck.featured,
         truck.homologation_expires_at,
         truck.insurance_expires_at,
         truck.created_at,
         truck.updated_at,
         truck.lead_response_rate,
         truck.last_active_at,
         truck.subscription_tier,
         truck.cuisine_types,
         truck.dietary_options,
         truck.teardown_minutes,
         truck.sanitation_required,
         truck.catering_type,
         truck.serves,
         truck.compatible_event_kinds,
         truck.service_type
    from public.airfnb_trucks as truck
   where auth.uid() is not null
     and coalesce(pg_catalog.current_setting('request.jwt.claim.role', true), '') <> 'service_role'
     and truck.owner_id = auth.uid()
     and (p_truck is null or truck.id = p_truck)
   order by truck.created_at, truck.id
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_touch_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
begin new.updated_at = now(); return new; end $$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_truck_is_available(p_truck uuid, p_from date, p_to date) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  select not exists (
    select 1 from public.airfnb_truck_availability a
    where a.truck_id = p_truck
      and a.date between p_from and p_to
      and a.status in ('booked','blocked')
  );
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_user_organizes_request(p_request uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (
    select 1
      from public.airfnb_event_requests r
     where r.id           = p_request
       and r.organizer_id = auth.uid()
  )
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE FUNCTION public.airfnb_user_owns_invited_truck(p_request uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (
    select 1
      from public.airfnb_request_invitations ri
      join public.airfnb_trucks t on t.id = ri.truck_id
     where ri.request_id = p_request
       and t.owner_id    = auth.uid()
  )
$$;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_addresses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_id uuid,
    label text,
    line1 text NOT NULL,
    line2 text,
    postal_code text,
    city text,
    region text,
    country text DEFAULT 'PT'::text,
    geom text,
    created_at timestamp with time zone DEFAULT now()
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_applications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    request_id uuid NOT NULL,
    truck_id uuid NOT NULL,
    proposed_price numeric(10,2) NOT NULL,
    cover_message text,
    menu_pitch jsonb,
    estimated_servings integer,
    available_confirmed boolean DEFAULT true,
    status public.airfnb_application_status DEFAULT 'submitted'::public.airfnb_application_status,
    shortlisted_at timestamp with time zone,
    decided_at timestamp with time zone,
    withdrawn_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    deal_type public.airfnb_deal_type DEFAULT 'fixed'::public.airfnb_deal_type,
    proposed_fixed_to_organizer numeric(10,2) DEFAULT 0,
    proposed_revenue_share_pct numeric(5,2) DEFAULT 0,
    CONSTRAINT airfnb_app_deal_consistency CHECK (
CASE deal_type
    WHEN 'fixed'::public.airfnb_deal_type THEN (proposed_revenue_share_pct = (0)::numeric)
    WHEN 'percent'::public.airfnb_deal_type THEN (proposed_fixed_to_organizer = (0)::numeric)
    WHEN 'mixed'::public.airfnb_deal_type THEN ((proposed_fixed_to_organizer > (0)::numeric) AND (proposed_revenue_share_pct > (0)::numeric))
    ELSE NULL::boolean
END),
    CONSTRAINT airfnb_applications_proposed_fixed_to_organizer_check CHECK ((proposed_fixed_to_organizer >= (0)::numeric)),
    CONSTRAINT airfnb_applications_proposed_price_check CHECK ((proposed_price >= (0)::numeric)),
    CONSTRAINT airfnb_applications_proposed_revenue_share_pct_check CHECK (((proposed_revenue_share_pct >= (0)::numeric) AND (proposed_revenue_share_pct <= (100)::numeric)))
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_audit_log (
    id bigint NOT NULL,
    actor_id uuid,
    action text,
    entity text,
    entity_id uuid,
    diff jsonb,
    ip inet,
    created_at timestamp with time zone DEFAULT now()
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE SEQUENCE public.airfnb_audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER SEQUENCE public.airfnb_audit_log_id_seq OWNED BY public.airfnb_audit_log.id;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_blog_authors (
    id uuid NOT NULL,
    bio text,
    twitter text,
    instagram text
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_blog_categories (
    id integer NOT NULL,
    slug text NOT NULL,
    name text NOT NULL
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE SEQUENCE public.airfnb_blog_categories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER SEQUENCE public.airfnb_blog_categories_id_seq OWNED BY public.airfnb_blog_categories.id;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_blog_posts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    slug text NOT NULL,
    author_id uuid,
    category_id integer,
    title text NOT NULL,
    excerpt text,
    cover_url text,
    body_md text,
    read_minutes integer,
    status public.airfnb_post_status DEFAULT 'draft'::public.airfnb_post_status,
    published_at timestamp with time zone,
    seo_title text,
    seo_description text,
    created_at timestamp with time zone DEFAULT now()
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_booking_addons (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    booking_id uuid,
    provider_id uuid,
    description text,
    qty integer DEFAULT 1,
    unit_price numeric(10,2)
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_booking_trucks (
    booking_id uuid NOT NULL,
    truck_id uuid NOT NULL,
    agreed_price numeric(10,2),
    notes text
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_bookings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id uuid,
    organizer_id uuid,
    status public.airfnb_booking_status DEFAULT 'inquiry'::public.airfnb_booking_status,
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    pax_count integer,
    total_amount numeric(10,2),
    currency character(3) DEFAULT 'EUR'::bpchar,
    notes text,
    cancellation_reason text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    application_id uuid,
    ics_token text
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_categories (
    id integer NOT NULL,
    slug text NOT NULL,
    name_pt text NOT NULL,
    name_en text,
    icon text
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE SEQUENCE public.airfnb_categories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER SEQUENCE public.airfnb_categories_id_seq OWNED BY public.airfnb_categories.id;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_contact_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    email text,
    phone text,
    message text,
    source_page text,
    handled_by uuid,
    created_at timestamp with time zone DEFAULT now()
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_conversation_participants (
    conversation_id uuid NOT NULL,
    user_id uuid NOT NULL,
    last_read_at timestamp with time zone
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_conversations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    booking_id uuid,
    created_at timestamp with time zone DEFAULT now(),
    application_id uuid
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organizer_id uuid NOT NULL,
    title text,
    kind public.airfnb_event_kind,
    start_at timestamp with time zone,
    end_at timestamp with time zone,
    expected_pax integer,
    city text,
    address_id uuid,
    budget_min numeric(10,2),
    budget_max numeric(10,2),
    notes text,
    status text DEFAULT 'draft'::text,
    created_at timestamp with time zone DEFAULT now()
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_faqs (
    id integer NOT NULL,
    question text NOT NULL,
    answer text NOT NULL,
    topic text,
    sort_order integer DEFAULT 0
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE SEQUENCE public.airfnb_faqs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER SEQUENCE public.airfnb_faqs_id_seq OWNED BY public.airfnb_faqs.id;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_favorites (
    user_id uuid NOT NULL,
    truck_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_invoices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    booking_id uuid,
    number text,
    issued_at date,
    pdf_url text,
    vat_amount numeric(10,2),
    total_amount numeric(10,2)
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_lock_fees (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    application_id uuid NOT NULL,
    amount numeric(10,2) NOT NULL,
    currency character(3) DEFAULT 'EUR'::bpchar NOT NULL,
    due_until timestamp with time zone NOT NULL,
    status public.airfnb_lock_fee_status DEFAULT 'pending'::public.airfnb_lock_fee_status,
    paid_at timestamp with time zone,
    provider_ref text,
    refunded_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    platform_fee numeric(10,2) DEFAULT 25,
    organizer_share numeric(10,2) DEFAULT 25,
    provider_event_log jsonb DEFAULT '[]'::jsonb NOT NULL,
    CONSTRAINT airfnb_lock_fees_amount_check CHECK ((amount >= (0)::numeric)),
    CONSTRAINT airfnb_lock_fees_currency_eur CHECK ((upper(btrim((currency)::text)) = 'EUR'::text)),
    CONSTRAINT airfnb_lock_fees_organizer_share_check CHECK ((organizer_share >= (0)::numeric)),
    CONSTRAINT airfnb_lock_fees_platform_fee_check CHECK ((platform_fee >= (0)::numeric))
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_menu_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    truck_id uuid,
    name text NOT NULL,
    description text,
    price numeric(8,2),
    image_url text,
    category text,
    tags public.airfnb_dietary_tag[] DEFAULT '{}'::public.airfnb_dietary_tag[],
    sort_order integer DEFAULT 0
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    conversation_id uuid,
    sender_id uuid,
    body text,
    attachments jsonb,
    created_at timestamp with time zone DEFAULT now()
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_newsletter_subs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email text NOT NULL,
    source text,
    confirmed_at timestamp with time zone,
    unsubscribed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_newsletter_subscribers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email text NOT NULL,
    confirmed boolean DEFAULT false,
    confirm_token text,
    created_at timestamp with time zone DEFAULT now()
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    kind text,
    payload jsonb,
    read_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_organizer_reviews (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    booking_id uuid NOT NULL,
    truck_id uuid NOT NULL,
    organizer_id uuid NOT NULL,
    rating_reliability smallint,
    rating_communication smallint,
    rating_payment smallint,
    rating_overall numeric(2,1),
    body text,
    reply_body text,
    reply_at timestamp with time zone,
    is_verified boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT airfnb_organizer_reviews_rating_communication_check CHECK (((rating_communication >= 1) AND (rating_communication <= 5))),
    CONSTRAINT airfnb_organizer_reviews_rating_payment_check CHECK (((rating_payment >= 1) AND (rating_payment <= 5))),
    CONSTRAINT airfnb_organizer_reviews_rating_reliability_check CHECK (((rating_reliability >= 1) AND (rating_reliability <= 5)))
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_partner_leads (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    kind public.airfnb_partner_lead_kind NOT NULL,
    name text NOT NULL,
    email text NOT NULL,
    phone text,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    handled_at timestamp with time zone,
    handled_by uuid,
    notes text
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_payments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    booking_id uuid,
    amount numeric(10,2),
    currency character(3) DEFAULT 'EUR'::bpchar,
    method public.airfnb_payment_method,
    status public.airfnb_payment_status DEFAULT 'pending'::public.airfnb_payment_status,
    provider_ref text,
    paid_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    direction public.airfnb_payment_direction,
    kind public.airfnb_payment_kind DEFAULT 'event_payment'::public.airfnb_payment_kind,
    application_id uuid,
    lock_fee_id uuid,
    refunded_amount numeric(10,2) DEFAULT 0 NOT NULL,
    last_provider_event_at timestamp with time zone,
    CONSTRAINT airfnb_payments_currency_eur CHECK (((currency IS NULL) OR (upper(btrim((currency)::text)) = 'EUR'::text))),
    CONSTRAINT airfnb_payments_refunded_amount_bounds CHECK (((refunded_amount >= (0)::numeric) AND ((amount IS NULL) OR (refunded_amount <= amount))))
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_platform_settings (
    key text NOT NULL,
    value text,
    "group" text DEFAULT 'general'::text NOT NULL,
    description text,
    secret boolean DEFAULT false NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_proposals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    booking_id uuid,
    prepared_by uuid,
    version integer DEFAULT 1,
    body jsonb,
    total_amount numeric(10,2),
    valid_until date,
    pdf_url text,
    signed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_rate_limits (
    action text NOT NULL,
    bucket text NOT NULL,
    count integer DEFAULT 0 NOT NULL,
    window_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT airfnb_rate_limits_action_format CHECK ((action ~ '^[a-z][a-z0-9_]{0,63}$'::text)),
    CONSTRAINT airfnb_rate_limits_bucket_format CHECK ((bucket ~ '^[A-Za-z0-9][A-Za-z0-9:_-]{0,159}$'::text)),
    CONSTRAINT airfnb_rate_limits_count_range CHECK (((count >= 0) AND (count <= 2147483647)))
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_request_invitations (
    request_id uuid NOT NULL,
    truck_id uuid NOT NULL,
    invited_by uuid,
    invited_at timestamp with time zone DEFAULT now(),
    responded boolean DEFAULT false
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_reviews (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    booking_id uuid,
    truck_id uuid,
    organizer_id uuid,
    rating_food smallint,
    rating_service smallint,
    rating_value smallint,
    rating_overall numeric(2,1),
    body text,
    reply_body text,
    reply_at timestamp with time zone,
    is_verified boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT airfnb_reviews_rating_food_check CHECK (((rating_food >= 1) AND (rating_food <= 5))),
    CONSTRAINT airfnb_reviews_rating_service_check CHECK (((rating_service >= 1) AND (rating_service <= 5))),
    CONSTRAINT airfnb_reviews_rating_value_check CHECK (((rating_value >= 1) AND (rating_value <= 5)))
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_service_providers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    kind public.airfnb_service_kind,
    name text,
    description text,
    city text,
    price_from numeric(10,2),
    image_url text,
    contact_email text,
    contact_phone text,
    created_at timestamp with time zone DEFAULT now()
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_stripe_events (
    event_id text NOT NULL,
    event_type text NOT NULL,
    event_created_at timestamp with time zone NOT NULL,
    provider_ref text NOT NULL,
    application_id uuid NOT NULL,
    lock_fee_id uuid NOT NULL,
    booking_id uuid NOT NULL,
    amount_minor bigint NOT NULL,
    currency character(3) NOT NULL,
    payment_status text NOT NULL,
    refunded_amount_minor bigint DEFAULT 0 NOT NULL,
    processing_result text,
    processed_at timestamp with time zone,
    received_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT airfnb_stripe_events_amount_minor_check CHECK ((amount_minor > 0)),
    CONSTRAINT airfnb_stripe_events_check CHECK (((refunded_amount_minor >= 0) AND (refunded_amount_minor <= amount_minor))),
    CONSTRAINT airfnb_stripe_events_currency_eur CHECK ((btrim((currency)::text) = 'EUR'::text)),
    CONSTRAINT airfnb_stripe_events_processed_check CHECK ((((processing_result IS NULL) AND (processed_at IS NULL)) OR ((processing_result IS NOT NULL) AND (processed_at IS NOT NULL)))),
    CONSTRAINT airfnb_stripe_events_type_check CHECK ((event_type = ANY (ARRAY['checkout.session.completed'::text, 'charge.refunded'::text])))
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_stripe_events FORCE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_truck_alert_prefs (
    truck_id uuid NOT NULL,
    cities text[] DEFAULT '{}'::text[],
    category_ids integer[] DEFAULT '{}'::integer[],
    min_budget numeric(10,2),
    max_radius_km integer,
    channels jsonb DEFAULT '{"push": false, "email": true}'::jsonb,
    updated_at timestamp with time zone DEFAULT now()
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_truck_availability (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    truck_id uuid,
    date date NOT NULL,
    status text,
    booking_id uuid,
    CONSTRAINT airfnb_truck_availability_status_check CHECK ((status = ANY (ARRAY['blocked'::text, 'tentative'::text, 'booked'::text])))
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_truck_categories (
    truck_id uuid NOT NULL,
    category_id integer NOT NULL
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_truck_documents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    truck_id uuid,
    kind public.airfnb_truck_document_kind DEFAULT 'outros'::public.airfnb_truck_document_kind,
    url text,
    issued_at date,
    expires_at date
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_truck_images (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    truck_id uuid,
    url text NOT NULL,
    alt text,
    sort_order integer DEFAULT 0,
    is_cover boolean DEFAULT false,
    kind public.airfnb_truck_image_kind DEFAULT 'other'::public.airfnb_truck_image_kind NOT NULL
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TABLE public.airfnb_trucks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_id uuid,
    slug text NOT NULL,
    name text NOT NULL,
    tagline text,
    description text,
    base_city text,
    service_radius_km integer DEFAULT 50,
    capacity integer,
    min_event_pax integer DEFAULT 30,
    max_event_pax integer DEFAULT 500,
    base_price numeric(10,2),
    price_per_pax numeric(10,2),
    setup_minutes integer DEFAULT 60,
    power_required_kw numeric(4,1),
    needs_water boolean DEFAULT false,
    dimensions_m numeric(4,1)[],
    status public.airfnb_truck_status DEFAULT 'draft'::public.airfnb_truck_status,
    rating_avg numeric(2,1) DEFAULT 0,
    rating_count integer DEFAULT 0,
    featured boolean DEFAULT false,
    homologation_expires_at date,
    insurance_expires_at date,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    lead_response_rate numeric(3,2),
    last_active_at timestamp with time zone,
    subscription_tier text DEFAULT 'basic'::text,
    cuisine_types text[] DEFAULT '{}'::text[],
    dietary_options public.airfnb_dietary_tag[] DEFAULT '{}'::public.airfnb_dietary_tag[],
    teardown_minutes integer DEFAULT 60,
    sanitation_required text DEFAULT 'none'::text,
    catering_type text DEFAULT 'fixed'::text,
    serves text DEFAULT 'food_and_drinks'::text,
    compatible_event_kinds public.airfnb_event_kind[] DEFAULT '{}'::public.airfnb_event_kind[] NOT NULL,
    service_type public.airfnb_service_type DEFAULT 'food_truck'::public.airfnb_service_type NOT NULL,
    CONSTRAINT airfnb_trucks_catering_type_chk CHECK ((catering_type = ANY (ARRAY['fixed'::text, 'percent'::text, 'mixed'::text]))),
    CONSTRAINT airfnb_trucks_sanitation_required_chk CHECK ((sanitation_required = ANY (ARRAY['none'::text, 'wc_proximo'::text, 'wc_dedicado'::text]))),
    CONSTRAINT airfnb_trucks_serves_chk CHECK ((serves = ANY (ARRAY['food'::text, 'drinks'::text, 'food_and_drinks'::text])))
);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE VIEW public.airfnb_v_booking_full WITH (security_invoker='true') AS
 SELECT b.id,
    b.status,
    b.starts_at,
    b.ends_at,
    b.pax_count,
    b.total_amount,
    b.currency,
    b.organizer_id,
    e.id AS event_id,
    e.title AS event_title,
    e.kind AS event_kind,
    ARRAY( SELECT json_build_object('id', t.id, 'name', t.name, 'slug', t.slug, 'price', bt.agreed_price) AS json_build_object
           FROM (public.airfnb_booking_trucks bt
             JOIN public.airfnb_trucks t ON ((t.id = bt.truck_id)))
          WHERE (bt.booking_id = b.id)) AS trucks
   FROM (public.airfnb_bookings b
     LEFT JOIN public.airfnb_events e ON ((e.id = b.event_id)));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE VIEW public.airfnb_v_truck_card WITH (security_invoker='true') AS
 SELECT id,
    slug,
    name,
    tagline,
    base_city,
    capacity,
    base_price,
    price_per_pax,
    min_event_pax,
    max_event_pax,
    service_radius_km,
    cuisine_types,
    dietary_options,
    catering_type,
    serves,
    setup_minutes,
    teardown_minutes,
    power_required_kw,
    sanitation_required,
    compatible_event_kinds,
    rating_avg,
    rating_count,
    featured,
    status,
    ( SELECT image.url
           FROM public.airfnb_truck_images image
          WHERE (image.truck_id = truck.id)
          ORDER BY
                CASE image.kind
                    WHEN 'truck'::public.airfnb_truck_image_kind THEN 1
                    WHEN 'food'::public.airfnb_truck_image_kind THEN 2
                    WHEN 'venue'::public.airfnb_truck_image_kind THEN 3
                    WHEN 'team'::public.airfnb_truck_image_kind THEN 4
                    ELSE 5
                END,
                CASE
                    WHEN image.is_cover THEN 0
                    ELSE 1
                END, image.sort_order, image.url
         LIMIT 1) AS cover_url,
    ( SELECT array_agg(ordered_image.url ORDER BY ordered_image.kind_rank, ordered_image.is_cover_rank, ordered_image.sort_order, ordered_image.url) AS array_agg
           FROM ( SELECT image.url,
                        CASE image.kind
                            WHEN 'truck'::public.airfnb_truck_image_kind THEN 1
                            WHEN 'food'::public.airfnb_truck_image_kind THEN 2
                            WHEN 'venue'::public.airfnb_truck_image_kind THEN 3
                            WHEN 'team'::public.airfnb_truck_image_kind THEN 4
                            ELSE 5
                        END AS kind_rank,
                        CASE
                            WHEN image.is_cover THEN 0
                            ELSE 1
                        END AS is_cover_rank,
                    image.sort_order
                   FROM public.airfnb_truck_images image
                  WHERE (image.truck_id = truck.id)
                  ORDER BY
                        CASE image.kind
                            WHEN 'truck'::public.airfnb_truck_image_kind THEN 1
                            WHEN 'food'::public.airfnb_truck_image_kind THEN 2
                            WHEN 'venue'::public.airfnb_truck_image_kind THEN 3
                            WHEN 'team'::public.airfnb_truck_image_kind THEN 4
                            ELSE 5
                        END,
                        CASE
                            WHEN image.is_cover THEN 0
                            ELSE 1
                        END, image.sort_order, image.url
                 LIMIT 6) ordered_image) AS gallery_urls,
    ARRAY( SELECT category.slug
           FROM (public.airfnb_truck_categories truck_category
             JOIN public.airfnb_categories category ON ((category.id = truck_category.category_id)))
          WHERE (truck_category.truck_id = truck.id)
          ORDER BY category.slug) AS category_slugs,
    service_type
   FROM public.airfnb_trucks truck
  WHERE (status = 'active'::public.airfnb_truck_status);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_audit_log ALTER COLUMN id SET DEFAULT nextval('public.airfnb_audit_log_id_seq'::regclass);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_blog_categories ALTER COLUMN id SET DEFAULT nextval('public.airfnb_blog_categories_id_seq'::regclass);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_categories ALTER COLUMN id SET DEFAULT nextval('public.airfnb_categories_id_seq'::regclass);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_faqs ALTER COLUMN id SET DEFAULT nextval('public.airfnb_faqs_id_seq'::regclass);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_addresses
    ADD CONSTRAINT airfnb_addresses_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_applications
    ADD CONSTRAINT airfnb_applications_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_applications
    ADD CONSTRAINT airfnb_applications_request_id_truck_id_key UNIQUE (request_id, truck_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_audit_log
    ADD CONSTRAINT airfnb_audit_log_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_blog_authors
    ADD CONSTRAINT airfnb_blog_authors_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_blog_categories
    ADD CONSTRAINT airfnb_blog_categories_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_blog_categories
    ADD CONSTRAINT airfnb_blog_categories_slug_key UNIQUE (slug);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_blog_posts
    ADD CONSTRAINT airfnb_blog_posts_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_blog_posts
    ADD CONSTRAINT airfnb_blog_posts_slug_key UNIQUE (slug);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_booking_addons
    ADD CONSTRAINT airfnb_booking_addons_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_booking_trucks
    ADD CONSTRAINT airfnb_booking_trucks_pkey PRIMARY KEY (booking_id, truck_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_bookings
    ADD CONSTRAINT airfnb_bookings_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_categories
    ADD CONSTRAINT airfnb_categories_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_categories
    ADD CONSTRAINT airfnb_categories_slug_key UNIQUE (slug);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_contact_requests
    ADD CONSTRAINT airfnb_contact_requests_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_conversation_participants
    ADD CONSTRAINT airfnb_conversation_participants_pkey PRIMARY KEY (conversation_id, user_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_conversations
    ADD CONSTRAINT airfnb_conversations_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_event_requests
    ADD CONSTRAINT airfnb_event_requests_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_events
    ADD CONSTRAINT airfnb_events_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_faqs
    ADD CONSTRAINT airfnb_faqs_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_favorites
    ADD CONSTRAINT airfnb_favorites_pkey PRIMARY KEY (user_id, truck_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_invoices
    ADD CONSTRAINT airfnb_invoices_number_key UNIQUE (number);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_invoices
    ADD CONSTRAINT airfnb_invoices_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_lock_fees
    ADD CONSTRAINT airfnb_lock_fees_application_id_key UNIQUE (application_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_lock_fees
    ADD CONSTRAINT airfnb_lock_fees_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_lock_fees
    ADD CONSTRAINT airfnb_lock_fees_provider_ref_key UNIQUE (provider_ref);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_menu_items
    ADD CONSTRAINT airfnb_menu_items_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_messages
    ADD CONSTRAINT airfnb_messages_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_newsletter_subs
    ADD CONSTRAINT airfnb_newsletter_subs_email_key UNIQUE (email);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_newsletter_subs
    ADD CONSTRAINT airfnb_newsletter_subs_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_newsletter_subscribers
    ADD CONSTRAINT airfnb_newsletter_subscribers_email_key UNIQUE (email);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_newsletter_subscribers
    ADD CONSTRAINT airfnb_newsletter_subscribers_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_notifications
    ADD CONSTRAINT airfnb_notifications_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_organizer_reviews
    ADD CONSTRAINT airfnb_organizer_reviews_booking_id_truck_id_key UNIQUE (booking_id, truck_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_organizer_reviews
    ADD CONSTRAINT airfnb_organizer_reviews_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_partner_leads
    ADD CONSTRAINT airfnb_partner_leads_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_payments
    ADD CONSTRAINT airfnb_payments_lock_fee_key UNIQUE (lock_fee_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_payments
    ADD CONSTRAINT airfnb_payments_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_payments
    ADD CONSTRAINT airfnb_payments_provider_ref_key UNIQUE (provider_ref);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_platform_settings
    ADD CONSTRAINT airfnb_platform_settings_pkey PRIMARY KEY (key);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_profiles
    ADD CONSTRAINT airfnb_profiles_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_membership_tombstones
    ADD CONSTRAINT airfnb_membership_tombstones_pkey PRIMARY KEY (user_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_proposals
    ADD CONSTRAINT airfnb_proposals_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_rate_limits
    ADD CONSTRAINT airfnb_rate_limits_pkey PRIMARY KEY (action, bucket);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_request_invitations
    ADD CONSTRAINT airfnb_request_invitations_pkey PRIMARY KEY (request_id, truck_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_reviews
    ADD CONSTRAINT airfnb_reviews_booking_id_truck_id_key UNIQUE (booking_id, truck_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_reviews
    ADD CONSTRAINT airfnb_reviews_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_service_providers
    ADD CONSTRAINT airfnb_service_providers_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_stripe_events
    ADD CONSTRAINT airfnb_stripe_events_pkey PRIMARY KEY (event_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_truck_alert_prefs
    ADD CONSTRAINT airfnb_truck_alert_prefs_pkey PRIMARY KEY (truck_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_truck_availability
    ADD CONSTRAINT airfnb_truck_availability_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_truck_availability
    ADD CONSTRAINT airfnb_truck_availability_truck_id_date_key UNIQUE (truck_id, date);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_truck_categories
    ADD CONSTRAINT airfnb_truck_categories_pkey PRIMARY KEY (truck_id, category_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_truck_documents
    ADD CONSTRAINT airfnb_truck_documents_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_truck_images
    ADD CONSTRAINT airfnb_truck_images_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_trucks
    ADD CONSTRAINT airfnb_trucks_pkey PRIMARY KEY (id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_trucks
    ADD CONSTRAINT airfnb_trucks_slug_key UNIQUE (slug);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_addresses_geom_idx ON public.airfnb_addresses USING btree (geom);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_addresses_owner_idx ON public.airfnb_addresses USING btree (owner_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_app_pending_idx ON public.airfnb_applications USING btree (status) WHERE (status = ANY (ARRAY['submitted'::public.airfnb_application_status, 'shortlisted'::public.airfnb_application_status]));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_app_request_idx ON public.airfnb_applications USING btree (request_id, status);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_app_truck_idx ON public.airfnb_applications USING btree (truck_id, status);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_booking_trucks_truck_idx ON public.airfnb_booking_trucks USING btree (truck_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_bookings_app_idx ON public.airfnb_bookings USING btree (application_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE UNIQUE INDEX airfnb_bookings_application_unique ON public.airfnb_bookings USING btree (application_id) WHERE (application_id IS NOT NULL);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_bookings_event_idx ON public.airfnb_bookings USING btree (event_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE UNIQUE INDEX airfnb_bookings_ics_token_uniq ON public.airfnb_bookings USING btree (ics_token) WHERE (ics_token IS NOT NULL);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_bookings_organizer_idx ON public.airfnb_bookings USING btree (organizer_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_bookings_status_idx ON public.airfnb_bookings USING btree (status);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_event_requests_open_start_idx ON public.airfnb_event_requests USING btree (start_at) WHERE (status = 'open'::public.airfnb_request_status);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_event_requests_status_start_idx ON public.airfnb_event_requests USING btree (status, start_at);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_event_requests_water_gin_idx ON public.airfnb_event_requests USING gin (water_provided);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_event_requests_wc_gin_idx ON public.airfnb_event_requests USING gin (wc_provided);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_events_organizer_idx ON public.airfnb_events USING btree (organizer_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_events_start_idx ON public.airfnb_events USING btree (start_at);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_invites_truck_idx ON public.airfnb_request_invitations USING btree (truck_id, responded);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_invoices_booking_idx ON public.airfnb_invoices USING btree (booking_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_lock_fees_status_due_idx ON public.airfnb_lock_fees USING btree (status, due_until);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_lockfee_status_idx ON public.airfnb_lock_fees USING btree (status, due_until) WHERE (status = 'pending'::public.airfnb_lock_fee_status);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_menu_items_truck_idx ON public.airfnb_menu_items USING btree (truck_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_messages_conv_idx ON public.airfnb_messages USING btree (conversation_id, created_at);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_messages_created_at_brin ON public.airfnb_messages USING brin (created_at);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_messages_sender_idx ON public.airfnb_messages USING btree (sender_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_notifications_user_unread_created_idx ON public.airfnb_notifications USING btree (user_id, created_at DESC) WHERE (read_at IS NULL);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_notifications_user_unread_idx ON public.airfnb_notifications USING btree (user_id) WHERE (read_at IS NULL);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_organizer_reviews_org_idx ON public.airfnb_organizer_reviews USING btree (organizer_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_partner_leads_kind_created_idx ON public.airfnb_partner_leads USING btree (kind, created_at DESC);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_partner_leads_unhandled_idx ON public.airfnb_partner_leads USING btree (created_at DESC) WHERE (handled_at IS NULL);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_payments_booking_idx ON public.airfnb_payments USING btree (booking_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_payments_kind_idx ON public.airfnb_payments USING btree (kind, status);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_payments_status_idx ON public.airfnb_payments USING btree (status);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_platform_settings_group_idx ON public.airfnb_platform_settings USING btree ("group", key);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_posts_published_idx ON public.airfnb_blog_posts USING btree (status, published_at DESC);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE UNIQUE INDEX airfnb_profiles_referral_code_uniq ON public.airfnb_profiles USING btree (referral_code) WHERE (referral_code IS NOT NULL);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE UNIQUE INDEX airfnb_profiles_vat_uniq ON public.airfnb_profiles USING btree (vat_number) WHERE (vat_number IS NOT NULL);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_proposals_booking_idx ON public.airfnb_proposals USING btree (booking_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_rate_limits_window_at_idx ON public.airfnb_rate_limits USING btree (window_at);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_req_categories_gin ON public.airfnb_event_requests USING gin (desired_categories);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_req_city_start_idx ON public.airfnb_event_requests USING btree (city, start_at) WHERE (status = 'open'::public.airfnb_request_status);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_req_deadline_idx ON public.airfnb_event_requests USING btree (applications_deadline) WHERE (status = 'open'::public.airfnb_request_status);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_req_dietary_gin ON public.airfnb_event_requests USING gin (dietary_requirements);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_req_organizer_idx ON public.airfnb_event_requests USING btree (organizer_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_req_status_idx ON public.airfnb_event_requests USING btree (status) WHERE (status = ANY (ARRAY['open'::public.airfnb_request_status, 'reviewing'::public.airfnb_request_status]));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_reviews_truck_idx ON public.airfnb_reviews USING btree (truck_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_stripe_events_provider_time_idx ON public.airfnb_stripe_events USING btree (provider_ref, event_created_at DESC);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_truck_avail_truck_date_idx ON public.airfnb_truck_availability USING btree (truck_id, date);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_truck_docs_expiry_idx ON public.airfnb_truck_documents USING btree (expires_at);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_truck_images_truck_idx ON public.airfnb_truck_images USING btree (truck_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_truck_images_truck_kind_idx ON public.airfnb_truck_images USING btree (truck_id, kind, sort_order);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_trucks_active_idx ON public.airfnb_trucks USING btree (status) WHERE (status = 'active'::public.airfnb_truck_status);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_trucks_active_rating_idx ON public.airfnb_trucks USING btree (rating_avg DESC, id) WHERE (status = 'active'::public.airfnb_truck_status);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_trucks_active_service_type_idx ON public.airfnb_trucks USING btree (service_type) WHERE (status = 'active'::public.airfnb_truck_status);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_trucks_base_city_trgm_idx ON public.airfnb_trucks USING gin (base_city extensions.gin_trgm_ops);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_trucks_city_idx ON public.airfnb_trucks USING btree (base_city) WHERE (status = 'active'::public.airfnb_truck_status);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_trucks_event_kinds_gin_idx ON public.airfnb_trucks USING gin (compatible_event_kinds);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_trucks_featured_idx ON public.airfnb_trucks USING btree (featured) WHERE (status = 'active'::public.airfnb_truck_status);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_trucks_owner_idx ON public.airfnb_trucks USING btree (owner_id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_trucks_owner_status_idx ON public.airfnb_trucks USING btree (owner_id, status);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE INDEX airfnb_trucks_search ON public.airfnb_trucks USING gin (to_tsvector('portuguese'::regconfig, ((COALESCE(name, ''::text) || ' '::text) || COALESCE(description, ''::text))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TRIGGER airfnb_applications_notify_received AFTER INSERT ON public.airfnb_applications FOR EACH ROW EXECUTE FUNCTION public.airfnb_notify_application_received();
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TRIGGER airfnb_applications_rate_limit_trg BEFORE INSERT ON public.airfnb_applications FOR EACH ROW EXECUTE FUNCTION public.airfnb_applications_rate_limit();
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TRIGGER airfnb_booking_ics_token_trg BEFORE INSERT ON public.airfnb_bookings FOR EACH ROW EXECUTE FUNCTION public.airfnb_assign_ics_token();
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TRIGGER airfnb_event_request_notify_admins_trg AFTER INSERT ON public.airfnb_event_requests FOR EACH ROW EXECUTE FUNCTION public.airfnb_event_request_notify_admins();
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TRIGGER airfnb_event_request_visibility_sync_trg BEFORE INSERT OR UPDATE OF discovery_mode, visibility ON public.airfnb_event_requests FOR EACH ROW EXECUTE FUNCTION public.airfnb_event_request_visibility_sync();
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TRIGGER airfnb_event_requests_rate_limit_trg BEFORE INSERT ON public.airfnb_event_requests FOR EACH ROW EXECUTE FUNCTION public.airfnb_event_requests_rate_limit();
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TRIGGER airfnb_organizer_reviews_recompute AFTER INSERT OR DELETE OR UPDATE OF organizer_id, rating_overall ON public.airfnb_organizer_reviews FOR EACH ROW EXECUTE FUNCTION public.airfnb_organizer_rating_recompute();
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TRIGGER airfnb_prepare_organizer_review BEFORE INSERT ON public.airfnb_organizer_reviews FOR EACH ROW EXECUTE FUNCTION public.airfnb_prepare_organizer_review();
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TRIGGER airfnb_prepare_truck_review BEFORE INSERT ON public.airfnb_reviews FOR EACH ROW EXECUTE FUNCTION public.airfnb_prepare_truck_review();
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TRIGGER airfnb_profile_referral_code BEFORE INSERT ON public.airfnb_profiles FOR EACH ROW EXECUTE FUNCTION public.airfnb_assign_referral_code();
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TRIGGER airfnb_profiles_guard_role BEFORE INSERT OR UPDATE ON public.airfnb_profiles FOR EACH ROW EXECUTE FUNCTION public.airfnb_guard_profile_role();
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TRIGGER airfnb_trg_app_touch BEFORE UPDATE ON public.airfnb_applications FOR EACH ROW EXECUTE FUNCTION public.airfnb_touch_updated_at();
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TRIGGER airfnb_trg_bookings_touch BEFORE UPDATE ON public.airfnb_bookings FOR EACH ROW EXECUTE FUNCTION public.airfnb_touch_updated_at();
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TRIGGER airfnb_trg_platform_settings_touch BEFORE UPDATE ON public.airfnb_platform_settings FOR EACH ROW EXECUTE FUNCTION public.airfnb_platform_settings_touch();
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TRIGGER airfnb_trg_profiles_touch BEFORE UPDATE ON public.airfnb_profiles FOR EACH ROW EXECUTE FUNCTION public.airfnb_touch_updated_at();
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TRIGGER airfnb_trg_req_recommend BEFORE INSERT ON public.airfnb_event_requests FOR EACH ROW EXECUTE FUNCTION public.airfnb_set_recommended_slots();
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TRIGGER airfnb_trg_req_touch BEFORE UPDATE ON public.airfnb_event_requests FOR EACH ROW EXECUTE FUNCTION public.airfnb_touch_updated_at();
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TRIGGER airfnb_trg_reviews_rating AFTER INSERT OR DELETE OR UPDATE OF truck_id, rating_overall ON public.airfnb_reviews FOR EACH ROW EXECUTE FUNCTION public.airfnb_recalc_truck_rating();
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TRIGGER airfnb_trg_trucks_moderation BEFORE INSERT OR UPDATE ON public.airfnb_trucks FOR EACH ROW EXECUTE FUNCTION public.airfnb_guard_truck_moderation();
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE TRIGGER airfnb_trg_trucks_touch BEFORE UPDATE ON public.airfnb_trucks FOR EACH ROW EXECUTE FUNCTION public.airfnb_touch_updated_at();
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_addresses
    ADD CONSTRAINT airfnb_addresses_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.airfnb_profiles(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_applications
    ADD CONSTRAINT airfnb_applications_request_id_fkey FOREIGN KEY (request_id) REFERENCES public.airfnb_event_requests(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_applications
    ADD CONSTRAINT airfnb_applications_truck_id_fkey FOREIGN KEY (truck_id) REFERENCES public.airfnb_trucks(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_blog_authors
    ADD CONSTRAINT airfnb_blog_authors_id_fkey FOREIGN KEY (id) REFERENCES public.airfnb_profiles(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_blog_posts
    ADD CONSTRAINT airfnb_blog_posts_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.airfnb_blog_authors(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_blog_posts
    ADD CONSTRAINT airfnb_blog_posts_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.airfnb_blog_categories(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_booking_addons
    ADD CONSTRAINT airfnb_booking_addons_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.airfnb_bookings(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_booking_addons
    ADD CONSTRAINT airfnb_booking_addons_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES public.airfnb_service_providers(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_booking_trucks
    ADD CONSTRAINT airfnb_booking_trucks_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.airfnb_bookings(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_booking_trucks
    ADD CONSTRAINT airfnb_booking_trucks_truck_id_fkey FOREIGN KEY (truck_id) REFERENCES public.airfnb_trucks(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_bookings
    ADD CONSTRAINT airfnb_bookings_application_id_fkey FOREIGN KEY (application_id) REFERENCES public.airfnb_applications(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_bookings
    ADD CONSTRAINT airfnb_bookings_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.airfnb_events(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_bookings
    ADD CONSTRAINT airfnb_bookings_organizer_id_fkey FOREIGN KEY (organizer_id) REFERENCES public.airfnb_profiles(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_contact_requests
    ADD CONSTRAINT airfnb_contact_requests_handled_by_fkey FOREIGN KEY (handled_by) REFERENCES public.airfnb_profiles(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_conversation_participants
    ADD CONSTRAINT airfnb_conversation_participants_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.airfnb_conversations(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_conversation_participants
    ADD CONSTRAINT airfnb_conversation_participants_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.airfnb_profiles(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_conversations
    ADD CONSTRAINT airfnb_conversations_application_id_fkey FOREIGN KEY (application_id) REFERENCES public.airfnb_applications(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_conversations
    ADD CONSTRAINT airfnb_conversations_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.airfnb_bookings(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_event_requests
    ADD CONSTRAINT airfnb_event_requests_address_id_fkey FOREIGN KEY (address_id) REFERENCES public.airfnb_addresses(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_event_requests
    ADD CONSTRAINT airfnb_event_requests_organizer_id_fkey FOREIGN KEY (organizer_id) REFERENCES public.airfnb_profiles(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_events
    ADD CONSTRAINT airfnb_events_address_id_fkey FOREIGN KEY (address_id) REFERENCES public.airfnb_addresses(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_events
    ADD CONSTRAINT airfnb_events_organizer_id_fkey FOREIGN KEY (organizer_id) REFERENCES public.airfnb_profiles(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_favorites
    ADD CONSTRAINT airfnb_favorites_truck_id_fkey FOREIGN KEY (truck_id) REFERENCES public.airfnb_trucks(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_favorites
    ADD CONSTRAINT airfnb_favorites_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.airfnb_profiles(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_invoices
    ADD CONSTRAINT airfnb_invoices_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.airfnb_bookings(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_lock_fees
    ADD CONSTRAINT airfnb_lock_fees_application_id_fkey FOREIGN KEY (application_id) REFERENCES public.airfnb_applications(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_menu_items
    ADD CONSTRAINT airfnb_menu_items_truck_id_fkey FOREIGN KEY (truck_id) REFERENCES public.airfnb_trucks(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_messages
    ADD CONSTRAINT airfnb_messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.airfnb_conversations(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_messages
    ADD CONSTRAINT airfnb_messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES public.airfnb_profiles(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_notifications
    ADD CONSTRAINT airfnb_notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.airfnb_profiles(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_organizer_reviews
    ADD CONSTRAINT airfnb_organizer_reviews_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.airfnb_bookings(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_organizer_reviews
    ADD CONSTRAINT airfnb_organizer_reviews_organizer_id_fkey FOREIGN KEY (organizer_id) REFERENCES public.airfnb_profiles(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_organizer_reviews
    ADD CONSTRAINT airfnb_organizer_reviews_truck_id_fkey FOREIGN KEY (truck_id) REFERENCES public.airfnb_trucks(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_partner_leads
    ADD CONSTRAINT airfnb_partner_leads_handled_by_fkey FOREIGN KEY (handled_by) REFERENCES public.airfnb_profiles(id) ON DELETE SET NULL;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_payments
    ADD CONSTRAINT airfnb_payments_application_id_fkey FOREIGN KEY (application_id) REFERENCES public.airfnb_applications(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_payments
    ADD CONSTRAINT airfnb_payments_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.airfnb_bookings(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_payments
    ADD CONSTRAINT airfnb_payments_lock_fee_id_fkey FOREIGN KEY (lock_fee_id) REFERENCES public.airfnb_lock_fees(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_platform_settings
    ADD CONSTRAINT airfnb_platform_settings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.airfnb_profiles(id) ON DELETE SET NULL;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_profiles
    ADD CONSTRAINT airfnb_profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_profiles
    ADD CONSTRAINT airfnb_profiles_referred_by_fkey FOREIGN KEY (referred_by) REFERENCES public.airfnb_profiles(id) ON DELETE SET NULL;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_proposals
    ADD CONSTRAINT airfnb_proposals_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.airfnb_bookings(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_proposals
    ADD CONSTRAINT airfnb_proposals_prepared_by_fkey FOREIGN KEY (prepared_by) REFERENCES public.airfnb_profiles(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_request_invitations
    ADD CONSTRAINT airfnb_request_invitations_invited_by_fkey FOREIGN KEY (invited_by) REFERENCES public.airfnb_profiles(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_request_invitations
    ADD CONSTRAINT airfnb_request_invitations_request_id_fkey FOREIGN KEY (request_id) REFERENCES public.airfnb_event_requests(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_request_invitations
    ADD CONSTRAINT airfnb_request_invitations_truck_id_fkey FOREIGN KEY (truck_id) REFERENCES public.airfnb_trucks(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_reviews
    ADD CONSTRAINT airfnb_reviews_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.airfnb_bookings(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_reviews
    ADD CONSTRAINT airfnb_reviews_organizer_id_fkey FOREIGN KEY (organizer_id) REFERENCES public.airfnb_profiles(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_reviews
    ADD CONSTRAINT airfnb_reviews_truck_id_fkey FOREIGN KEY (truck_id) REFERENCES public.airfnb_trucks(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_stripe_events
    ADD CONSTRAINT airfnb_stripe_events_application_id_fkey FOREIGN KEY (application_id) REFERENCES public.airfnb_applications(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_stripe_events
    ADD CONSTRAINT airfnb_stripe_events_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.airfnb_bookings(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_stripe_events
    ADD CONSTRAINT airfnb_stripe_events_lock_fee_id_fkey FOREIGN KEY (lock_fee_id) REFERENCES public.airfnb_lock_fees(id);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_truck_alert_prefs
    ADD CONSTRAINT airfnb_truck_alert_prefs_truck_id_fkey FOREIGN KEY (truck_id) REFERENCES public.airfnb_trucks(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_truck_availability
    ADD CONSTRAINT airfnb_truck_availability_truck_id_fkey FOREIGN KEY (truck_id) REFERENCES public.airfnb_trucks(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_truck_categories
    ADD CONSTRAINT airfnb_truck_categories_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.airfnb_categories(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_truck_categories
    ADD CONSTRAINT airfnb_truck_categories_truck_id_fkey FOREIGN KEY (truck_id) REFERENCES public.airfnb_trucks(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_truck_documents
    ADD CONSTRAINT airfnb_truck_documents_truck_id_fkey FOREIGN KEY (truck_id) REFERENCES public.airfnb_trucks(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_truck_images
    ADD CONSTRAINT airfnb_truck_images_truck_id_fkey FOREIGN KEY (truck_id) REFERENCES public.airfnb_trucks(id) ON DELETE CASCADE;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE ONLY public.airfnb_trucks
    ADD CONSTRAINT airfnb_trucks_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.airfnb_profiles(id) ON DELETE SET NULL;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_addons_read ON public.airfnb_booking_addons FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.airfnb_bookings b
  WHERE ((b.id = airfnb_booking_addons.booking_id) AND ((b.organizer_id = auth.uid()) OR public.airfnb_is_admin())))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_addons_write ON public.airfnb_booking_addons USING ((EXISTS ( SELECT 1
   FROM public.airfnb_bookings b
  WHERE ((b.id = airfnb_booking_addons.booking_id) AND ((b.organizer_id = auth.uid()) OR public.airfnb_is_admin()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.airfnb_bookings b
  WHERE ((b.id = airfnb_booking_addons.booking_id) AND ((b.organizer_id = auth.uid()) OR public.airfnb_is_admin())))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_addresses ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_addresses_self ON public.airfnb_addresses USING (((owner_id = auth.uid()) OR public.airfnb_is_admin())) WITH CHECK (((owner_id = auth.uid()) OR public.airfnb_is_admin()));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_alerts_self ON public.airfnb_truck_alert_prefs USING (((EXISTS ( SELECT 1
   FROM public.airfnb_trucks t
  WHERE ((t.id = airfnb_truck_alert_prefs.truck_id) AND (t.owner_id = auth.uid())))) OR public.airfnb_is_admin())) WITH CHECK (((EXISTS ( SELECT 1
   FROM public.airfnb_trucks t
  WHERE ((t.id = airfnb_truck_alert_prefs.truck_id) AND (t.owner_id = auth.uid())))) OR public.airfnb_is_admin()));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_app_insert_guarded ON public.airfnb_applications FOR INSERT TO authenticated WITH CHECK (((status = 'submitted'::public.airfnb_application_status) AND (shortlisted_at IS NULL) AND (decided_at IS NULL) AND (withdrawn_at IS NULL) AND ( SELECT public.airfnb_can_submit_application(airfnb_applications.request_id, airfnb_applications.truck_id) AS airfnb_can_submit_application)));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_app_select_participant ON public.airfnb_applications FOR SELECT TO authenticated USING ((( SELECT public.airfnb_is_admin() AS airfnb_is_admin) OR ( SELECT public.airfnb_can_manage_truck((airfnb_applications.truck_id)::text) AS airfnb_can_manage_truck) OR (EXISTS ( SELECT 1
   FROM public.airfnb_event_requests request_row
  WHERE ((request_row.id = airfnb_applications.request_id) AND (request_row.organizer_id = ( SELECT auth.uid() AS uid)))))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_applications ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_audit_admin_read ON public.airfnb_audit_log FOR SELECT USING (public.airfnb_is_admin());
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_audit_log ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_blog_authors ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_blog_authors_read ON public.airfnb_blog_authors FOR SELECT USING (true);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_blog_authors_self ON public.airfnb_blog_authors USING (((id = auth.uid()) OR public.airfnb_is_admin())) WITH CHECK (((id = auth.uid()) OR public.airfnb_is_admin()));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_blog_cat_admin_write ON public.airfnb_blog_categories USING (public.airfnb_is_admin()) WITH CHECK (public.airfnb_is_admin());
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_blog_cat_read ON public.airfnb_blog_categories FOR SELECT USING (true);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_blog_categories ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_blog_posts ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_booking_addons ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_booking_trucks ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_bookings ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_bookings_select ON public.airfnb_bookings FOR SELECT USING (((organizer_id = auth.uid()) OR public.airfnb_is_admin() OR (EXISTS ( SELECT 1
   FROM (public.airfnb_booking_trucks bt
     JOIN public.airfnb_trucks t ON ((t.id = bt.truck_id)))
  WHERE ((bt.booking_id = airfnb_bookings.id) AND (t.owner_id = auth.uid()))))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_btrucks_read ON public.airfnb_booking_trucks FOR SELECT USING (((EXISTS ( SELECT 1
   FROM public.airfnb_bookings b
  WHERE ((b.id = airfnb_booking_trucks.booking_id) AND (b.organizer_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM public.airfnb_trucks t
  WHERE ((t.id = airfnb_booking_trucks.truck_id) AND (t.owner_id = auth.uid())))) OR public.airfnb_is_admin()));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_categories ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_categories_admin_write ON public.airfnb_categories USING (public.airfnb_is_admin()) WITH CHECK (public.airfnb_is_admin());
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_categories_read ON public.airfnb_categories FOR SELECT USING (true);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_contact_admin_read ON public.airfnb_contact_requests FOR SELECT USING (public.airfnb_is_admin());
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_contact_requests ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_conversation_participants ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_conversations ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_convs_select_participant ON public.airfnb_conversations FOR SELECT TO authenticated USING ((( SELECT public.airfnb_is_admin() AS airfnb_is_admin) OR (EXISTS ( SELECT 1
   FROM public.airfnb_conversation_participants cp
  WHERE ((cp.conversation_id = airfnb_conversations.id) AND (cp.user_id = ( SELECT auth.uid() AS uid)))))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_cp_select_participant ON public.airfnb_conversation_participants FOR SELECT TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) OR ( SELECT public.airfnb_is_admin() AS airfnb_is_admin)));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_event_requests ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_events ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_events_owner_read ON public.airfnb_events FOR SELECT USING ((EXISTS ( SELECT 1
   FROM ((public.airfnb_bookings b
     JOIN public.airfnb_booking_trucks bt ON ((bt.booking_id = b.id)))
     JOIN public.airfnb_trucks t ON ((t.id = bt.truck_id)))
  WHERE ((b.event_id = airfnb_events.id) AND (t.owner_id = auth.uid())))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_events_self ON public.airfnb_events USING (((organizer_id = auth.uid()) OR public.airfnb_is_admin())) WITH CHECK (((organizer_id = auth.uid()) OR public.airfnb_is_admin()));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_faqs ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_faqs_admin_write ON public.airfnb_faqs USING (public.airfnb_is_admin()) WITH CHECK (public.airfnb_is_admin());
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_faqs_read ON public.airfnb_faqs FOR SELECT USING (true);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_fav_self ON public.airfnb_favorites USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_favorites ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_inv_insert ON public.airfnb_request_invitations FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.airfnb_event_requests r
  WHERE ((r.id = airfnb_request_invitations.request_id) AND (r.organizer_id = auth.uid())))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_inv_read ON public.airfnb_request_invitations FOR SELECT USING ((public.airfnb_is_admin() OR (EXISTS ( SELECT 1
   FROM public.airfnb_trucks t
  WHERE ((t.id = airfnb_request_invitations.truck_id) AND (t.owner_id = auth.uid())))) OR public.airfnb_user_organizes_request(request_id)));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_inv_update ON public.airfnb_request_invitations FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.airfnb_trucks t
  WHERE ((t.id = airfnb_request_invitations.truck_id) AND (t.owner_id = auth.uid())))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_invoices ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_invoices_owner_read ON public.airfnb_invoices FOR SELECT USING ((EXISTS ( SELECT 1
   FROM (public.airfnb_booking_trucks bt
     JOIN public.airfnb_trucks t ON ((t.id = bt.truck_id)))
  WHERE ((bt.booking_id = airfnb_invoices.booking_id) AND (t.owner_id = auth.uid())))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_invoices_read ON public.airfnb_invoices FOR SELECT USING ((public.airfnb_is_admin() OR (EXISTS ( SELECT 1
   FROM public.airfnb_bookings b
  WHERE ((b.id = airfnb_invoices.booking_id) AND (b.organizer_id = auth.uid()))))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_invoices_write ON public.airfnb_invoices USING (public.airfnb_is_admin()) WITH CHECK (public.airfnb_is_admin());
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_lock_fees ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_lockfee_read ON public.airfnb_lock_fees FOR SELECT USING ((public.airfnb_is_admin() OR (EXISTS ( SELECT 1
   FROM (public.airfnb_applications a
     JOIN public.airfnb_trucks t ON ((t.id = a.truck_id)))
  WHERE ((a.id = airfnb_lock_fees.application_id) AND (t.owner_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM (public.airfnb_applications a
     JOIN public.airfnb_event_requests r ON ((r.id = a.request_id)))
  WHERE ((a.id = airfnb_lock_fees.application_id) AND (r.organizer_id = auth.uid()))))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_menu_items ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_menu_items_read ON public.airfnb_menu_items FOR SELECT TO anon, authenticated USING (public.airfnb_can_read_truck_child((truck_id)::text));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_menu_items_write ON public.airfnb_menu_items TO authenticated USING (public.airfnb_can_manage_truck((truck_id)::text)) WITH CHECK (public.airfnb_can_manage_truck((truck_id)::text));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_messages ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_membership_tombstones ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_msg_insert_participant ON public.airfnb_messages FOR INSERT TO authenticated WITH CHECK (((sender_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM public.airfnb_conversation_participants cp
  WHERE ((cp.conversation_id = airfnb_messages.conversation_id) AND (cp.user_id = ( SELECT auth.uid() AS uid)))))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_msg_select_participant ON public.airfnb_messages FOR SELECT TO authenticated USING ((( SELECT public.airfnb_is_admin() AS airfnb_is_admin) OR (EXISTS ( SELECT 1
   FROM public.airfnb_conversation_participants cp
  WHERE ((cp.conversation_id = airfnb_messages.conversation_id) AND (cp.user_id = ( SELECT auth.uid() AS uid)))))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_newsletter_admin_read ON public.airfnb_newsletter_subs FOR SELECT USING (public.airfnb_is_admin());
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_newsletter_admin_read ON public.airfnb_newsletter_subscribers FOR SELECT USING (public.airfnb_is_admin());
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_newsletter_subs ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_newsletter_subscribers ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_notif_self ON public.airfnb_notifications FOR SELECT USING ((user_id = auth.uid()));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_notif_self_update ON public.airfnb_notifications FOR UPDATE USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_notifications ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_org_reviews_participant_insert ON public.airfnb_organizer_reviews FOR INSERT TO authenticated WITH CHECK (((is_verified IS TRUE) AND ((rating_reliability >= 1) AND (rating_reliability <= 5)) AND ((rating_communication >= 1) AND (rating_communication <= 5)) AND ((rating_payment >= 1) AND (rating_payment <= 5)) AND (rating_overall = round(((((rating_reliability + rating_communication) + rating_payment))::numeric / (3)::numeric), 1)) AND (reply_body IS NULL) AND (reply_at IS NULL) AND public.airfnb_can_manage_truck((truck_id)::text)));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_org_reviews_public_read ON public.airfnb_organizer_reviews FOR SELECT TO anon, authenticated USING (true);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_organizer_reviews ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_partner_leads ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_partner_leads_admin_read ON public.airfnb_partner_leads FOR SELECT USING (public.airfnb_is_admin());
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_partner_leads_admin_update ON public.airfnb_partner_leads FOR UPDATE USING (public.airfnb_is_admin()) WITH CHECK (public.airfnb_is_admin());
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_payments ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_payments_owner_read ON public.airfnb_payments FOR SELECT USING ((EXISTS ( SELECT 1
   FROM (public.airfnb_booking_trucks bt
     JOIN public.airfnb_trucks t ON ((t.id = bt.truck_id)))
  WHERE ((bt.booking_id = airfnb_payments.booking_id) AND (t.owner_id = auth.uid())))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_payments_read ON public.airfnb_payments FOR SELECT USING ((public.airfnb_is_admin() OR (EXISTS ( SELECT 1
   FROM public.airfnb_bookings b
  WHERE ((b.id = airfnb_payments.booking_id) AND (b.organizer_id = auth.uid()))))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_platform_settings ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_platform_settings_admin_read ON public.airfnb_platform_settings FOR SELECT USING (public.airfnb_is_admin());
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_platform_settings_admin_write ON public.airfnb_platform_settings USING (public.airfnb_is_admin()) WITH CHECK (public.airfnb_is_admin());
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_posts_public_read ON public.airfnb_blog_posts FOR SELECT USING (((status = 'published'::public.airfnb_post_status) OR public.airfnb_is_admin()));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_profile_self ON public.airfnb_profiles USING (((id = auth.uid()) OR public.airfnb_is_admin())) WITH CHECK (((id = auth.uid()) OR public.airfnb_is_admin()));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_profiles ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_proposals ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_proposals_read ON public.airfnb_proposals FOR SELECT USING ((public.airfnb_is_admin() OR (EXISTS ( SELECT 1
   FROM public.airfnb_bookings b
  WHERE ((b.id = airfnb_proposals.booking_id) AND (b.organizer_id = auth.uid()))))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_proposals_write ON public.airfnb_proposals USING (public.airfnb_is_admin()) WITH CHECK (public.airfnb_is_admin());
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_providers_admin_write ON public.airfnb_service_providers USING (public.airfnb_is_admin()) WITH CHECK (public.airfnb_is_admin());
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_providers_read ON public.airfnb_service_providers FOR SELECT USING (true);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_rate_limits ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_req_delete ON public.airfnb_event_requests FOR DELETE USING (((organizer_id = auth.uid()) OR public.airfnb_is_admin()));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_req_insert ON public.airfnb_event_requests FOR INSERT WITH CHECK ((organizer_id = auth.uid()));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_req_public_read ON public.airfnb_event_requests FOR SELECT USING ((((visibility = 'public'::text) AND (status = ANY (ARRAY['open'::public.airfnb_request_status, 'reviewing'::public.airfnb_request_status, 'awarded'::public.airfnb_request_status]))) OR (organizer_id = auth.uid()) OR public.airfnb_is_admin() OR public.airfnb_user_owns_invited_truck(id)));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_req_update ON public.airfnb_event_requests FOR UPDATE USING (((organizer_id = auth.uid()) OR public.airfnb_is_admin()));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_request_invitations ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_reviews ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_reviews_participant_insert ON public.airfnb_reviews FOR INSERT TO authenticated WITH CHECK (((organizer_id = ( SELECT auth.uid() AS uid)) AND (is_verified IS TRUE) AND ((rating_food >= 1) AND (rating_food <= 5)) AND ((rating_service >= 1) AND (rating_service <= 5)) AND ((rating_value >= 1) AND (rating_value <= 5)) AND (rating_overall = round(((((rating_food + rating_service) + rating_value))::numeric / (3)::numeric), 1)) AND (reply_body IS NULL) AND (reply_at IS NULL)));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_reviews_public_read ON public.airfnb_reviews FOR SELECT TO anon, authenticated USING (true);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_service_providers ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_stripe_events ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_truck_alert_prefs ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_truck_avail_write ON public.airfnb_truck_availability USING ((EXISTS ( SELECT 1
   FROM public.airfnb_trucks t
  WHERE ((t.id = airfnb_truck_availability.truck_id) AND ((t.owner_id = auth.uid()) OR public.airfnb_is_admin())))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_truck_availability ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_truck_cat_read ON public.airfnb_truck_categories FOR SELECT TO anon, authenticated USING (public.airfnb_can_read_truck_child((truck_id)::text));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_truck_cat_write ON public.airfnb_truck_categories TO authenticated USING (public.airfnb_can_manage_truck((truck_id)::text)) WITH CHECK (public.airfnb_can_manage_truck((truck_id)::text));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_truck_categories ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_truck_docs_write ON public.airfnb_truck_documents USING ((EXISTS ( SELECT 1
   FROM public.airfnb_trucks t
  WHERE ((t.id = airfnb_truck_documents.truck_id) AND ((t.owner_id = auth.uid()) OR public.airfnb_is_admin())))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_truck_documents ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_truck_images ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_truck_images_read ON public.airfnb_truck_images FOR SELECT TO anon, authenticated USING (public.airfnb_can_read_truck_child((truck_id)::text));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_truck_images_write ON public.airfnb_truck_images TO authenticated USING (public.airfnb_can_manage_truck((truck_id)::text)) WITH CHECK (public.airfnb_can_manage_truck((truck_id)::text));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
ALTER TABLE public.airfnb_trucks ENABLE ROW LEVEL SECURITY;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_trucks_owner_insert ON public.airfnb_trucks FOR INSERT TO authenticated WITH CHECK (((owner_id = ( SELECT auth.uid() AS uid)) OR public.airfnb_is_admin()));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_trucks_owner_update ON public.airfnb_trucks FOR UPDATE TO authenticated USING (((owner_id = ( SELECT auth.uid() AS uid)) OR public.airfnb_is_admin())) WITH CHECK (((owner_id = ( SELECT auth.uid() AS uid)) OR public.airfnb_is_admin()));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
CREATE POLICY airfnb_trucks_public_read ON public.airfnb_trucks FOR SELECT USING (((status = 'active'::public.airfnb_truck_status) OR (owner_id = auth.uid()) OR public.airfnb_is_admin()));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_accept_application(p_application uuid) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_accept_application(p_application uuid) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_accept_application(p_application uuid) TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_admin_approve_truck(p_truck uuid) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_admin_approve_truck(p_truck uuid) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_admin_metrics() FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_admin_metrics() TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_admin_pending_trucks(p_limit integer) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_admin_pending_trucks(p_limit integer) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_admin_reject_truck(p_truck uuid, p_reason text) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_admin_reject_truck(p_truck uuid, p_reason text) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_apply_referral(p_code text) FROM PUBLIC, anon, authenticated, service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT EXECUTE ON FUNCTION public.airfnb_apply_referral(p_code text) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_assign_referral_code() FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_booking_by_ics_token(p_token text) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_booking_by_ics_token(p_token text) TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_booking_by_ics_token(p_token text) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_booking_service_context(p_booking uuid) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_booking_service_context(p_booking uuid) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_calculate_lock_fee(p_application uuid) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_calculate_lock_fee(p_application uuid) TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_can_manage_truck(p_truck_text text) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_can_manage_truck(p_truck_text text) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_can_read_truck_child(p_truck_text text) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_can_read_truck_child(p_truck_text text) TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_can_read_truck_child(p_truck_text text) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_can_submit_application(p_request uuid, p_truck uuid) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_can_submit_application(p_request uuid, p_truck uuid) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_check_rate_limit(p_action text, p_bucket text, p_limit_per_window integer, p_window_seconds integer) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_check_rate_limit(p_action text, p_bucket text, p_limit_per_window integer, p_window_seconds integer) TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON TABLE public.airfnb_profiles FROM PUBLIC, anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE INSERT,UPDATE,DELETE ON TABLE public.airfnb_profiles FROM authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE UPDATE(id,role,organizer_rating_avg,organizer_rating_count,referral_code,referred_by,referrals_count,created_at,updated_at) ON TABLE public.airfnb_profiles FROM authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT ON TABLE public.airfnb_profiles TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT UPDATE(full_name,display_name,phone,avatar_url,locale,vat_number,company_name,marketing_opt_in,onboarding_completed,address_line,billing_address_line) ON TABLE public.airfnb_profiles TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON TABLE public.airfnb_membership_tombstones FROM PUBLIC, anon, authenticated, service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_claim_role(p_role public.airfnb_user_role) FROM PUBLIC, anon, authenticated, service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT EXECUTE ON FUNCTION public.airfnb_claim_role(p_role public.airfnb_user_role) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_conversation_peers() FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_conversation_peers() TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_conversation_summaries() FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_conversation_summaries() TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_ensure_profile(p_full_name text, p_locale text) FROM PUBLIC, anon, authenticated, service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT EXECUTE ON FUNCTION public.airfnb_ensure_profile(p_full_name text, p_locale text) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_expire_stale_lock_fees() FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_expire_stale_lock_fees() TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_expire_stale_requests() FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_expire_stale_requests() TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_find_matching_requests(p_truck uuid, p_limit integer) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_find_matching_requests(p_truck uuid, p_limit integer) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_find_matching_trucks(p_request uuid, p_limit integer) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_find_matching_trucks(p_request uuid, p_limit integer) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_generate_referral_code() FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_guard_profile_role() FROM PUBLIC, anon, authenticated, service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_guard_truck_moderation() FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_invitation_candidates(p_request uuid) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_invitation_candidates(p_request uuid) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_invite_request_services(p_request uuid, p_trucks uuid[]) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_invite_request_services(p_request uuid, p_trucks uuid[]) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_is_admin() FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_is_admin() TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_is_admin() TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_is_truck_owner(p_truck_text text) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_is_truck_owner(p_truck_text text) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_is_truck_owner(p_truck_id uuid) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_is_truck_owner(p_truck_id uuid) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_mark_conversation_read(p_conversation uuid) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_mark_conversation_read(p_conversation uuid) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_match_category_availability_score(p_truck uuid, p_request uuid) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_match_category_availability_score(p_truck uuid, p_request uuid) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_match_score(p_truck uuid, p_request uuid) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_match_score(p_truck uuid, p_request uuid) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_match_scores_batch(p_truck_ids uuid[], p_request_ids uuid[]) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_match_scores_batch(p_truck_ids uuid[], p_request_ids uuid[]) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_organizer_rating_recompute() FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_own_application_truck() FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_own_application_truck() TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_prepare_organizer_review() FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_prepare_truck_review() FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT ON TABLE public.airfnb_event_requests TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(id) ON TABLE public.airfnb_event_requests TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(id) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(organizer_id) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(title) ON TABLE public.airfnb_event_requests TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(title) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(kind) ON TABLE public.airfnb_event_requests TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(kind) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(description) ON TABLE public.airfnb_event_requests TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(description) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(start_at) ON TABLE public.airfnb_event_requests TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(start_at) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(end_at) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(city) ON TABLE public.airfnb_event_requests TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(city) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(expected_pax) ON TABLE public.airfnb_event_requests TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(expected_pax) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(slots_needed) ON TABLE public.airfnb_event_requests TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(slots_needed) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(budget_min) ON TABLE public.airfnb_event_requests TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(budget_min) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(budget_max) ON TABLE public.airfnb_event_requests TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(budget_max) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(desired_categories) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(dietary_requirements) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(applications_deadline) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(power_available) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(notes) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(status) ON TABLE public.airfnb_event_requests TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(status) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(visibility) ON TABLE public.airfnb_event_requests TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(visibility) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(created_at) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(discovery_mode) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(accepted_deal_types) ON TABLE public.airfnb_event_requests TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(accepted_deal_types) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(min_fixed_fee) ON TABLE public.airfnb_event_requests TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(min_fixed_fee) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(min_revenue_share_pct) ON TABLE public.airfnb_event_requests TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(min_revenue_share_pct) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(locality) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(desired_cuisines) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(setup_minutes) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(energy_need) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(energy_assistance) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(sanitation_level) ON TABLE public.airfnb_event_requests TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_private_event_requests(p_request_id uuid) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_private_event_requests(p_request_id uuid) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_public_service_detail(p_slug text) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_public_service_detail(p_slug text) TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_public_service_detail(p_slug text) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_recalc_truck_rating() FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_recommend_trucks_for_request(p_request uuid, p_limit integer) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_recommend_trucks_for_request(p_request uuid, p_limit integer) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_reconcile_stripe_event(p_event_id text, p_event_type text, p_event_created_at timestamp with time zone, p_application_id uuid, p_lock_fee_id uuid, p_booking_id uuid, p_payment_intent text, p_amount_minor bigint, p_currency text, p_payment_status text, p_refunded_amount_minor bigint) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_reconcile_stripe_event(p_event_id text, p_event_type text, p_event_created_at timestamp with time zone, p_application_id uuid, p_lock_fee_id uuid, p_booking_id uuid, p_payment_intent text, p_amount_minor bigint, p_currency text, p_payment_status text, p_refunded_amount_minor bigint) TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_reject_application(p_application uuid, p_reason text) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_reject_application(p_application uuid, p_reason text) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_reject_application(p_application uuid, p_reason text) TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_reply_to_organizer_review(p_review uuid, p_reply text) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_reply_to_organizer_review(p_review uuid, p_reply text) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_reply_to_truck_review(p_review uuid, p_reply text) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_reply_to_truck_review(p_review uuid, p_reply text) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_request_application_service_context(p_request uuid) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_request_application_service_context(p_request uuid) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_self_delete() FROM PUBLIC, anon, authenticated, service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT EXECUTE ON FUNCTION public.airfnb_self_delete() TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_self_delete_storage_prefixes() FROM PUBLIC, anon, authenticated, service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT EXECUTE ON FUNCTION public.airfnb_self_delete_storage_prefixes() TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_setting_int(p_key text, p_fallback integer) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_setting_int(p_key text, p_fallback integer) TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_shortlist_application(p_application uuid) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_shortlist_application(p_application uuid) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_shortlist_application(p_application uuid) TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_supplier_export_data() FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_supplier_export_data() TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_supplier_lock_fee(p_application uuid) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_supplier_lock_fee(p_application uuid) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_supplier_services(p_truck uuid) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_supplier_services(p_truck uuid) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_truck_is_available(p_truck uuid, p_from date, p_to date) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_truck_is_available(p_truck uuid, p_from date, p_to date) TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_truck_is_available(p_truck uuid, p_from date, p_to date) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_user_organizes_request(p_request uuid) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_user_organizes_request(p_request uuid) TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_user_organizes_request(p_request uuid) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_user_organizes_request(p_request uuid) TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
REVOKE ALL ON FUNCTION public.airfnb_user_owns_invited_truck(p_request uuid) FROM PUBLIC;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_user_owns_invited_truck(p_request uuid) TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_user_owns_invited_truck(p_request uuid) TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT ALL ON FUNCTION public.airfnb_user_owns_invited_truck(p_request uuid) TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT ON TABLE public.airfnb_applications TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.airfnb_applications TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(request_id) ON TABLE public.airfnb_applications TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(truck_id) ON TABLE public.airfnb_applications TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(proposed_price) ON TABLE public.airfnb_applications TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(cover_message) ON TABLE public.airfnb_applications TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(menu_pitch) ON TABLE public.airfnb_applications TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(estimated_servings) ON TABLE public.airfnb_applications TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(available_confirmed) ON TABLE public.airfnb_applications TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(deal_type) ON TABLE public.airfnb_applications TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(proposed_fixed_to_organizer) ON TABLE public.airfnb_applications TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(proposed_revenue_share_pct) ON TABLE public.airfnb_applications TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT ON TABLE public.airfnb_booking_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.airfnb_booking_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT ON TABLE public.airfnb_bookings TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.airfnb_bookings TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(id) ON TABLE public.airfnb_categories TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(id) ON TABLE public.airfnb_categories TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(id) ON TABLE public.airfnb_categories TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(slug) ON TABLE public.airfnb_categories TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(slug) ON TABLE public.airfnb_categories TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(slug) ON TABLE public.airfnb_categories TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(name_pt) ON TABLE public.airfnb_categories TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(name_pt) ON TABLE public.airfnb_categories TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(name_pt) ON TABLE public.airfnb_categories TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(name_en) ON TABLE public.airfnb_categories TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(name_en) ON TABLE public.airfnb_categories TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(name_en) ON TABLE public.airfnb_categories TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(icon) ON TABLE public.airfnb_categories TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(icon) ON TABLE public.airfnb_categories TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(icon) ON TABLE public.airfnb_categories TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT ON TABLE public.airfnb_contact_requests TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT ON TABLE public.airfnb_conversation_participants TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT ON TABLE public.airfnb_conversations TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT ON TABLE public.airfnb_lock_fees TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT ON TABLE public.airfnb_messages TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(conversation_id) ON TABLE public.airfnb_messages TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(sender_id) ON TABLE public.airfnb_messages TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(body) ON TABLE public.airfnb_messages TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(attachments) ON TABLE public.airfnb_messages TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT,INSERT,UPDATE ON TABLE public.airfnb_newsletter_subs TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT ON TABLE public.airfnb_newsletter_subscribers TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT ON TABLE public.airfnb_organizer_reviews TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT ON TABLE public.airfnb_organizer_reviews TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(booking_id) ON TABLE public.airfnb_organizer_reviews TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(truck_id) ON TABLE public.airfnb_organizer_reviews TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(rating_reliability) ON TABLE public.airfnb_organizer_reviews TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(rating_communication) ON TABLE public.airfnb_organizer_reviews TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(rating_payment) ON TABLE public.airfnb_organizer_reviews TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(body) ON TABLE public.airfnb_organizer_reviews TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT ON TABLE public.airfnb_partner_leads TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT ON TABLE public.airfnb_payments TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT ON TABLE public.airfnb_request_invitations TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT ON TABLE public.airfnb_reviews TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT ON TABLE public.airfnb_reviews TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(booking_id) ON TABLE public.airfnb_reviews TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(truck_id) ON TABLE public.airfnb_reviews TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(rating_food) ON TABLE public.airfnb_reviews TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(rating_service) ON TABLE public.airfnb_reviews TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(rating_value) ON TABLE public.airfnb_reviews TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(body) ON TABLE public.airfnb_reviews TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT ON TABLE public.airfnb_stripe_events TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(truck_id) ON TABLE public.airfnb_truck_categories TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(truck_id) ON TABLE public.airfnb_truck_categories TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(truck_id) ON TABLE public.airfnb_truck_categories TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(category_id) ON TABLE public.airfnb_truck_categories TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(category_id) ON TABLE public.airfnb_truck_categories TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(category_id) ON TABLE public.airfnb_truck_categories TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(id) ON TABLE public.airfnb_truck_images TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(truck_id) ON TABLE public.airfnb_truck_images TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(truck_id) ON TABLE public.airfnb_truck_images TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(truck_id) ON TABLE public.airfnb_truck_images TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(url) ON TABLE public.airfnb_truck_images TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(url) ON TABLE public.airfnb_truck_images TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(url) ON TABLE public.airfnb_truck_images TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(sort_order) ON TABLE public.airfnb_truck_images TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(sort_order) ON TABLE public.airfnb_truck_images TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(sort_order) ON TABLE public.airfnb_truck_images TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(is_cover) ON TABLE public.airfnb_truck_images TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(is_cover) ON TABLE public.airfnb_truck_images TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(is_cover) ON TABLE public.airfnb_truck_images TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(kind) ON TABLE public.airfnb_truck_images TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(kind) ON TABLE public.airfnb_truck_images TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(kind) ON TABLE public.airfnb_truck_images TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(id) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(id) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(id) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(owner_id) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(slug),INSERT(slug) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(slug) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(slug) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(name),INSERT(name),UPDATE(name) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(name) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(name) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(tagline),INSERT(tagline),UPDATE(tagline) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(tagline) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(tagline) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(description),UPDATE(description) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(base_city),INSERT(base_city),UPDATE(base_city) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(base_city) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(base_city) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(service_radius_km),INSERT(service_radius_km),UPDATE(service_radius_km) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(service_radius_km) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(service_radius_km) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(capacity),INSERT(capacity),UPDATE(capacity) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(capacity) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(capacity) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(min_event_pax),INSERT(min_event_pax),UPDATE(min_event_pax) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(min_event_pax) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(min_event_pax) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(max_event_pax),INSERT(max_event_pax),UPDATE(max_event_pax) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(max_event_pax) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(max_event_pax) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(base_price),INSERT(base_price),UPDATE(base_price) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(base_price) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(base_price) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(price_per_pax),INSERT(price_per_pax),UPDATE(price_per_pax) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(price_per_pax) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(price_per_pax) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(setup_minutes),INSERT(setup_minutes),UPDATE(setup_minutes) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(setup_minutes) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(setup_minutes) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(power_required_kw),INSERT(power_required_kw),UPDATE(power_required_kw) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(power_required_kw) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(power_required_kw) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(needs_water),UPDATE(needs_water) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT INSERT(dimensions_m),UPDATE(dimensions_m) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(status),INSERT(status),UPDATE(status) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(status) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(status) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(rating_avg) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(rating_avg) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(rating_avg) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(rating_count) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(rating_count) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(rating_count) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(featured) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(featured) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(featured) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(cuisine_types),INSERT(cuisine_types),UPDATE(cuisine_types) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(cuisine_types) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(cuisine_types) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(dietary_options),INSERT(dietary_options),UPDATE(dietary_options) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(dietary_options) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(dietary_options) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(teardown_minutes),INSERT(teardown_minutes),UPDATE(teardown_minutes) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(teardown_minutes) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(teardown_minutes) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(sanitation_required),INSERT(sanitation_required),UPDATE(sanitation_required) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(sanitation_required) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(sanitation_required) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(catering_type),INSERT(catering_type),UPDATE(catering_type) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(catering_type) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(catering_type) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(serves),INSERT(serves),UPDATE(serves) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(serves) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(serves) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(compatible_event_kinds),INSERT(compatible_event_kinds),UPDATE(compatible_event_kinds) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(compatible_event_kinds) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(compatible_event_kinds) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(service_type),INSERT(service_type),UPDATE(service_type) ON TABLE public.airfnb_trucks TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(service_type) ON TABLE public.airfnb_trucks TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT(service_type) ON TABLE public.airfnb_trucks TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT ON TABLE public.airfnb_v_truck_card TO anon;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT ON TABLE public.airfnb_v_truck_card TO authenticated;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
GRANT SELECT ON TABLE public.airfnb_v_truck_card TO service_role;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_trucks VALUES ('44ab71c1-9927-4e9c-89cc-6bd7681b3726', NULL, 'divine-burguers', 'Divine Burguer''s', 'O melhor estilo americano', 'Hambúrgueres artesanais com pão de brioche e batatas trufadas.', 'Lisboa', 50, 100, 30, 500, 850.00, 12.50, 60, NULL, false, NULL, 'active', 4.8, 27, true, NULL, NULL, '2026-08-18 20:19:55.052757+01', '2026-08-21 14:08:17.481932+01', NULL, NULL, 'basic', '{}', '{}', 60, 'none', 'fixed', 'food_and_drinks', '{}', 'food_truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_trucks VALUES ('b98cf4f9-1ad0-4596-9511-da590aaf975e', NULL, 'gypsy-kitchen', 'Gypsy Kitchen', 'Cozinha de Fusão', 'Pratos de inspiração mediterrânica com toque oriental.', 'Lisboa', 50, 100, 30, 500, 900.00, 13.00, 60, NULL, false, NULL, 'active', 4.7, 18, true, NULL, NULL, '2026-08-18 20:19:55.052757+01', '2026-08-21 14:08:17.481932+01', NULL, NULL, 'basic', '{}', '{}', 60, 'none', 'fixed', 'food_and_drinks', '{}', 'food_truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_trucks VALUES ('11b7b30d-b215-452f-97a2-804a917ecccb', NULL, 'el-mexicano', 'El Mexicano', 'Autêntica comida mexicana', 'Tacos, quesadillas e burritos como em Cidade do México.', 'Porto', 50, 100, 30, 500, 780.00, 11.00, 60, NULL, false, NULL, 'active', 4.6, 22, false, NULL, NULL, '2026-08-18 20:19:55.052757+01', '2026-08-21 14:08:17.481932+01', NULL, NULL, 'basic', '{}', '{}', 60, 'none', 'fixed', 'food_and_drinks', '{}', 'food_truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_trucks VALUES ('7a86447a-804f-4296-aa17-8077d0af3720', NULL, 'la-dolce-vita', 'La Dolce Vita', 'Sabores Italianos Autênticos', 'Pasta fresca, pizzas em forno a lenha e tiramisu caseiro.', 'Lisboa', 50, 100, 30, 500, 950.00, 14.00, 60, NULL, false, NULL, 'active', 4.9, 31, true, NULL, NULL, '2026-08-18 20:19:55.052757+01', '2026-08-21 14:08:17.481932+01', NULL, NULL, 'basic', '{}', '{}', 60, 'none', 'fixed', 'food_and_drinks', '{}', 'food_truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_trucks VALUES ('0e9cf87a-3be5-4184-81d1-116851f7c8da', NULL, 'bbq-kings', 'BBQ Kings', 'Os Mestres do Churrasco', 'Carne fumada lentamente durante 14h, molhos da casa.', 'Algarve', 50, 100, 30, 500, 1100.00, 15.00, 60, NULL, false, NULL, 'active', 4.5, 14, false, NULL, NULL, '2026-08-18 20:19:55.052757+01', '2026-08-21 14:08:17.481932+01', NULL, NULL, 'basic', '{}', '{}', 60, 'none', 'fixed', 'food_and_drinks', '{}', 'food_truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_trucks VALUES ('33009bd1-a1b5-4b42-888c-e9c7c2feaf93', NULL, 'sushi-zen', 'Sushi Zen', 'A excelência da cozinha Japonesa', 'Nigiri, sashimi e uramaki preparados ao momento.', 'Porto', 50, 100, 30, 500, 1050.00, 16.50, 60, NULL, false, NULL, 'active', 4.9, 19, true, NULL, NULL, '2026-08-18 20:19:55.052757+01', '2026-08-21 14:08:17.481932+01', NULL, NULL, 'basic', '{}', '{}', 60, 'none', 'fixed', 'food_and_drinks', '{}', 'food_truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_trucks VALUES ('be683452-c59e-4a95-afd5-7803ddedb982', NULL, 'taco-fiesta', 'Taco Fiesta', 'Sabores mexicanos autênticos', 'Tacos de pastor, cochinita e barbacoa.', 'Lisboa', 50, 100, 30, 500, 820.00, 11.50, 60, NULL, false, NULL, 'active', 4.4, 11, false, NULL, NULL, '2026-08-18 20:19:55.052757+01', '2026-08-21 14:08:17.481932+01', NULL, NULL, 'basic', '{}', '{}', 60, 'none', 'fixed', 'food_and_drinks', '{}', 'food_truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_trucks VALUES ('bc18c7bd-8456-490d-b5b1-2e0cb0abad75', NULL, 'turkish-delights', 'Turkish Delights', 'Autêntica Cozinha Turca', 'Doner kebab, kofta, baklava e chá turco.', 'Lisboa', 50, 100, 30, 500, 760.00, 10.50, 60, NULL, false, NULL, 'active', 4.3, 9, false, NULL, NULL, '2026-08-18 20:19:55.052757+01', '2026-08-21 14:08:17.481932+01', NULL, NULL, 'basic', '{}', '{}', 60, 'none', 'fixed', 'food_and_drinks', '{}', 'food_truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_trucks VALUES ('e0609ef6-64d9-4f37-830d-17f2edea6cb4', NULL, 'portuguese-tradition', 'Portuguese Traditions', 'Sabores Tradicionais', 'Bifanas, francesinhas e pataniscas de bacalhau.', 'Lisboa', 50, 100, 30, 500, 880.00, 12.00, 60, NULL, false, NULL, 'active', 4.8, 24, true, NULL, NULL, '2026-08-18 20:19:55.052757+01', '2026-08-21 14:08:17.481932+01', NULL, NULL, 'basic', '{}', '{}', 60, 'none', 'fixed', 'food_and_drinks', '{}', 'food_truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_trucks VALUES ('2b18813b-d72f-44a4-b724-ce3b1a2d62bf', NULL, 'wok-and-roll', 'Wok & Roll', 'Cozinha Asiática', 'Noodles, dim sum e bao buns recheados.', 'Porto', 50, 80, 30, 500, 720.00, 10.00, 60, NULL, false, NULL, 'active', 4.5, 13, false, NULL, NULL, '2026-08-18 20:19:55.052757+01', '2026-08-21 14:08:17.481932+01', NULL, NULL, 'basic', '{}', '{}', 60, 'none', 'fixed', 'food_and_drinks', '{}', 'food_truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_trucks VALUES ('159248c3-18f0-49e2-896e-f90e7931dc45', NULL, 'pizza-vesuvio', 'Pizza Vesúvio', 'Forno a lenha', 'Pizzas napolitanas com massa de fermentação longa.', 'Lisboa', 50, 120, 30, 500, 990.00, 13.50, 60, NULL, false, NULL, 'active', 4.7, 28, true, NULL, NULL, '2026-08-18 20:19:55.052757+01', '2026-08-21 14:08:17.481932+01', NULL, NULL, 'basic', '{}', '{}', 60, 'none', 'fixed', 'food_and_drinks', '{}', 'food_truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_trucks VALUES ('8c6eb1e6-46a1-4153-b698-4100d4c653e1', NULL, 'creperia-pt', 'Crep''eria', 'Crepes franceses', 'Crepes salgados e doces feitos à frente do cliente.', 'Cascais', 50, 60, 30, 500, 580.00, 9.00, 60, NULL, false, NULL, 'active', 4.6, 16, false, NULL, NULL, '2026-08-18 20:19:55.052757+01', '2026-08-21 14:08:17.481932+01', NULL, NULL, 'basic', '{}', '{}', 60, 'none', 'fixed', 'food_and_drinks', '{}', 'food_truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_blog_categories VALUES (1, 'inspiracao', 'Inspiração');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_blog_categories VALUES (2, 'dicas', 'Dicas');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_blog_categories VALUES (3, 'tendencias', 'Tendências');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_blog_categories VALUES (4, 'casos-de-sucesso', 'Casos de Sucesso');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_blog_posts VALUES ('3c3c333e-8e46-45d9-a9df-6ecf2c8b080e', 'festivais-2025-o-que-ai-vem', NULL, 1, 'Festivais 2025: o que aí vem', 'A nossa selecção de festivais para experimentar este verão.', 'https://images.unsplash.com/photo-1459749411175-04bf5292ceea?w=1400', 'NOS Alive, Primavera Sound, MEO Sudoeste — onde vais comer melhor.', 4, 'published', '2026-07-19 20:19:55.06966+01', NULL, NULL, '2026-08-18 20:19:55.06966+01');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_blog_posts VALUES ('e7f66188-1399-402e-9cac-20ed1b04a953', 'como-organizar-evento-perfeito-food-trucks', NULL, 1, 'Como organizar o evento perfeito com Food Trucks', 'Um guia prático em 7 passos para escolher, contratar e coordenar trucks no teu próximo evento.', 'https://images.unsplash.com/photo-1414235077428-338989a2e8c0?w=1400', '## Passo 1 — Define o tipo de evento\n\nCasamento, festa de empresa ou festival? O tipo de evento define o número de trucks, a variedade de menus e a logística.\n\n## Passo 2 — Estima o número de convidados\n\nUm truck serve em média 80 pessoas/hora. Em eventos com mais de 100 convidados costuma fazer sentido contratar 2 ou 3 trucks complementares.\n\n## Passo 3 — Escolhe os estilos gastronómicos\n\nMistura comida principal + sobremesa + bebida especial. Mexicano + Pizza + Gelado é uma fórmula vencedora.', 6, 'published', '2026-08-17 20:19:55.06966+01', NULL, NULL, '2026-08-18 20:19:55.06966+01');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_blog_posts VALUES ('82d5ef18-a96d-45c6-908d-519b0c9328d2', 'quanto-custa-catering-50-pessoas', NULL, 2, 'Quanto custa um catering com food trucks para 50 pessoas?', 'Calculadora e estimativas reais para te ajudar a planear o orçamento.', 'https://images.unsplash.com/photo-1555244162-803834f70033?w=1400', 'Em média entre 15€ e 25€ por convidado dependendo do tipo de truck.', 3, 'published', '2026-07-28 20:19:55.06966+01', NULL, NULL, '2026-08-18 20:19:55.06966+01');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_blog_posts VALUES ('059d67a2-add9-41e0-9c9e-2385ac099c1f', 'casamentos-food-trucks-5-dicas', NULL, 2, 'Casamentos com Food Trucks: 5 dicas', 'Como integrar trucks numa cerimónia mais formal e impressionar os convidados.', 'https://images.unsplash.com/photo-1519225421980-715cb0215aed?w=1400', '## 1. Loiça vintage\n\nApresentação faz toda a diferença.\n\n## 2. Estações temáticas\n\nUm truck por momento (cocktail, jantar, sobremesa).\n\n## 3. Menu impresso\n\nReforça a experiência sensorial.', 5, 'published', '2026-08-04 20:19:55.06966+01', NULL, NULL, '2026-08-18 20:19:55.06966+01');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_blog_posts VALUES ('325d262a-a7f4-4ac2-b8b1-5d95e9c70e61', 'tendencias-gastronomicas-2025', NULL, 3, 'Tendências gastronómicas para 2025', 'Brunch tudo-o-dia, fermentações, sabores asiáticos e proteína vegetal: o que vai mandar este ano.', 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=1400', '## Brunch all day\n\nA categoria mais procurada para eventos corporativos.\n\n## Sabores asiáticos\n\nBao, ramen e dim sum dominam os street food markets.\n\n## Plant-based\n\nMais de 30% dos eventos pedem opções 100% vegetais.', 4, 'published', '2026-08-11 20:19:55.06966+01', NULL, NULL, '2026-08-18 20:19:55.06966+01');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_service_providers VALUES ('97eb2202-6155-4195-b8b0-7e2ad050c9aa', 'venue', 'Quinta dos Olivais', 'Quinta com 5 hectares, capacidade até 250 pessoas.', 'Sintra', 1800.00, 'https://images.unsplash.com/photo-1464366400600-7168b8af9bc3?w=900', 'reservas@quintaolivais.example', NULL, '2026-08-18 20:19:55.068527+01');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_service_providers VALUES ('b0d8491c-979f-47ec-b88b-2b95c7f73861', 'venue', 'Atrium Industrial', 'Espaço urbano de 600m² no centro do Porto.', 'Porto', 1200.00, 'https://images.unsplash.com/photo-1519167758481-83f550bb49b3?w=900', 'ola@atriumindustrial.example', NULL, '2026-08-18 20:19:55.068527+01');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_service_providers VALUES ('7253efe9-c13b-4c2d-9d6a-958ca8464cdd', 'venue', 'Casa do Mar', 'Salão à beira-mar com terraço, até 120 pessoas.', 'Cascais', 2200.00, 'https://images.unsplash.com/photo-1465495976277-4387d4b0e4a6?w=900', 'eventos@casadomar.example', NULL, '2026-08-18 20:19:55.068527+01');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_service_providers VALUES ('25555afe-400b-4f0b-9ce9-6b6c09a73896', 'entertainment', 'Bumba Music', 'Banda ao vivo (4 elementos) e DJ residente.', 'Lisboa', 900.00, 'https://images.unsplash.com/photo-1501386761578-eac5c94b800a?w=900', 'booking@bumba.example', NULL, '2026-08-18 20:19:55.068527+01');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_service_providers VALUES ('9c87c273-36ba-45fc-a00e-925432f76b1b', 'entertainment', 'DJ Solo Marina', 'DJ residente em festas privadas e casamentos.', 'Lisboa', 450.00, 'https://images.unsplash.com/photo-1493676304819-0d7a8d026dcf?w=900', 'marina@djmarina.example', NULL, '2026-08-18 20:19:55.068527+01');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_service_providers VALUES ('821c88b4-d55e-4a06-afdc-7f05aa019427', 'marketing', 'Curva Studio', 'Landing pages, redes e gestão de campanhas pagas.', 'Lisboa', 600.00, 'https://images.unsplash.com/photo-1432888622747-4eb9a8efeb07?w=900', 'studio@curva.example', NULL, '2026-08-18 20:19:55.068527+01');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_service_providers VALUES ('e5ed2d0f-28fe-448a-8f51-d54d0d70fd19', 'planning', 'PlanIt Eventos', 'Wedding planners e gestão integrada de convidados.', 'Lisboa', 750.00, 'https://images.unsplash.com/photo-1492684223066-81342ee5ff30?w=900', 'planning@planit.example', NULL, '2026-08-18 20:19:55.068527+01');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_service_providers VALUES ('83e3b5ea-b225-4ebc-b707-fa68a73f9c51', 'rental', 'Aluga Tudo', 'Mesas, cadeiras, talheres, lounge, geradores.', 'Porto', 350.00, NULL, 'aluga@alugatudo.example', NULL, '2026-08-18 20:19:55.068527+01');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_categories VALUES (1, 'pizza', 'Pizza', NULL, 'local_pizza');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_categories VALUES (2, 'kebab', 'Kebab', NULL, 'restaurant');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_categories VALUES (3, 'hamburguer', 'Hambúrguer', NULL, 'lunch_dining');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_categories VALUES (4, 'poke', 'Poke', NULL, 'set_meal');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_categories VALUES (5, 'sobremesas', 'Sobremesas', NULL, 'icecream');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_categories VALUES (6, 'pequeno-almoco', 'Pequeno Almoço', NULL, 'free_breakfast');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_categories VALUES (7, 'brunch', 'Brunch', NULL, 'coffee');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_categories VALUES (8, 'tacos', 'Tacos', NULL, 'tapas');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_categories VALUES (9, 'sushi', 'Sushi', NULL, 'rice_bowl');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_categories VALUES (10, 'bbq', 'BBQ', NULL, 'outdoor_grill');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_categories VALUES (11, 'sandwich', 'Sandwich', NULL, 'bakery_dining');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_faqs VALUES (1, 'Que tipos de camiões estão disponíveis?', 'Temos food trucks de várias categorias: hambúrguer, pizza, sushi, tacos, BBQ, sobremesas, brunch e mais. Filtra no catálogo pelo estilo que procuras.', 'reservas', 1);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_faqs VALUES (2, 'Quanto custa alugar um camião de Comida?', 'O preço depende do tipo de truck, número de convidados, duração e localização. Pede uma proposta personalizada à nossa equipa.', 'precos', 2);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_faqs VALUES (3, 'Com quanto tempo de antecedência devo reservar?', 'Recomendamos reservar com pelo menos 3 a 4 semanas de antecedência, sobretudo em épocas altas.', 'reservas', 3);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_faqs VALUES (4, 'Cancelamento de reservas. Como funciona?', 'Cancelamentos até 14 dias antes têm reembolso total; entre 14 e 7 dias 50%; menos de 7 dias não são reembolsáveis.', 'reservas', 4);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_faqs VALUES (5, 'Restrições alimentares ou alergias.', 'A maioria dos trucks oferece opções vegetarianas, veganas e sem glúten. Indica as restrições no formulário de reserva.', 'menus', 5);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_menu_items VALUES ('9417c4eb-e3d7-466c-aa4a-d9648f42f0e2', '44ab71c1-9927-4e9c-89cc-6bd7681b3726', 'Smashburger', 'Carne picada do dia, queijo cheddar fundido e molho da casa.', 9.50, NULL, 'Principais', '{}', 0);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_menu_items VALUES ('36956862-be96-492c-9c2b-c61e508df2d4', 'b98cf4f9-1ad0-4596-9511-da590aaf975e', 'Bowl mediterrânico', 'Quinoa, grão, abóbora assada e tahine de limão.', 10.50, NULL, 'Principais', '{}', 0);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_menu_items VALUES ('f0ba6c78-bef1-4718-ba5d-ab028613fb8b', '11b7b30d-b215-452f-97a2-804a917ecccb', 'Taco al Pastor', 'Porco marinado em achiote, ananás grelhado e coentros.', 4.50, NULL, 'Principais', '{}', 0);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_menu_items VALUES ('3ea74786-849d-403d-992e-75e4edcf96af', '7a86447a-804f-4296-aa17-8077d0af3720', 'Pizza Margherita', 'Tomate San Marzano, mozzarella fior di latte e manjericão.', 11.00, NULL, 'Principais', '{}', 0);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_menu_items VALUES ('53bd5cbc-0027-457e-8681-b24554ebbfaf', '0e9cf87a-3be5-4184-81d1-116851f7c8da', 'Pulled Pork Bun', 'Pá de porco fumada 14h em bun de batata-doce.', 10.50, NULL, 'Principais', '{}', 0);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_menu_items VALUES ('c3c0b042-d2fe-4697-902c-c54c64a5e82c', '33009bd1-a1b5-4b42-888c-e9c7c2feaf93', 'Especial 16 peças', 'Sashimi de salmão, nigiri de atum e uramaki da casa.', 18.00, NULL, 'Principais', '{}', 0);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_menu_items VALUES ('592151c5-50f4-4062-b084-59b5f5eef216', 'be683452-c59e-4a95-afd5-7803ddedb982', 'Burrito Carnitas', 'Tortilha de farinha, porco confitado, arroz e feijão preto.', 9.00, NULL, 'Principais', '{}', 0);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_menu_items VALUES ('545441d3-05f0-48e4-9b66-a99bfbee9e45', 'bc18c7bd-8456-490d-b5b1-2e0cb0abad75', 'Doner kebab', 'Carne de vitela, salada, hummus e iogurte de menta.', 8.50, NULL, 'Principais', '{}', 0);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_menu_items VALUES ('23ac214e-d450-43d1-8987-460a7bc5b35e', 'e0609ef6-64d9-4f37-830d-17f2edea6cb4', 'Bifana especial', 'Lombo de porco em vinha-d''alhos, mostarda e pão estaladiço.', 4.50, NULL, 'Principais', '{}', 0);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_menu_items VALUES ('5bd434bc-1040-489e-8ee5-23af687228de', '2b18813b-d72f-44a4-b724-ce3b1a2d62bf', 'Bao Pork Belly', 'Bao cozido a vapor com barriga de porco glaceada.', 6.50, NULL, 'Principais', '{}', 0);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_menu_items VALUES ('0c641616-27dc-47e9-879b-4eaa4b58afc2', '159248c3-18f0-49e2-896e-f90e7931dc45', 'Pizza Diavola', 'Tomate, mozzarella, salame picante e azeite de chili.', 12.50, NULL, 'Principais', '{}', 0);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_menu_items VALUES ('219cb4db-714e-442c-9fb6-0d07d1d8fa8a', '8c6eb1e6-46a1-4153-b698-4100d4c653e1', 'Crepe Nutella & Banana', 'Crepe fino, Nutella, banana caramelizada e amêndoa.', 5.00, NULL, 'Principais', '{}', 0);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_platform_settings VALUES ('partner_email_venues', '', 'leads', 'Email para onde enviamos leads de "Espaços para Eventos".', false, '2026-08-18 20:20:25.007832+01', NULL);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_platform_settings VALUES ('partner_email_guest_mgmt', '', 'leads', 'Email para leads de "Gestão de Convidados" (3cket).', false, '2026-08-18 20:20:25.007832+01', NULL);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_platform_settings VALUES ('partner_email_music', '', 'leads', 'Email para leads de "Música & Animação".', false, '2026-08-18 20:20:25.007832+01', NULL);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_platform_settings VALUES ('partner_email_marketing', '', 'leads', 'Email para leads de "Marketing & Publicidade".', false, '2026-08-18 20:20:25.007832+01', NULL);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_platform_settings VALUES ('lock_fee.platform_fee', '25', 'lock_fee', 'Quota da plataforma no lock-fee, em €. Default 25.', false, '2026-08-18 20:20:25.070728+01', NULL);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_platform_settings VALUES ('lock_fee.organizer_share', '25', 'lock_fee', 'Quota retida para o organizer no lock-fee, em €. Default 25. Total cobrado ao truck = soma das duas quotas.', false, '2026-08-18 20:20:25.070728+01', NULL);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_platform_settings VALUES ('rate_limit.event_requests_per_day', '10', 'rate_limit', 'Máximo de pedidos de evento que um organizer pode publicar por dia. Default 10.', false, '2026-08-18 20:20:25.070728+01', NULL);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_platform_settings VALUES ('rate_limit.applications_per_day_per_truck', '50', 'rate_limit', 'Máximo de candidaturas que um truck pode submeter por dia. Default 50.', false, '2026-08-18 20:20:25.070728+01', NULL);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_categories VALUES ('159248c3-18f0-49e2-896e-f90e7931dc45', 1);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_categories VALUES ('7a86447a-804f-4296-aa17-8077d0af3720', 1);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_categories VALUES ('bc18c7bd-8456-490d-b5b1-2e0cb0abad75', 2);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_categories VALUES ('44ab71c1-9927-4e9c-89cc-6bd7681b3726', 3);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_categories VALUES ('8c6eb1e6-46a1-4153-b698-4100d4c653e1', 5);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_categories VALUES ('b98cf4f9-1ad0-4596-9511-da590aaf975e', 7);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_categories VALUES ('be683452-c59e-4a95-afd5-7803ddedb982', 8);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_categories VALUES ('11b7b30d-b215-452f-97a2-804a917ecccb', 8);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_categories VALUES ('2b18813b-d72f-44a4-b724-ce3b1a2d62bf', 9);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_categories VALUES ('33009bd1-a1b5-4b42-888c-e9c7c2feaf93', 9);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_categories VALUES ('0e9cf87a-3be5-4184-81d1-116851f7c8da', 10);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_categories VALUES ('e0609ef6-64d9-4f37-830d-17f2edea6cb4', 11);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('e709f1a3-6942-45bf-9695-2d88ad4fbf9c', '44ab71c1-9927-4e9c-89cc-6bd7681b3726', 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=900', 'Divine Burguer''s', 0, true, 'food');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('4867d920-0900-4590-8b72-6b3c5f24d1f5', 'b98cf4f9-1ad0-4596-9511-da590aaf975e', 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=900', 'Gypsy Kitchen', 0, true, 'food');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('8609bb1b-3927-41d7-bcc5-9d4213555335', '11b7b30d-b215-452f-97a2-804a917ecccb', 'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=900', 'El Mexicano', 0, true, 'food');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('4ec087fd-8c72-4764-ae87-e834d8502cc7', '7a86447a-804f-4296-aa17-8077d0af3720', 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=900', 'La Dolce Vita', 0, true, 'food');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('a90f3117-1404-49d0-9f18-4e563d689d0d', '0e9cf87a-3be5-4184-81d1-116851f7c8da', 'https://images.unsplash.com/photo-1529193591184-b1d58069ecdd?w=900', 'BBQ Kings', 0, true, 'food');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('99026643-991c-4d49-9c80-220df1ef1930', '33009bd1-a1b5-4b42-888c-e9c7c2feaf93', 'https://images.unsplash.com/photo-1579871494447-9811cf80d66c?w=900', 'Sushi Zen', 0, true, 'food');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('c8e8c904-1939-49f7-86c9-6f1e69353003', 'be683452-c59e-4a95-afd5-7803ddedb982', 'https://images.unsplash.com/photo-1552332386-f8dd00dc2f85?w=900', 'Taco Fiesta', 0, true, 'food');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('67c759f6-04aa-4c48-b295-1ba277319a5a', 'bc18c7bd-8456-490d-b5b1-2e0cb0abad75', 'https://images.unsplash.com/photo-1561651823-34feb02250e4?w=900', 'Turkish Delights', 0, true, 'food');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('6d53783b-5a7d-4faa-b36c-b1368a32a117', 'e0609ef6-64d9-4f37-830d-17f2edea6cb4', 'https://images.unsplash.com/photo-1432139509613-5c4255815697?w=900', 'Portuguese Traditions', 0, true, 'food');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('789f7b4a-880e-429f-b0a7-44d67a310a1e', '2b18813b-d72f-44a4-b724-ce3b1a2d62bf', 'https://images.unsplash.com/photo-1526318896980-cf78c088247c?w=900', 'Wok & Roll', 0, true, 'food');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('ec88c50a-0c5e-41a5-a962-73258394dc90', '159248c3-18f0-49e2-896e-f90e7931dc45', 'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=900', 'Pizza Vesúvio', 0, true, 'food');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('5693aebe-8479-48e6-bfc5-d0246716ad6d', '8c6eb1e6-46a1-4153-b698-4100d4c653e1', 'https://images.unsplash.com/photo-1519676867240-f03562e64548?w=900', 'Crep''eria', 0, true, 'food');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('41d1c61d-e348-4fbd-865e-dacc4242bcd4', '44ab71c1-9927-4e9c-89cc-6bd7681b3726', '/truck-placeholder.png', 'Divine Burguer''s (truck)', -1, false, 'truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('f461a683-54cb-4688-9201-d42a0d8add8b', 'b98cf4f9-1ad0-4596-9511-da590aaf975e', '/truck-placeholder.png', 'Gypsy Kitchen (truck)', -1, false, 'truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('a18ee8e3-9b9b-42d6-9ced-8d4c5d219ce0', '11b7b30d-b215-452f-97a2-804a917ecccb', '/truck-placeholder.png', 'El Mexicano (truck)', -1, false, 'truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('5d361358-86c4-4f6f-af79-fd67dd4f4d8e', '7a86447a-804f-4296-aa17-8077d0af3720', '/truck-placeholder.png', 'La Dolce Vita (truck)', -1, false, 'truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('75ff68bb-55b4-49bc-96f9-87a3132240e0', '0e9cf87a-3be5-4184-81d1-116851f7c8da', '/truck-placeholder.png', 'BBQ Kings (truck)', -1, false, 'truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('abae1936-7840-4919-9bf3-9f50d6e16ed1', '33009bd1-a1b5-4b42-888c-e9c7c2feaf93', '/truck-placeholder.png', 'Sushi Zen (truck)', -1, false, 'truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('a3ba9c6e-9d18-49d1-894a-8f71b5c1ef55', 'be683452-c59e-4a95-afd5-7803ddedb982', '/truck-placeholder.png', 'Taco Fiesta (truck)', -1, false, 'truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('4e026674-b680-4078-8024-5b324401c459', 'bc18c7bd-8456-490d-b5b1-2e0cb0abad75', '/truck-placeholder.png', 'Turkish Delights (truck)', -1, false, 'truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('659bbecb-399e-4aaa-86d7-12cac360a81e', 'e0609ef6-64d9-4f37-830d-17f2edea6cb4', '/truck-placeholder.png', 'Portuguese Traditions (truck)', -1, false, 'truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('3e0650bf-70d9-492c-8e1a-04d223c487cc', '2b18813b-d72f-44a4-b724-ce3b1a2d62bf', '/truck-placeholder.png', 'Wok & Roll (truck)', -1, false, 'truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('1221f6a6-1ce7-44c4-a149-b8310bbf22f3', '159248c3-18f0-49e2-896e-f90e7931dc45', '/truck-placeholder.png', 'Pizza Vesúvio (truck)', -1, false, 'truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
INSERT INTO public.airfnb_truck_images VALUES ('46f7a678-baf4-4894-b552-507c6bef04a5', '8c6eb1e6-46a1-4153-b698-4100d4c653e1', '/truck-placeholder.png', 'Crep''eria (truck)', -1, false, 'truck');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
SELECT pg_catalog.setval('public.airfnb_audit_log_id_seq', 1, false);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
SELECT pg_catalog.setval('public.airfnb_blog_categories_id_seq', 4, true);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
SELECT pg_catalog.setval('public.airfnb_categories_id_seq', 11, true);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
SELECT pg_catalog.setval('public.airfnb_faqs_id_seq', 5, true);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
create policy airfnb_avatars_owner_delete on storage.objects as PERMISSIVE for DELETE to authenticated using (((bucket_id = 'airfnb-avatars'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND (split_part(name, '/'::text, 1) = (auth.uid())::text) AND (EXISTS ( SELECT 1 FROM public.airfnb_profiles WHERE (airfnb_profiles.id = auth.uid())))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
create policy airfnb_avatars_owner_insert on storage.objects as PERMISSIVE for INSERT to authenticated with check (((bucket_id = 'airfnb-avatars'::text) AND (auth.uid() IS NOT NULL) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND (split_part(name, '/'::text, 1) = (auth.uid())::text) AND (EXISTS ( SELECT 1 FROM public.airfnb_profiles WHERE (airfnb_profiles.id = auth.uid())))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
create policy airfnb_avatars_owner_update on storage.objects as PERMISSIVE for UPDATE to authenticated using (((bucket_id = 'airfnb-avatars'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND (split_part(name, '/'::text, 1) = (auth.uid())::text) AND (EXISTS ( SELECT 1 FROM public.airfnb_profiles WHERE (airfnb_profiles.id = auth.uid()))))) with check (((bucket_id = 'airfnb-avatars'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND (split_part(name, '/'::text, 1) = (auth.uid())::text) AND (EXISTS ( SELECT 1 FROM public.airfnb_profiles WHERE (airfnb_profiles.id = auth.uid())))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
create policy airfnb_avatars_public_read on storage.objects as PERMISSIVE for SELECT to anon, authenticated using ((bucket_id = 'airfnb-avatars'::text));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
create policy airfnb_documents_owner_delete on storage.objects as PERMISSIVE for DELETE to authenticated using (((bucket_id = 'airfnb-documents'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND (EXISTS ( SELECT 1 FROM public.airfnb_profiles WHERE (airfnb_profiles.id = auth.uid()))) AND public.airfnb_can_manage_truck(split_part(name, '/'::text, 1))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
create policy airfnb_documents_owner_insert on storage.objects as PERMISSIVE for INSERT to authenticated with check (((bucket_id = 'airfnb-documents'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND (EXISTS ( SELECT 1 FROM public.airfnb_profiles WHERE (airfnb_profiles.id = auth.uid()))) AND public.airfnb_can_manage_truck(split_part(name, '/'::text, 1))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
create policy airfnb_documents_owner_read on storage.objects as PERMISSIVE for SELECT to authenticated using (((bucket_id = 'airfnb-documents'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND (EXISTS ( SELECT 1 FROM public.airfnb_profiles WHERE (airfnb_profiles.id = auth.uid()))) AND public.airfnb_can_manage_truck(split_part(name, '/'::text, 1))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
create policy airfnb_documents_owner_update on storage.objects as PERMISSIVE for UPDATE to authenticated using (((bucket_id = 'airfnb-documents'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND (EXISTS ( SELECT 1 FROM public.airfnb_profiles WHERE (airfnb_profiles.id = auth.uid()))) AND public.airfnb_can_manage_truck(split_part(name, '/'::text, 1)))) with check (((bucket_id = 'airfnb-documents'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND (EXISTS ( SELECT 1 FROM public.airfnb_profiles WHERE (airfnb_profiles.id = auth.uid()))) AND public.airfnb_can_manage_truck(split_part(name, '/'::text, 1))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
create policy airfnb_truck_images_owner_delete on storage.objects as PERMISSIVE for DELETE to authenticated using (((bucket_id = 'airfnb-truck-images'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND (EXISTS ( SELECT 1 FROM public.airfnb_profiles WHERE (airfnb_profiles.id = auth.uid()))) AND public.airfnb_can_manage_truck(split_part(name, '/'::text, 1))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
create policy airfnb_truck_images_owner_insert on storage.objects as PERMISSIVE for INSERT to authenticated with check (((bucket_id = 'airfnb-truck-images'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND (EXISTS ( SELECT 1 FROM public.airfnb_profiles WHERE (airfnb_profiles.id = auth.uid()))) AND public.airfnb_can_manage_truck(split_part(name, '/'::text, 1))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
create policy airfnb_truck_images_owner_update on storage.objects as PERMISSIVE for UPDATE to authenticated using (((bucket_id = 'airfnb-truck-images'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND (EXISTS ( SELECT 1 FROM public.airfnb_profiles WHERE (airfnb_profiles.id = auth.uid()))) AND public.airfnb_can_manage_truck(split_part(name, '/'::text, 1)))) with check (((bucket_id = 'airfnb-truck-images'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND (EXISTS ( SELECT 1 FROM public.airfnb_profiles WHERE (airfnb_profiles.id = auth.uid()))) AND public.airfnb_can_manage_truck(split_part(name, '/'::text, 1))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
create policy airfnb_truck_images_public_read on storage.objects as PERMISSIVE for SELECT to anon, authenticated using (((bucket_id = 'airfnb-truck-images'::text) AND (name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'::text) AND public.airfnb_can_read_truck_child(split_part(name, '/'::text, 1))));
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types) values
('airfnb-avatars','airfnb-avatars',true,2097152,array['image/jpeg','image/png','image/webp']),
('airfnb-blog-images','airfnb-blog-images',true,2097152,array['image/jpeg','image/png','image/webp']),
('airfnb-documents','airfnb-documents',false,8388608,array['application/pdf']),
('airfnb-menu-images','airfnb-menu-images',true,2097152,array['image/jpeg','image/png','image/webp']),
('airfnb-truck-images','airfnb-truck-images',true,2097152,array['image/jpeg','image/png','image/webp']);
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
alter publication supabase_realtime add table public.airfnb_applications;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
alter publication supabase_realtime add table public.airfnb_bookings;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
alter publication supabase_realtime add table public.airfnb_event_requests;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
alter publication supabase_realtime add table public.airfnb_lock_fees;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
alter publication supabase_realtime add table public.airfnb_messages;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
alter publication supabase_realtime add table public.airfnb_notifications;
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
select cron.schedule('airfnb_expire_lockfees','*/10 * * * *','select public.airfnb_expire_stale_lock_fees();');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
select cron.schedule('airfnb_expire_requests','0 * * * *','select public.airfnb_expire_stale_requests();');
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
create table public.airfnb_baseline_manifest (singleton boolean primary key default true check (singleton), manifest_version text not null, catalog_hash text not null check (catalog_hash ~ '^[0-9a-f]{32}$'), storage_hash text not null check (storage_hash ~ '^[0-9a-f]{32}$'), seed_count bigint not null check (seed_count >= 0), seed_hash text not null check (seed_hash ~ '^[0-9a-f]{32}$'), installed_at timestamptz not null default now());
$indigo_baseline_statement$;

  execute $indigo_baseline_statement$
insert into public.airfnb_baseline_manifest(singleton,manifest_version,catalog_hash,storage_hash,seed_count,seed_hash) values (true,'20260821124724-v1','00000000000000000000000000000000','00000000000000000000000000000000',0,'00000000000000000000000000000000');
$indigo_baseline_statement$;
end
$install$;

do $acl_hardening$
declare
  v_function record;
  v_grant record;
begin
  if pg_catalog.current_setting('airfnb.baseline_mode') = 'final' then
    return;
  end if;

  -- Supabase projects can grant broad table/function privileges through
  -- destination-specific DEFAULT PRIVILEGES. Make the F&B boundary explicit
  -- after object creation, rather than inheriting those project defaults.
  alter table public.airfnb_baseline_manifest enable row level security;
  revoke all on table public.airfnb_baseline_manifest
    from public, anon, authenticated, service_role;

  execute 'alter function public.airfnb_assign_ics_token() set search_path = pg_catalog, public';
  execute 'alter function public.airfnb_event_request_visibility_sync() set search_path = pg_catalog, public';
  execute 'alter function public.airfnb_make_ics_token() set search_path = pg_catalog, public, extensions';
  execute 'alter function public.airfnb_platform_settings_touch() set search_path = pg_catalog, public';

  for v_function in
    select p.oid::pg_catalog.regprocedure as signature
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname like 'airfnb_%'
  loop
    execute pg_catalog.format(
      'revoke all on function %s from public, anon, authenticated, service_role',
      v_function.signature
    );
  end loop;

  for v_grant in
    select pg_catalog.to_regprocedure(grant_row.signature) as signature,
           granted_role.role_name as granted_role
      from (
        values
          ('public.airfnb_accept_application(uuid)', array['authenticated','service_role']::text[]),
          ('public.airfnb_admin_approve_truck(uuid)', array['authenticated']::text[]),
          ('public.airfnb_admin_metrics()', array['authenticated']::text[]),
          ('public.airfnb_admin_pending_trucks(integer)', array['authenticated']::text[]),
          ('public.airfnb_admin_reject_truck(uuid,text)', array['authenticated']::text[]),
          ('public.airfnb_apply_referral(text)', array['authenticated']::text[]),
          ('public.airfnb_booking_by_ics_token(text)', array['anon','authenticated']::text[]),
          ('public.airfnb_booking_service_context(uuid)', array['authenticated']::text[]),
          ('public.airfnb_calculate_lock_fee(uuid)', array['service_role']::text[]),
          ('public.airfnb_can_manage_truck(text)', array['authenticated']::text[]),
          ('public.airfnb_can_read_truck_child(text)', array['anon','authenticated']::text[]),
          ('public.airfnb_can_submit_application(uuid,uuid)', array['authenticated']::text[]),
          ('public.airfnb_check_rate_limit(text,text,integer,integer)', array['service_role']::text[]),
          ('public.airfnb_claim_role(public.airfnb_user_role)', array['authenticated']::text[]),
          ('public.airfnb_conversation_peers()', array['authenticated']::text[]),
          ('public.airfnb_conversation_summaries()', array['authenticated']::text[]),
          ('public.airfnb_ensure_profile(text,text)', array['authenticated']::text[]),
          ('public.airfnb_expire_stale_lock_fees()', array['service_role']::text[]),
          ('public.airfnb_expire_stale_requests()', array['service_role']::text[]),
          ('public.airfnb_find_matching_requests(uuid,integer)', array['authenticated']::text[]),
          ('public.airfnb_find_matching_trucks(uuid,integer)', array['authenticated']::text[]),
          ('public.airfnb_invitation_candidates(uuid)', array['authenticated']::text[]),
          ('public.airfnb_invite_request_services(uuid,uuid[])', array['authenticated']::text[]),
          ('public.airfnb_is_admin()', array['anon','authenticated']::text[]),
          ('public.airfnb_is_truck_owner(text)', array['authenticated']::text[]),
          ('public.airfnb_is_truck_owner(uuid)', array['authenticated']::text[]),
          ('public.airfnb_mark_conversation_read(uuid)', array['authenticated']::text[]),
          ('public.airfnb_match_category_availability_score(uuid,uuid)', array['authenticated']::text[]),
          ('public.airfnb_match_score(uuid,uuid)', array['authenticated']::text[]),
          ('public.airfnb_match_scores_batch(uuid[],uuid[])', array['authenticated']::text[]),
          ('public.airfnb_own_application_truck()', array['authenticated']::text[]),
          ('public.airfnb_private_event_requests(uuid)', array['authenticated']::text[]),
          ('public.airfnb_public_service_detail(text)', array['anon','authenticated']::text[]),
          ('public.airfnb_recommend_trucks_for_request(uuid,integer)', array['authenticated']::text[]),
          ('public.airfnb_reconcile_stripe_event(text,text,timestamp with time zone,uuid,uuid,uuid,text,bigint,text,text,bigint)', array['service_role']::text[]),
          ('public.airfnb_reject_application(uuid,text)', array['authenticated','service_role']::text[]),
          ('public.airfnb_reply_to_organizer_review(uuid,text)', array['authenticated']::text[]),
          ('public.airfnb_reply_to_truck_review(uuid,text)', array['authenticated']::text[]),
          ('public.airfnb_request_application_service_context(uuid)', array['authenticated']::text[]),
          ('public.airfnb_self_delete()', array['authenticated']::text[]),
          ('public.airfnb_self_delete_storage_prefixes()', array['authenticated']::text[]),
          ('public.airfnb_setting_int(text,integer)', array['service_role']::text[]),
          ('public.airfnb_shortlist_application(uuid)', array['authenticated','service_role']::text[]),
          ('public.airfnb_supplier_export_data()', array['authenticated']::text[]),
          ('public.airfnb_supplier_lock_fee(uuid)', array['authenticated']::text[]),
          ('public.airfnb_supplier_services(uuid)', array['authenticated']::text[]),
          ('public.airfnb_truck_is_available(uuid,date,date)', array['anon','authenticated']::text[]),
          ('public.airfnb_user_organizes_request(uuid)', array['anon','authenticated','service_role']::text[]),
          ('public.airfnb_user_owns_invited_truck(uuid)', array['anon','authenticated','service_role']::text[])
      ) grant_row(signature,granted_roles)
      cross join lateral pg_catalog.unnest(grant_row.granted_roles) granted_role(role_name)
  loop
    if v_grant.signature is null then
      raise exception 'indigo baseline failed: function grant target is missing';
    end if;
    execute pg_catalog.format(
      'grant execute on function %s to %I',
      v_grant.signature,
      v_grant.granted_role
    );
  end loop;
end
$acl_hardening$;

do $postconditions$
declare
  v_actual_catalog_hash text;
  v_expected_catalog_hash text;
  v_actual_storage_hash text;
  v_expected_storage_hash text;
  v_actual_seed_count bigint;
  v_expected_seed_count bigint;
  v_actual_seed_hash text;
  v_expected_seed_hash text;
begin
  select pg_catalog.md5(pg_catalog.string_agg(entry, E'\n' order by entry))
    into v_actual_catalog_hash
    from (
      select pg_catalog.jsonb_build_array('relation',c.relname,c.relkind,c.relpersistence,c.relrowsecurity,c.relforcerowsecurity,c.relreplident,pg_catalog.pg_get_userbyid(c.relowner),coalesce(c.relacl::text,''),case when c.relkind in ('v','m') then pg_catalog.pg_get_viewdef(c.oid,true) else '' end)::text as entry
        from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname like 'airfnb_%'
      union all
      select pg_catalog.jsonb_build_array('attribute',c.relname,a.attnum,a.attname,pg_catalog.format_type(a.atttypid,a.atttypmod),a.attnotnull,a.attidentity,a.attgenerated,coalesce(pg_catalog.pg_get_expr(d.adbin,d.adrelid),''),coalesce(a.attacl::text,''))::text
        from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace join pg_catalog.pg_attribute a on a.attrelid=c.oid left join pg_catalog.pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum where n.nspname='public' and c.relname like 'airfnb_%' and a.attnum>0 and not a.attisdropped
      union all
      select pg_catalog.jsonb_build_array('constraint',c.relname,k.conname,k.contype,pg_catalog.pg_get_constraintdef(k.oid,true))::text
        from pg_catalog.pg_constraint k join pg_catalog.pg_class c on c.oid=k.conrelid join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname like 'airfnb_%'
      union all
      select pg_catalog.jsonb_build_array('index',c.relname,pg_catalog.pg_get_indexdef(c.oid))::text
        from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname like 'airfnb_%' and c.relkind='i'
      union all
      select pg_catalog.jsonb_build_array('function',p.proname,pg_catalog.pg_get_function_identity_arguments(p.oid),pg_catalog.pg_get_function_result(p.oid),l.lanname,p.provolatile,p.prosecdef,p.proleakproof,p.proisstrict,p.proparallel,pg_catalog.pg_get_userbyid(p.proowner),coalesce(p.proconfig::text,''),coalesce(p.proacl::text,''),p.prosrc)::text
        from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace join pg_catalog.pg_language l on l.oid=p.prolang where n.nspname='public' and p.proname like 'airfnb_%'
      union all
      select pg_catalog.jsonb_build_array('type',t.typname,t.typtype,t.typcategory,t.typnotnull,pg_catalog.pg_get_userbyid(t.typowner),coalesce(t.typacl::text,''))::text
        from pg_catalog.pg_type t join pg_catalog.pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typname like 'airfnb_%'
      union all
      select pg_catalog.jsonb_build_array('enum',t.typname,e.enumsortorder,e.enumlabel)::text
        from pg_catalog.pg_type t join pg_catalog.pg_namespace n on n.oid=t.typnamespace join pg_catalog.pg_enum e on e.enumtypid=t.oid where n.nspname='public' and t.typname like 'airfnb_%'
      union all
      select pg_catalog.jsonb_build_array('policy',schemaname,tablename,policyname,permissive,roles,cmd,coalesce(qual,''),coalesce(with_check,''))::text
        from pg_catalog.pg_policies where (schemaname='public' or schemaname='storage') and policyname like 'airfnb_%'
      union all
      select pg_catalog.jsonb_build_array('trigger',n.nspname,c.relname,t.tgname,pg_catalog.pg_get_triggerdef(t.oid,true))::text
        from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid=t.tgrelid join pg_catalog.pg_namespace n on n.oid=c.relnamespace where not t.tgisinternal and t.tgname like 'airfnb_%'
      union all
      select pg_catalog.jsonb_build_array('bucket',id,name,public,file_size_limit,allowed_mime_types)::text from storage.buckets where id like 'airfnb-%'
      union all
      select pg_catalog.jsonb_build_array('job',jobname,schedule,command)::text from cron.job where jobname like 'airfnb_%'
      union all
      select pg_catalog.jsonb_build_array('publication',pubname,schemaname,tablename)::text from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename like 'airfnb_%'
    ) manifest_entries;
  select pg_catalog.md5(pg_catalog.string_agg(entry, E'\n' order by entry))
    into v_actual_storage_hash
    from (
      select pg_catalog.jsonb_build_array('bucket',id,name,public,file_size_limit,allowed_mime_types)::text as entry
        from storage.buckets where id like 'airfnb-%'
      union all
      select pg_catalog.jsonb_build_array('policy',schemaname,tablename,policyname,permissive,roles,cmd,coalesce(qual,''),coalesce(with_check,''))::text
        from pg_catalog.pg_policies where schemaname='storage' and policyname like 'airfnb_%'
    ) storage_entries;
  select pg_catalog.count(*),pg_catalog.md5(pg_catalog.string_agg(entry,E'\n' order by entry))
    into v_actual_seed_count,v_actual_seed_hash
    from (
      select pg_catalog.jsonb_build_array('airfnb_blog_categories',pg_catalog.to_jsonb(seed_row))::text as entry from public.airfnb_blog_categories seed_row
      union all select pg_catalog.jsonb_build_array('airfnb_blog_posts',pg_catalog.to_jsonb(seed_row))::text from public.airfnb_blog_posts seed_row
      union all select pg_catalog.jsonb_build_array('airfnb_categories',pg_catalog.to_jsonb(seed_row))::text from public.airfnb_categories seed_row
      union all select pg_catalog.jsonb_build_array('airfnb_faqs',pg_catalog.to_jsonb(seed_row))::text from public.airfnb_faqs seed_row
      union all select pg_catalog.jsonb_build_array('airfnb_menu_items',pg_catalog.to_jsonb(seed_row))::text from public.airfnb_menu_items seed_row
      union all select pg_catalog.jsonb_build_array('airfnb_platform_settings',pg_catalog.to_jsonb(seed_row))::text from public.airfnb_platform_settings seed_row
      union all select pg_catalog.jsonb_build_array('airfnb_service_providers',pg_catalog.to_jsonb(seed_row))::text from public.airfnb_service_providers seed_row
      union all select pg_catalog.jsonb_build_array('airfnb_truck_categories',pg_catalog.to_jsonb(seed_row))::text from public.airfnb_truck_categories seed_row
      union all select pg_catalog.jsonb_build_array('airfnb_truck_images',pg_catalog.to_jsonb(seed_row))::text from public.airfnb_truck_images seed_row
      union all select pg_catalog.jsonb_build_array('airfnb_trucks',pg_catalog.to_jsonb(seed_row))::text from public.airfnb_trucks seed_row
    ) seed_entries;
  if pg_catalog.current_setting('airfnb.baseline_mode') = 'install' then
    update public.airfnb_baseline_manifest
       set catalog_hash=v_actual_catalog_hash,
           storage_hash=v_actual_storage_hash,
           seed_count=v_actual_seed_count,
           seed_hash=v_actual_seed_hash
     where singleton and manifest_version='20260821124724-v1'
       and catalog_hash='00000000000000000000000000000000'
       and storage_hash='00000000000000000000000000000000'
       and seed_count=0
       and seed_hash='00000000000000000000000000000000';
    if not found then
      raise exception 'indigo baseline failed: manifest could not be sealed';
    end if;
  elsif pg_catalog.current_setting('airfnb.baseline_mode') = 'harden' then
    update public.airfnb_baseline_manifest
       set catalog_hash=v_actual_catalog_hash
     where singleton and manifest_version='20260821124724-v1'
       and catalog_hash='c7587da9523bd65c2f30e24073c76eac';
    if not found then
      raise exception 'indigo baseline failed: hardened manifest could not be resealed';
    end if;
  end if;
  select catalog_hash,storage_hash,seed_count,seed_hash
    into v_expected_catalog_hash,v_expected_storage_hash,v_expected_seed_count,v_expected_seed_hash
    from public.airfnb_baseline_manifest
   where singleton and manifest_version='20260821124724-v1';
  if pg_catalog.to_regclass('public.airfnb_baseline_manifest') is null
     or (select count(*) from public.airfnb_baseline_manifest where singleton and manifest_version='20260821124724-v1') <> 1
     or v_expected_catalog_hash is distinct from v_actual_catalog_hash
     or v_expected_storage_hash is distinct from v_actual_storage_hash
     or v_actual_seed_count <> 101
     or v_expected_seed_count <> 101
     or v_expected_seed_hash is distinct from v_actual_seed_hash
     or (select count(*) from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname like 'airfnb_%') <> 169
     or (select count(*) from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname like 'airfnb_%' and c.relkind='r') <> 43
     or (select count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'airfnb_%') <> 68
     or (select count(*) from pg_catalog.pg_policies where schemaname='public' and policyname like 'airfnb_%') <> 67
     or (select count(*) from pg_catalog.pg_trigger where not tgisinternal and tgname like 'airfnb_%') <> 20
     or pg_catalog.to_regclass('public.airfnb_membership_tombstones') is null
     or not (select relrowsecurity from pg_catalog.pg_class where oid='public.airfnb_baseline_manifest'::pg_catalog.regclass)
     or exists (
       select 1
         from (values ('anon'::text),('authenticated'::text),('service_role'::text)) checked_roles(role_name)
         cross join (values ('SELECT'::text),('INSERT'::text),('UPDATE'::text),('DELETE'::text),('TRUNCATE'::text),('REFERENCES'::text),('TRIGGER'::text)) checked_privileges(privilege_name)
        where pg_catalog.has_table_privilege(
          checked_roles.role_name,
          'public.airfnb_baseline_manifest',
          checked_privileges.privilege_name
        )
     )
     or not (select relrowsecurity from pg_catalog.pg_class where oid='public.airfnb_membership_tombstones'::pg_catalog.regclass)
     or exists (select 1 from pg_catalog.pg_policies where schemaname='public' and tablename='airfnb_membership_tombstones')
     or pg_catalog.has_table_privilege('anon','public.airfnb_membership_tombstones','SELECT')
     or pg_catalog.has_table_privilege('authenticated','public.airfnb_membership_tombstones','SELECT')
     or pg_catalog.has_table_privilege('service_role','public.airfnb_membership_tombstones','SELECT')
     or pg_catalog.has_table_privilege('authenticated','public.airfnb_profiles','INSERT')
     or pg_catalog.has_table_privilege('authenticated','public.airfnb_profiles','UPDATE')
     or pg_catalog.has_table_privilege('authenticated','public.airfnb_profiles','DELETE')
     or pg_catalog.has_column_privilege('authenticated','public.airfnb_profiles','role','UPDATE')
     or not pg_catalog.has_column_privilege('authenticated','public.airfnb_profiles','full_name','UPDATE')
     or pg_catalog.has_function_privilege('anon','public.airfnb_ensure_profile(text,text)','EXECUTE')
     or pg_catalog.has_function_privilege('service_role','public.airfnb_ensure_profile(text,text)','EXECUTE')
     or pg_catalog.has_function_privilege('anon','public.airfnb_self_delete()','EXECUTE')
     or pg_catalog.has_function_privilege('service_role','public.airfnb_self_delete()','EXECUTE')
     or pg_catalog.has_function_privilege('anon','public.airfnb_self_delete_storage_prefixes()','EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated','public.airfnb_self_delete_storage_prefixes()','EXECUTE')
     or pg_catalog.has_function_privilege('service_role','public.airfnb_self_delete_storage_prefixes()','EXECUTE')
     or (select count(*)
           from pg_catalog.pg_proc p
           join pg_catalog.pg_namespace n on n.oid=p.pronamespace
           cross join lateral pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
           join pg_catalog.pg_roles r on r.oid=acl.grantee
          where n.nspname='public' and p.proname like 'airfnb_%'
            and acl.privilege_type='EXECUTE' and r.rolname='anon') <> 7
     or (select count(*)
           from pg_catalog.pg_proc p
           join pg_catalog.pg_namespace n on n.oid=p.pronamespace
           cross join lateral pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
           join pg_catalog.pg_roles r on r.oid=acl.grantee
          where n.nspname='public' and p.proname like 'airfnb_%'
            and acl.privilege_type='EXECUTE' and r.rolname='authenticated') <> 43
     or (select count(*)
           from pg_catalog.pg_proc p
           join pg_catalog.pg_namespace n on n.oid=p.pronamespace
           cross join lateral pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
           join pg_catalog.pg_roles r on r.oid=acl.grantee
          where n.nspname='public' and p.proname like 'airfnb_%'
            and acl.privilege_type='EXECUTE' and r.rolname='service_role') <> 11
     or exists (
       select 1
         from pg_catalog.pg_proc p
         join pg_catalog.pg_namespace n on n.oid=p.pronamespace
         cross join lateral pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
        where n.nspname='public' and p.proname like 'airfnb_%'
          and acl.privilege_type='EXECUTE' and acl.grantee=0
     )
     or exists (
       select 1
         from pg_catalog.pg_proc p
         join pg_catalog.pg_namespace n on n.oid=p.pronamespace
        where n.nspname='public'
          and p.proname in ('airfnb_assign_ics_token','airfnb_event_request_visibility_sync','airfnb_make_ics_token','airfnb_platform_settings_touch')
          and p.proconfig is null
     )
     or (select count(*) from pg_catalog.pg_trigger where tgrelid='auth.users'::pg_catalog.regclass and not tgisinternal and tgname like 'airfnb_%') <> 0
     or (select count(*) from pg_catalog.pg_extension where extname in ('pgcrypto','pg_trgm','unaccent','postgis','pg_cron')) <> 5
     or (select count(*) from storage.buckets where id like 'airfnb-%') <> 5
     or (select count(*) from cron.job where jobname like 'airfnb_%') <> 2
     or (select count(*) from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename like 'airfnb_%') <> 6 then
    raise exception 'indigo baseline failed: canonical postconditions are absent';
  end if;
end
$postconditions$;

commit;
