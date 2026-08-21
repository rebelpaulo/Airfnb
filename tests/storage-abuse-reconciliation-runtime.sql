\set ON_ERROR_STOP on

select pg_catalog.set_config(
  'storage.runtime_database',
  :'storage_runtime_database',
  false
);

select :'storage_runtime_phase' = 'reconstruct_historical' as storage_is_reconstruct,
       :'storage_runtime_phase' = 'setup' as storage_is_setup,
       :'storage_runtime_phase' = 'assert_pre_historical' as storage_is_pre_historical,
       :'storage_runtime_phase' = 'assert_pre_old' as storage_is_pre_old,
       :'storage_runtime_phase' = 'assert_good' as storage_is_good
\gset

\if :storage_is_reconstruct
begin;

do $identity$
begin
  if pg_catalog.current_database() <> pg_catalog.current_setting('storage.runtime_database')
     or pg_catalog.current_database() !~ '^fb_tailor_storage_[0-9]+_[0-9]+_(historical|old)$' then
    raise exception 'storage runtime refused: unsafe historical clone identity';
  end if;
end
$identity$;

drop policy "airfnb_truck_images_read" on public.airfnb_truck_images;
create policy "airfnb_truck_images_read"
  on public.airfnb_truck_images for select using (true);
drop policy "airfnb_menu_items_read" on public.airfnb_menu_items;
create policy "airfnb_menu_items_read"
  on public.airfnb_menu_items for select using (true);
drop policy "airfnb_truck_cat_read" on public.airfnb_truck_categories;
create policy "airfnb_truck_cat_read"
  on public.airfnb_truck_categories for select using (true);

drop policy "airfnb_truck_images_public_read" on storage.objects;
create policy "airfnb_truck_images_public_read"
  on storage.objects for select
  using (bucket_id = 'airfnb-truck-images');

drop function public.airfnb_can_read_truck_child(text);
drop function if exists public.airfnb_can_manage_truck(text);

update storage.buckets
   set file_size_limit = null,
       allowed_mime_types = null
 where id like 'airfnb-%';

alter table public.airfnb_rate_limits disable row level security;
drop index if exists public.airfnb_rate_limits_window_at_idx;
alter table public.airfnb_rate_limits
  drop constraint if exists airfnb_rate_limits_action_format,
  drop constraint if exists airfnb_rate_limits_bucket_format,
  drop constraint if exists airfnb_rate_limits_count_range;
revoke all on table public.airfnb_rate_limits from service_role;

