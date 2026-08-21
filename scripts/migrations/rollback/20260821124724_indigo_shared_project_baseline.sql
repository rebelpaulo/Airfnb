-- Selective rollback for the Indigo shared-project F&B baseline.

begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
set local idle_in_transaction_session_timeout='180s';
set local search_path=pg_catalog,public,extensions;

select pg_catalog.pg_advisory_xact_lock(
  1095122502,
  pg_catalog.hashtext('airfnb-indigo-baseline-installer')
);
lock table supabase_migrations.schema_migrations in share mode;

do $preflight$
declare
  v_actual_catalog_hash text;
  v_expected_catalog_hash text;
  v_actual_storage_hash text;
  v_expected_storage_hash text;
begin
  if pg_catalog.to_regclass('public.airfnb_baseline_manifest') is null then
    raise exception 'indigo baseline rollback refused: manifest is absent';
  end if;
  if not exists (
       select 1 from pg_catalog.pg_attribute
        where attrelid=pg_catalog.to_regclass('public.airfnb_baseline_manifest')
          and attname in ('catalog_hash','storage_hash') and not attisdropped
        group by attrelid having count(*)=2
     ) then
    raise exception 'indigo baseline rollback refused: manifest drifted';
  end if;
  begin
    execute 'select catalog_hash,storage_hash from public.airfnb_baseline_manifest where singleton and manifest_version=''20260821124724-v1'' for update'
      into strict v_expected_catalog_hash,v_expected_storage_hash;
  exception
    when no_data_found or too_many_rows then
      raise exception 'indigo baseline rollback refused: manifest drifted';
  end;
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
  if v_expected_storage_hash is null
     or v_actual_storage_hash is distinct from v_expected_storage_hash
     or exists (select 1 from storage.objects where bucket_id like 'airfnb-%')
     or (select count(*) from storage.buckets where id like 'airfnb-%') <> 5
     or (select count(*) from pg_catalog.pg_policies where schemaname='storage' and policyname like 'airfnb_%') <> 12
     or (select count(*) from cron.job where jobname like 'airfnb_%') <> 2
     or exists (select 1 from cron.job where jobname='airfnb_expire_lockfees' and (schedule<>'*/10 * * * *' or command<>'select public.airfnb_expire_stale_lock_fees();'))
     or exists (select 1 from cron.job where jobname='airfnb_expire_requests' and (schedule<>'0 * * * *' or command<>'select public.airfnb_expire_stale_requests();'))
     or exists (select 1 from pg_catalog.pg_trigger where tgrelid='auth.users'::pg_catalog.regclass and not tgisinternal and tgname like 'airfnb_%') then
    raise exception 'indigo baseline rollback refused: manifest, buckets, objects or jobs drifted';
  end if;
  if v_expected_catalog_hash is null
     or v_actual_catalog_hash is distinct from v_expected_catalog_hash then
    raise exception 'indigo baseline rollback refused: catalog drifted';
  end if;
end
$preflight$;

lock table storage.buckets in share row exclusive mode;
lock table storage.objects in share row exclusive mode;
select pg_catalog.pg_advisory_xact_lock(
  1095122502,
  pg_catalog.hashtext('airfnb-indigo-cron-catalog')
);

select cron.unschedule(jobid) from cron.job where jobname in ('airfnb_expire_lockfees','airfnb_expire_requests');

alter publication supabase_realtime drop table
  public.airfnb_applications, public.airfnb_bookings, public.airfnb_event_requests,
  public.airfnb_lock_fees, public.airfnb_messages, public.airfnb_notifications;

drop policy if exists airfnb_avatars_owner_delete on storage.objects;
drop policy if exists airfnb_avatars_owner_insert on storage.objects;
drop policy if exists airfnb_avatars_owner_update on storage.objects;
drop policy if exists airfnb_avatars_public_read on storage.objects;
drop policy if exists airfnb_documents_owner_delete on storage.objects;
drop policy if exists airfnb_documents_owner_insert on storage.objects;
drop policy if exists airfnb_documents_owner_read on storage.objects;
drop policy if exists airfnb_documents_owner_update on storage.objects;
drop policy if exists airfnb_truck_images_owner_delete on storage.objects;
drop policy if exists airfnb_truck_images_owner_insert on storage.objects;
drop policy if exists airfnb_truck_images_owner_update on storage.objects;
drop policy if exists airfnb_truck_images_public_read on storage.objects;