create or replace function public.airfnb_check_rate_limit(
  p_action text,
  p_bucket text,
  p_limit_per_window integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_count int;
  v_window_at timestamptz;
begin
  insert into public.airfnb_rate_limits (action, bucket, count, window_at)
  values (p_action, p_bucket, 1, now())
  on conflict (action, bucket) do update
    set count = case
      when public.airfnb_rate_limits.window_at
             < now() - (p_window_seconds || ' seconds')::interval
        then 1
      else public.airfnb_rate_limits.count + 1
    end,
    window_at = case
      when public.airfnb_rate_limits.window_at
             < now() - (p_window_seconds || ' seconds')::interval
        then now()
      else public.airfnb_rate_limits.window_at
    end
  returning count, window_at into v_count, v_window_at;

  return v_count <= p_limit_per_window;
end
$function$;

revoke execute on function public.airfnb_check_rate_limit(text, text, integer, integer)
  from public, anon, authenticated, service_role;

create policy airfnb_partner_leads_insert
  on public.airfnb_partner_leads for insert with check (true);
create policy "airfnb_newsletter_anyone_insert"
  on public.airfnb_newsletter_subs for insert with check (true);
create policy "airfnb_newsletter_insert_any"
  on public.airfnb_newsletter_subscribers for insert with check (true);
create policy "airfnb_contact_insert_any"
  on public.airfnb_contact_requests for insert with check (true);

grant insert on table public.airfnb_partner_leads,
  public.airfnb_newsletter_subs,
  public.airfnb_newsletter_subscribers,
  public.airfnb_contact_requests
  to anon, authenticated;

revoke all on table public.airfnb_partner_leads from service_role;
revoke all on table public.airfnb_newsletter_subs from service_role;
revoke all on table public.airfnb_newsletter_subscribers from service_role;
revoke all on table public.airfnb_contact_requests from service_role;

commit;
\endif

\if :storage_is_setup
begin;

do $identity$
begin
  if pg_catalog.current_database() <> pg_catalog.current_setting('storage.runtime_database')
     or pg_catalog.current_database() !~ '^fb_tailor_storage_[0-9]+_[0-9]+_(historical|old)$'
     or exists (
       select 1 from auth.users where id::text like 'f2600000-0000-4000-8000-%'
     ) then
    raise exception 'storage runtime refused: unsafe clone or fixture collision';
  end if;
end
$identity$;

insert into auth.users (id, email, raw_user_meta_data)
values
  ('f2600000-0000-4000-8000-000000000001', 'storage-owner@example.invalid', '{"full_name":"Storage Owner"}'::jsonb),
  ('f2600000-0000-4000-8000-000000000002', 'storage-unrelated@example.invalid', '{"full_name":"Storage Unrelated"}'::jsonb),
  ('f2600000-0000-4000-8000-000000000003', 'storage-admin@example.invalid', '{"full_name":"Storage Admin"}'::jsonb);

update public.airfnb_profiles
   set role = case id
     when 'f2600000-0000-4000-8000-000000000001' then 'owner'::public.airfnb_user_role
     when 'f2600000-0000-4000-8000-000000000003' then 'admin'::public.airfnb_user_role
     else 'organizer'::public.airfnb_user_role
   end
 where id::text like 'f2600000-0000-4000-8000-%';

insert into public.airfnb_trucks (
  id, owner_id, slug, name, status, capacity, rating_avg, featured, base_price
)
values
  ('f2600000-0000-4000-8000-000000000010', 'f2600000-0000-4000-8000-000000000001', 'storage-active', 'Storage Active', 'active', 100, 4.5, false, 500),
  ('f2600000-0000-4000-8000-000000000011', 'f2600000-0000-4000-8000-000000000001', 'storage-draft', 'Storage Draft', 'draft', 100, 4.5, false, 500),
  ('f2600000-0000-4000-8000-000000000012', 'f2600000-0000-4000-8000-000000000002', 'storage-unrelated', 'Storage Unrelated', 'draft', 100, 4.5, false, 500);

insert into public.airfnb_categories (id, slug, name_pt, name_en)
values
  (9260, 'storage-runtime-one', 'Storage runtime one', 'Storage runtime one'),
  (9261, 'storage-runtime-two', 'Storage runtime two', 'Storage runtime two');

insert into public.airfnb_truck_images (id, truck_id, url, alt, is_cover)
values
  ('f2600000-0000-4000-8000-000000000020', 'f2600000-0000-4000-8000-000000000010', '/storage/active.jpg', 'Active', true),
  ('f2600000-0000-4000-8000-000000000021', 'f2600000-0000-4000-8000-000000000011', '/storage/draft.jpg', 'Draft', true);
insert into public.airfnb_menu_items (id, truck_id, name, price)
values
  ('f2600000-0000-4000-8000-000000000030', 'f2600000-0000-4000-8000-000000000010', 'Active menu', 10),
  ('f2600000-0000-4000-8000-000000000031', 'f2600000-0000-4000-8000-000000000011', 'Draft menu', 10);
insert into public.airfnb_truck_categories (truck_id, category_id)
values
  ('f2600000-0000-4000-8000-000000000010', 9260),
  ('f2600000-0000-4000-8000-000000000011', 9260);

insert into storage.objects (id, bucket_id, name, owner)
values
  ('f2600000-0000-4000-8000-000000000040', 'airfnb-truck-images', 'f2600000-0000-4000-8000-000000000010/active.jpg', 'f2600000-0000-4000-8000-000000000001'),
  ('f2600000-0000-4000-8000-000000000041', 'airfnb-truck-images', 'f2600000-0000-4000-8000-000000000011/draft.jpg', 'f2600000-0000-4000-8000-000000000001'),
  ('f2600000-0000-4000-8000-000000000042', 'airfnb-documents', 'f2600000-0000-4000-8000-000000000011/compliance.pdf', 'f2600000-0000-4000-8000-000000000001'),
  ('f2600000-0000-4000-8000-000000000043', 'airfnb-avatars', 'f2600000-0000-4000-8000-000000000001/avatar.jpg', 'f2600000-0000-4000-8000-000000000001');

commit;
\endif

\if :storage_is_pre_historical
begin;
grant select on public.airfnb_truck_images, public.airfnb_menu_items,
  public.airfnb_truck_categories to anon;
set local role anon;
select pg_catalog.count(*) as draft_images
  from public.airfnb_truck_images
 where truck_id = 'f2600000-0000-4000-8000-000000000011'
\gset historical_
insert into public.airfnb_partner_leads (kind, name, email)
values ('venues', 'Historical leak', 'historical@example.invalid');
insert into public.airfnb_newsletter_subs (email)
values ('historical-subs@example.invalid');
insert into public.airfnb_newsletter_subscribers (email)
values ('historical-subscriber@example.invalid');
insert into public.airfnb_contact_requests (name, email)
values ('Historical contact', 'historical-contact@example.invalid');
reset role;
select :'historical_draft_images'::integer = 1
       and (select pg_catalog.bool_and(file_size_limit is null and allowed_mime_types is null)
              from storage.buckets where id like 'airfnb-%')
       as historical_preproof_ok
\gset
\if :historical_preproof_ok
\else
select 1 / 0 as historical_preproof_failed;
\endif
rollback;
\endif

\if :storage_is_pre_old
begin;
insert into public.airfnb_rate_limits (action, bucket, count, window_at)
values ('storage_overflow_probe', 'probe', 2147483647, pg_catalog.statement_timestamp());
do $overflow$
declare
  v_saw_overflow boolean := false;
begin
  begin
    perform public.airfnb_check_rate_limit('storage_overflow_probe', 'probe', 10000, 60);
  exception when numeric_value_out_of_range then
    v_saw_overflow := true;
  end;
  if not v_saw_overflow then
    raise exception 'old-candidate overflow did not reproduce';
  end if;
end
$overflow$;

select pg_catalog.set_config('request.jwt.claim.sub', 'f2600000-0000-4000-8000-000000000003', true);
select not public.airfnb_is_truck_owner('f2600000-0000-4000-8000-000000000011'::uuid)
       and (select pg_catalog.bool_and(file_size_limit is not null and allowed_mime_types is not null)
              from storage.buckets where id like 'airfnb-%')
       and exists (
         select 1 from pg_catalog.pg_policy
          where polrelid = 'public.airfnb_truck_images'::pg_catalog.regclass
            and polname = 'airfnb_truck_images_write'
            and polwithcheck is null
       ) as old_preproof_ok
\gset
\if :old_preproof_ok
\else
select 1 / 0 as old_preproof_failed;
\endif
rollback;
\endif

\if :storage_is_good
do $catalog_and_metadata$
declare
  v_anon oid := (select oid from pg_catalog.pg_roles where rolname = 'anon');
  v_authenticated oid := (select oid from pg_catalog.pg_roles where rolname = 'authenticated');
  v_service oid := (select oid from pg_catalog.pg_roles where rolname = 'service_role');
begin
  if exists (
    select 1
      from pg_catalog.pg_attribute as attribute
      cross join lateral pg_catalog.aclexplode(attribute.attacl) as acl
     where attribute.attrelid in (
       'public.airfnb_trucks'::pg_catalog.regclass,
       'public.airfnb_truck_images'::pg_catalog.regclass,
       'public.airfnb_menu_items'::pg_catalog.regclass,
       'public.airfnb_truck_categories'::pg_catalog.regclass
       )
       and attribute.attnum > 0 and not attribute.attisdropped
       and acl.privilege_type = 'SELECT'
       and acl.grantee in (0, v_anon, v_authenticated)
  ) then
    raise exception 'storage runtime failed: catalog base-column grant appeared';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_indexes
     where schemaname = 'public' and tablename = 'airfnb_rate_limits'
       and indexname = 'airfnb_rate_limits_window_at_idx'
  ) or (select pg_catalog.count(*) from pg_catalog.pg_constraint
         where conrelid = 'public.airfnb_rate_limits'::pg_catalog.regclass) <> 4
     or exists (select 1 from pg_catalog.pg_policy
                 where polrelid = 'public.airfnb_rate_limits'::pg_catalog.regclass)
     or pg_catalog.has_table_privilege(v_service, 'public.airfnb_rate_limits', 'SELECT')
     or pg_catalog.has_table_privilege(v_service, 'public.airfnb_rate_limits', 'INSERT')
     or pg_catalog.has_table_privilege(v_service, 'public.airfnb_rate_limits', 'UPDATE')
     or pg_catalog.has_table_privilege(v_service, 'public.airfnb_rate_limits', 'DELETE') then
    raise exception 'storage runtime failed: rate-limit metadata';
  end if;

  if not pg_catalog.has_table_privilege(v_service, 'public.airfnb_partner_leads', 'INSERT')
     or not pg_catalog.has_table_privilege(v_service, 'public.airfnb_newsletter_subs', 'SELECT')
     or not pg_catalog.has_table_privilege(v_service, 'public.airfnb_newsletter_subs', 'INSERT')
     or not pg_catalog.has_table_privilege(v_service, 'public.airfnb_newsletter_subs', 'UPDATE')
     or not pg_catalog.has_table_privilege(v_service, 'public.airfnb_newsletter_subscribers', 'INSERT')
     or not pg_catalog.has_table_privilege(v_service, 'public.airfnb_contact_requests', 'INSERT') then
    raise exception 'storage runtime failed: service ingestion grants';
  end if;
end
$catalog_and_metadata$;

begin;
grant select, insert, update, delete on public.airfnb_truck_images,
  public.airfnb_menu_items, public.airfnb_truck_categories to anon, authenticated;
grant select, insert, update, delete on storage.objects to anon, authenticated;
create temporary table storage_runtime_checks (
  assertion_order integer primary key,
  assertion text not null unique,
  actual bigint not null,
  expected bigint not null
) on commit drop;

set local role anon;
select pg_catalog.count(*) filter (where truck_id = 'f2600000-0000-4000-8000-000000000010') as active,
       pg_catalog.count(*) filter (where truck_id = 'f2600000-0000-4000-8000-000000000011') as draft
  from public.airfnb_truck_images
\gset anon_child_
select pg_catalog.count(*) filter (where name like 'f2600000-0000-4000-8000-000000000010/%') as active,
       pg_catalog.count(*) filter (where name like 'f2600000-0000-4000-8000-000000000011/%') as draft
  from storage.objects
 where bucket_id = 'airfnb-truck-images'
\gset anon_object_
reset role;
insert into storage_runtime_checks values
  (10, 'anon_child_active', :'anon_child_active', 1),
  (11, 'anon_child_draft', :'anon_child_draft', 0),
  (12, 'anon_object_active', :'anon_object_active', 1),
  (13, 'anon_object_draft', :'anon_object_draft', 0);