-- Supabase Storage protects direct bucket deletion. The preflight above proves
-- these exact owned buckets contain zero objects; scope the supported bypass to
-- this transaction so no session-level capability survives the rollback.
select pg_catalog.set_config('storage.allow_delete_query','true',true);
delete from storage.buckets where id in ('airfnb-avatars','airfnb-blog-images','airfnb-documents','airfnb-menu-images','airfnb-truck-images');

do $drop_public_relation_controls$
declare
  v_owned_public_tables constant text[] := array[
    'airfnb_addresses','airfnb_applications','airfnb_audit_log','airfnb_blog_authors',
    'airfnb_blog_categories','airfnb_blog_posts','airfnb_booking_addons','airfnb_booking_trucks',
    'airfnb_bookings','airfnb_categories','airfnb_contact_requests','airfnb_conversation_participants',
    'airfnb_conversations','airfnb_event_requests','airfnb_events','airfnb_faqs','airfnb_favorites',
    'airfnb_invoices','airfnb_lock_fees','airfnb_menu_items','airfnb_membership_tombstones','airfnb_messages','airfnb_newsletter_subs',
    'airfnb_newsletter_subscribers','airfnb_notifications','airfnb_organizer_reviews','airfnb_partner_leads',
    'airfnb_payments','airfnb_platform_settings','airfnb_profiles','airfnb_proposals','airfnb_rate_limits',
    'airfnb_request_invitations','airfnb_reviews','airfnb_service_providers','airfnb_stripe_events',
    'airfnb_truck_alert_prefs','airfnb_truck_availability','airfnb_truck_categories',
    'airfnb_truck_documents','airfnb_truck_images','airfnb_trucks','airfnb_baseline_manifest'
  ];
  policy_row record;
  trigger_row record;
begin
  for policy_row in
    select schemaname,tablename,policyname from pg_catalog.pg_policies
     where schemaname='public' and tablename::text=any(v_owned_public_tables)
     order by tablename,policyname
  loop
    execute pg_catalog.format('drop policy %I on %I.%I',policy_row.policyname,policy_row.schemaname,policy_row.tablename);
  end loop;
  for trigger_row in
    select n.nspname,c.relname,t.tgname
      from pg_catalog.pg_trigger t
      join pg_catalog.pg_class c on c.oid=t.tgrelid
      join pg_catalog.pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relname::text=any(v_owned_public_tables) and not t.tgisinternal
     order by c.relname,t.tgname
  loop
    execute pg_catalog.format('drop trigger %I on %I.%I',trigger_row.tgname,trigger_row.nspname,trigger_row.relname);
  end loop;
end
$drop_public_relation_controls$;