select pg_catalog.set_config('request.jwt.claim.sub', 'f2600000-0000-4000-8000-000000000002', true);
set local role authenticated;
select pg_catalog.count(*) filter (where truck_id = 'f2600000-0000-4000-8000-000000000010') as active,
       pg_catalog.count(*) filter (where truck_id = 'f2600000-0000-4000-8000-000000000011') as draft
  from public.airfnb_menu_items
\gset unrelated_child_
reset role;
insert into storage_runtime_checks values
  (20, 'unrelated_child_active', :'unrelated_child_active', 1),
  (21, 'unrelated_child_draft', :'unrelated_child_draft', 0);

select pg_catalog.set_config('request.jwt.claim.sub', 'f2600000-0000-4000-8000-000000000001', true);
set local role authenticated;
select pg_catalog.count(*) filter (where truck_id = 'f2600000-0000-4000-8000-000000000010') as active,
       pg_catalog.count(*) filter (where truck_id = 'f2600000-0000-4000-8000-000000000011') as draft
  from public.airfnb_truck_categories
\gset owner_child_
select pg_catalog.count(*) as documents from storage.objects where bucket_id = 'airfnb-documents'
\gset owner_
reset role;
insert into storage_runtime_checks values
  (30, 'owner_child_active_before_write', :'owner_child_active', 1),
  (31, 'owner_child_draft_before_write', :'owner_child_draft', 1),
  (32, 'owner_documents_before_write', :'owner_documents', 1);
set local role authenticated;
insert into public.airfnb_truck_images (truck_id, url)
values ('f2600000-0000-4000-8000-000000000011', '/storage/owner-write.jpg');
insert into public.airfnb_menu_items (truck_id, name)
values ('f2600000-0000-4000-8000-000000000011', 'Owner write');
insert into public.airfnb_truck_categories (truck_id, category_id)
values ('f2600000-0000-4000-8000-000000000011', 9261);
insert into storage.objects (bucket_id, name, owner)
values
  ('airfnb-truck-images', 'f2600000-0000-4000-8000-000000000011/owner.jpg', 'f2600000-0000-4000-8000-000000000001'),
  ('airfnb-documents', 'f2600000-0000-4000-8000-000000000011/owner.pdf', 'f2600000-0000-4000-8000-000000000001'),
  ('airfnb-avatars', 'f2600000-0000-4000-8000-000000000001/owner-avatar.jpg', 'f2600000-0000-4000-8000-000000000001');
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', 'f2600000-0000-4000-8000-000000000003', true);
set local role authenticated;
select pg_catalog.count(*) as draft from public.airfnb_truck_images
 where truck_id = 'f2600000-0000-4000-8000-000000000011'
\gset admin_child_
select pg_catalog.count(*) as documents from storage.objects where bucket_id = 'airfnb-documents'
\gset admin_
reset role;
insert into storage_runtime_checks values
  (40, 'admin_child_draft_after_owner_write', :'admin_child_draft', 2),
  (41, 'admin_documents_after_owner_write', :'admin_documents', 2);
set local role authenticated;
insert into public.airfnb_menu_items (truck_id, name)
values ('f2600000-0000-4000-8000-000000000010', 'Admin write');
insert into storage.objects (bucket_id, name, owner)
values ('airfnb-documents', 'f2600000-0000-4000-8000-000000000010/admin.pdf', 'f2600000-0000-4000-8000-000000000003');
reset role;