drop view public.airfnb_v_booking_full, public.airfnb_v_truck_card;
drop function if exists public.airfnb_accept_application(uuid), public.airfnb_admin_approve_truck(uuid), public.airfnb_admin_metrics(), public.airfnb_admin_pending_trucks(integer), public.airfnb_admin_reject_truck(uuid,text), public.airfnb_applications_rate_limit(), public.airfnb_apply_referral(text), public.airfnb_assign_ics_token(), public.airfnb_assign_referral_code(), public.airfnb_booking_by_ics_token(text), public.airfnb_booking_service_context(uuid), public.airfnb_calculate_lock_fee(uuid), public.airfnb_can_manage_truck(text), public.airfnb_can_read_truck_child(text), public.airfnb_can_submit_application(uuid,uuid), public.airfnb_check_rate_limit(text,text,integer,integer), public.airfnb_claim_role(airfnb_user_role), public.airfnb_conversation_peers(), public.airfnb_conversation_summaries(), public.airfnb_ensure_profile(text,text), public.airfnb_event_request_notify_admins(), public.airfnb_event_request_visibility_sync(), public.airfnb_event_requests_rate_limit(), public.airfnb_expire_stale_lock_fees(), public.airfnb_expire_stale_requests(), public.airfnb_find_matching_requests(uuid,integer), public.airfnb_find_matching_trucks(uuid,integer), public.airfnb_generate_referral_code(), public.airfnb_guard_profile_role(), public.airfnb_guard_truck_moderation(), public.airfnb_invitation_candidates(uuid), public.airfnb_invite_request_services(uuid,uuid[]), public.airfnb_is_admin(), public.airfnb_is_truck_owner(text), public.airfnb_is_truck_owner(uuid), public.airfnb_make_ics_token(), public.airfnb_mark_conversation_read(uuid), public.airfnb_match_category_availability_score(uuid,uuid), public.airfnb_match_score(uuid,uuid), public.airfnb_match_scores_batch(uuid[],uuid[]), public.airfnb_notify_application_received(), public.airfnb_organizer_rating_recompute(), public.airfnb_own_application_truck(), public.airfnb_platform_settings_touch(), public.airfnb_prepare_organizer_review(), public.airfnb_prepare_truck_review(), public.airfnb_private_event_requests(uuid), public.airfnb_public_service_detail(text), public.airfnb_recalc_truck_rating(), public.airfnb_recommend_slots(airfnb_event_kind,integer), public.airfnb_recommend_trucks_for_request(uuid,integer), public.airfnb_reconcile_stripe_event(text,text,timestamp with time zone,uuid,uuid,uuid,text,bigint,text,text,bigint), public.airfnb_reject_application(uuid,text), public.airfnb_reply_to_organizer_review(uuid,text), public.airfnb_reply_to_truck_review(uuid,text), public.airfnb_request_application_service_context(uuid), public.airfnb_self_delete(), public.airfnb_self_delete_storage_prefixes(), public.airfnb_set_recommended_slots(), public.airfnb_setting_int(text,integer), public.airfnb_shortlist_application(uuid), public.airfnb_supplier_export_data(), public.airfnb_supplier_lock_fee(uuid), public.airfnb_supplier_services(uuid), public.airfnb_touch_updated_at(), public.airfnb_truck_is_available(uuid,date,date), public.airfnb_user_organizes_request(uuid), public.airfnb_user_owns_invited_truck(uuid);
drop table public.airfnb_addresses, public.airfnb_applications, public.airfnb_audit_log, public.airfnb_blog_authors, public.airfnb_blog_categories, public.airfnb_blog_posts, public.airfnb_booking_addons, public.airfnb_booking_trucks, public.airfnb_bookings, public.airfnb_categories, public.airfnb_contact_requests, public.airfnb_conversation_participants, public.airfnb_conversations, public.airfnb_event_requests, public.airfnb_events, public.airfnb_faqs, public.airfnb_favorites, public.airfnb_invoices, public.airfnb_lock_fees, public.airfnb_menu_items, public.airfnb_membership_tombstones, public.airfnb_messages, public.airfnb_newsletter_subs, public.airfnb_newsletter_subscribers, public.airfnb_notifications, public.airfnb_organizer_reviews, public.airfnb_partner_leads, public.airfnb_payments, public.airfnb_platform_settings, public.airfnb_profiles, public.airfnb_proposals, public.airfnb_rate_limits, public.airfnb_request_invitations, public.airfnb_reviews, public.airfnb_service_providers, public.airfnb_stripe_events, public.airfnb_truck_alert_prefs, public.airfnb_truck_availability, public.airfnb_truck_categories, public.airfnb_truck_documents, public.airfnb_truck_images, public.airfnb_trucks, public.airfnb_baseline_manifest;
drop type public.airfnb_application_status, public.airfnb_booking_status, public.airfnb_catering_type, public.airfnb_deal_type, public.airfnb_dietary_tag, public.airfnb_discovery_mode, public.airfnb_energy_need, public.airfnb_event_kind, public.airfnb_lock_fee_status, public.airfnb_partner_lead_kind, public.airfnb_payment_direction, public.airfnb_payment_kind, public.airfnb_payment_method, public.airfnb_payment_status, public.airfnb_post_status, public.airfnb_request_status, public.airfnb_sanitation_level, public.airfnb_selection_mode, public.airfnb_service_kind, public.airfnb_service_type, public.airfnb_truck_document_kind, public.airfnb_truck_image_kind, public.airfnb_truck_status, public.airfnb_user_role;