insert into storage_runtime_checks
select * from (values
  (50, 'owner_child_image_insert_delta',
    (select pg_catalog.count(*) from public.airfnb_truck_images where url = '/storage/owner-write.jpg'), 1::bigint),
  (51, 'owner_child_menu_insert_delta',
    (select pg_catalog.count(*) from public.airfnb_menu_items where name = 'Owner write'), 1::bigint),
  (52, 'owner_child_category_insert_delta',
    (select pg_catalog.count(*) from public.airfnb_truck_categories where category_id = 9261), 1::bigint),
  (53, 'owner_storage_truck_image_insert_delta',
    (select pg_catalog.count(*) from storage.objects where name like '%/owner.jpg'), 1::bigint),
  (54, 'owner_storage_document_insert_delta',
    (select pg_catalog.count(*) from storage.objects where name like '%/owner.pdf'), 1::bigint),
  (55, 'owner_storage_avatar_insert_delta',
    (select pg_catalog.count(*) from storage.objects where name like '%/owner-avatar.jpg'), 1::bigint),
  (60, 'admin_child_menu_insert_delta',
    (select pg_catalog.count(*) from public.airfnb_menu_items where name = 'Admin write'), 1::bigint),
  (61, 'admin_storage_document_insert_delta',
    (select pg_catalog.count(*) from storage.objects where name like '%/admin.pdf'), 1::bigint)
) as expected(assertion_order, assertion, actual, expected);

do $named_assertions$
declare
  v_check record;
begin
  for v_check in
    select assertion, actual, expected
      from storage_runtime_checks
     order by assertion_order
  loop
    if v_check.actual <> v_check.expected then
      raise exception 'storage runtime assertion failed: % actual=% expected=%',
        v_check.assertion, v_check.actual, v_check.expected;
    end if;
  end loop;
end
$named_assertions$;
rollback;

begin;
insert into public.airfnb_rate_limits (action, bucket, count, window_at)
values
  ('storage_reset_probe', 'reset', 9, pg_catalog.statement_timestamp() - interval '61 seconds'),
  ('storage_saturation_probe', 'saturation', 2147483647, pg_catalog.statement_timestamp()),
  ('storage_prune_stale', 'stale', 1, pg_catalog.statement_timestamp() - interval '32 days');
set local role service_role;
select public.airfnb_check_rate_limit('storage_reset_probe', 'reset', 10, 60) as reset_allowed,
       public.airfnb_check_rate_limit('storage_saturation_probe', 'saturation', 10000, 86400) as saturation_allowed,
       public.airfnb_check_rate_limit('storage_prune_fresh', 'fresh', 1, 60) as prune_allowed
\gset rate_
select public.airfnb_check_rate_limit('storage_once', 'once', 1, 60) as first_allowed
\gset rate_
select public.airfnb_check_rate_limit('storage_once', 'once', 1, 60) as second_allowed
\gset rate_
reset role;
select count as reset_count from public.airfnb_rate_limits
 where action = 'storage_reset_probe' and bucket = 'reset'
\gset rate_
select count as saturation_count from public.airfnb_rate_limits
 where action = 'storage_saturation_probe' and bucket = 'saturation'
\gset rate_
select pg_catalog.count(*) as stale_count from public.airfnb_rate_limits
 where action = 'storage_prune_stale'
\gset rate_
select :'rate_reset_allowed'::boolean
       and not :'rate_saturation_allowed'::boolean
       and :'rate_prune_allowed'::boolean
       and :'rate_first_allowed'::boolean
       and not :'rate_second_allowed'::boolean
       and :'rate_reset_count'::integer = 1
       and :'rate_saturation_count'::integer = 2147483647
       and :'rate_stale_count'::integer = 0
       as rate_limit_runtime_ok
\gset
\if :rate_limit_runtime_ok
\else
select 1 / 0 as rate_limit_runtime_failed;
\endif
rollback;

select public.airfnb_can_read_truck_child('not-a-uuid') is false as malformed_read_false
\gset
select pg_catalog.set_config('request.jwt.claim.sub', 'f2600000-0000-4000-8000-000000000001', false);
select public.airfnb_can_manage_truck('not-a-uuid') is false as malformed_manage_false
\gset
select :'malformed_read_false'::boolean and :'malformed_manage_false'::boolean
       as malformed_helpers_ok
\gset
\if :malformed_helpers_ok
\else
select 1 / 0 as malformed_helpers_failed;
\endif
\endif