do $postconditions$
declare
  v_owned_public_tables constant text[] := array[
    'airfnb_addresses','airfnb_applications','airfnb_audit_log','airfnb_blog_authors',
    'airfnb_blog_categories','airfnb_blog_posts','airfnb_booking_addons','airfnb_booking_trucks',
    'airfnb_bookings','airfnb_categories','airfnb_contact_requests','airfnb_conversation_participants',
    'airfnb_conversations','airfnb_event_requests','airfnb_events','airfnb_faqs','airfnb_favorites',
    'airfnb_invoices','airfnb_lock_fees','airfnb_menu_items','airfnb_membership_tombstones','airfnb_messages','airfnb_newsletter_subs',
    'airfnb_newsletter_subscribers','airfnb_notifications','airfnb_organizer_reviews','airfnb_partner_leads',
    'airfnb_payments','airfnb_platform_settings','airfnb_profiles','airfnb_proposals','airfnb_rate_limits',
    'airfnb_request_invitations','airfnb_reviews','airfnb_service_providers','airfnb_stripe_events',
    'airfnb_truck_alert_prefs','airfnb_truck_availability','airfnb_truck_categories',
    'airfnb_truck_documents','airfnb_truck_images','airfnb_trucks','airfnb_baseline_manifest'
  ];
  v_owned_storage_policies constant text[] := array[
    'airfnb_avatars_owner_delete','airfnb_avatars_owner_insert','airfnb_avatars_owner_update',
    'airfnb_avatars_public_read','airfnb_documents_owner_delete','airfnb_documents_owner_insert',
    'airfnb_documents_owner_read','airfnb_documents_owner_update','airfnb_truck_images_owner_delete',
    'airfnb_truck_images_owner_insert','airfnb_truck_images_owner_update','airfnb_truck_images_public_read'
  ];
begin
  if exists (select 1 from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname like 'airfnb_%')
     or exists (select 1 from pg_catalog.pg_type t join pg_catalog.pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typname like 'airfnb_%' and t.typtype in ('e','d'))
     or exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'airfnb_%')
     or exists (select 1 from pg_catalog.pg_policies where schemaname='public' and tablename::text=any(v_owned_public_tables))
     or exists (
       select 1 from pg_catalog.pg_policies
        where schemaname='storage' and tablename='objects' and policyname::text=any(v_owned_storage_policies)
     )
     or exists (select 1 from storage.buckets where id like 'airfnb-%')
     or exists (select 1 from cron.job where jobname like 'airfnb_%')
     or exists (select 1 from pg_catalog.pg_publication_tables where pubname='supabase_realtime' and tablename like 'airfnb_%')
     or exists (
       select 1
         from pg_catalog.pg_trigger t
         join pg_catalog.pg_class c on c.oid=t.tgrelid
         join pg_catalog.pg_namespace n on n.oid=c.relnamespace
        where n.nspname='public' and c.relname::text=any(v_owned_public_tables) and not t.tgisinternal
     )
     or exists (select 1 from pg_catalog.pg_trigger where tgrelid='auth.users'::pg_catalog.regclass and not tgisinternal and tgname like 'airfnb_%') then
    raise exception 'indigo baseline rollback failed: F&B residue remains';
  end if;
  if (select count(*) from pg_catalog.pg_extension where extname in ('pgcrypto','pg_trgm','unaccent','postgis','pg_cron')) <> 5 then
    raise exception 'indigo baseline rollback failed: shared extension capability changed';
  end if;
end
$postconditions$;

commit;
