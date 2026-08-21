\set ON_ERROR_STOP on

select pg_catalog.set_config('catalog.runtime_database', :'catalog_runtime_database', false);

select :'catalog_runtime_phase' = 'reconstruct_legacy' as catalog_is_reconstruct,
       :'catalog_runtime_phase' = 'assert_pre_legacy' as catalog_is_pre_legacy,
       :'catalog_runtime_phase' = 'assert_pre_old' as catalog_is_pre_old,
       :'catalog_runtime_phase' = 'assert_good' as catalog_is_good
\gset

do $privacy_dependency$
declare
  v_owner oid := (
    select relation.relowner
      from pg_catalog.pg_class as relation
     where relation.oid = 'public.airfnb_trucks'::pg_catalog.regclass
  );
  v_expected_grantees oid[] := array[
    (select oid from pg_catalog.pg_roles where rolname = 'anon'),
    (select oid from pg_catalog.pg_roles where rolname = 'authenticated'),
    v_owner
  ]::oid[];
begin
  if pg_catalog.current_database() <> pg_catalog.current_setting('catalog.runtime_database')
     or (
       select pg_catalog.count(*)
         from pg_catalog.pg_proc as procedure
         join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
        where namespace.nspname = 'public'
          and procedure.proname = 'airfnb_is_admin'
     ) <> 1
     or not exists (
       select 1
         from pg_catalog.pg_proc as procedure
        where procedure.oid = 'public.airfnb_is_admin()'::pg_catalog.regprocedure
          and procedure.proowner = v_owner
          and procedure.prosecdef
          and procedure.provolatile = 's'
          and procedure.proconfig = array['search_path=""']::text[]
          and pg_catalog.md5(procedure.prosrc) = 'aa950c573de3ffe4835f7851c09a0631'
          and procedure.proacl is not null
          and not exists (
            select 1
              from pg_catalog.aclexplode(procedure.proacl) as privilege
             where privilege.grantor <> v_owner
                or privilege.privilege_type <> 'EXECUTE'
                or privilege.is_grantable
          )
          and (
            select pg_catalog.array_agg(privilege.grantee order by privilege.grantee)
              from pg_catalog.aclexplode(procedure.proacl) as privilege
          ) = (
            select pg_catalog.array_agg(grantee order by grantee)
              from pg_catalog.unnest(v_expected_grantees) as grantee
          )
     ) then
    raise exception 'catalog runtime failed: privacy-final is_admin contract differs';
  end if;
end
$privacy_dependency$;

\if :catalog_is_reconstruct
begin;
do $identity$
begin
  if pg_catalog.current_database() <> pg_catalog.current_setting('catalog.runtime_database')
     or pg_catalog.current_database() !~ '^fb_tailor_catalog_[0-9]+_[0-9]+_(legacy|old)$' then
    raise exception 'catalog runtime refused: unsafe legacy clone identity';
  end if;
end
$identity$;

drop view public.airfnb_v_truck_card;
create view public.airfnb_v_truck_card with (security_invoker = true) as
select
  truck.id, truck.slug, truck.name, truck.tagline, truck.base_city,
  truck.capacity, truck.base_price, truck.price_per_pax,
  truck.min_event_pax, truck.max_event_pax, truck.service_radius_km,
  truck.cuisine_types, truck.dietary_options, truck.catering_type,
  truck.serves, truck.setup_minutes, truck.teardown_minutes,
  truck.power_required_kw, truck.sanitation_required,
  truck.compatible_event_kinds, truck.rating_avg, truck.rating_count,
  truck.featured, truck.status,
  (
    select image.url
      from public.airfnb_truck_images as image
     where image.truck_id = truck.id
     order by
       case image.kind
         when 'truck' then 1 when 'food' then 2 when 'venue' then 3
         when 'team' then 4 else 5
       end,
       case when image.is_cover then 0 else 1 end,
       image.sort_order
     limit 1
  ) as cover_url,
  (
    select pg_catalog.array_agg(
             ordered_image.url
             order by ordered_image.kind_rank,
                      ordered_image.is_cover_rank,
                      ordered_image.sort_order
           )
      from (
        select image.url,
          case image.kind
            when 'truck' then 1 when 'food' then 2 when 'venue' then 3
            when 'team' then 4 else 5
          end as kind_rank,
          case when image.is_cover then 0 else 1 end as is_cover_rank,
          image.sort_order
        from public.airfnb_truck_images as image
        where image.truck_id = truck.id
        order by
          case image.kind
            when 'truck' then 1 when 'food' then 2 when 'venue' then 3
            when 'team' then 4 else 5
          end,
          case when image.is_cover then 0 else 1 end,
          image.sort_order
        limit 6
      ) as ordered_image
  ) as gallery_urls,
  array(
    select category.slug
      from public.airfnb_truck_categories as truck_category
      join public.airfnb_categories as category
        on category.id = truck_category.category_id
     where truck_category.truck_id = truck.id
  ) as category_slugs
from public.airfnb_trucks as truck
where truck.status = 'active'::public.airfnb_truck_status;

drop index public.airfnb_trucks_active_service_type_idx;
alter table public.airfnb_trucks drop column service_type;
drop type public.airfnb_service_type;
drop trigger airfnb_trg_trucks_moderation on public.airfnb_trucks;
drop function public.airfnb_guard_truck_moderation();
drop policy "airfnb_trucks_owner_insert" on public.airfnb_trucks;
drop policy "airfnb_trucks_owner_update" on public.airfnb_trucks;
create policy "airfnb_trucks_owner_write"
  on public.airfnb_trucks for all
  using (owner_id = auth.uid() or public.airfnb_is_admin())
  with check (owner_id = auth.uid() or public.airfnb_is_admin());

do $legacy_acl$
declare
  v_column record;
begin
  revoke all on table public.airfnb_trucks
    from public, anon, authenticated, service_role;
  for v_column in
    select attribute.attname
      from pg_catalog.pg_attribute as attribute
     where attribute.attrelid = 'public.airfnb_trucks'::pg_catalog.regclass
       and attribute.attnum > 0 and not attribute.attisdropped
  loop
    execute pg_catalog.format(
      'revoke select (%I), insert (%I), update (%I) on table public.airfnb_trucks from public, anon, authenticated, service_role',
      v_column.attname, v_column.attname, v_column.attname
    );
  end loop;
  grant select, insert, update, delete on table public.airfnb_trucks
    to authenticated;
end
$legacy_acl$;
commit;
\endif

\if :catalog_is_pre_legacy
do $legacy_prestate$
begin
  if pg_catalog.current_database() <> pg_catalog.current_setting('catalog.runtime_database')
     or pg_catalog.to_regtype('public.airfnb_service_type') is not null
     or pg_catalog.to_regprocedure('public.airfnb_guard_truck_moderation()') is not null
     or (select pg_catalog.count(*) from pg_catalog.pg_policy
          where polrelid = 'public.airfnb_trucks'::pg_catalog.regclass) <> 2
     or not exists (
       select 1 from pg_catalog.pg_policy
        where polrelid = 'public.airfnb_trucks'::pg_catalog.regclass
          and polname = 'airfnb_trucks_owner_write'
     )
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute
          where attrelid = 'public.airfnb_v_truck_card'::pg_catalog.regclass
            and attnum > 0 and not attisdropped) <> 27
     or pg_catalog.md5(
          pg_catalog.pg_get_viewdef('public.airfnb_v_truck_card'::pg_catalog.regclass, true)
        ) <> '5e17d15485c2be8af68157568ba84028'
     or (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc
          where oid = 'public.airfnb_recalc_truck_rating()'::pg_catalog.regprocedure)
          <> '06b8f300efdd0e8d2d418a8ae0ca48e5'
     or (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc
          where oid = 'public.airfnb_can_read_truck_child(text)'::pg_catalog.regprocedure)
          <> '63f8f31bbf345d3075b489257b6fdea5' then
    raise exception 'catalog runtime failed: legacy prestate differs';
  end if;
end
$legacy_prestate$;
\endif

\if :catalog_is_pre_old
do $old_prestate$
begin
  if pg_catalog.current_database() <> pg_catalog.current_setting('catalog.runtime_database')
     or (select pg_catalog.array_agg(value.enumlabel order by value.enumsortorder)
           from pg_catalog.pg_enum as value
          where value.enumtypid = 'public.airfnb_service_type'::pg_catalog.regtype)
          is distinct from array['food_truck','catering','bar']::name[]
     or (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc
          where oid = 'public.airfnb_guard_truck_moderation()'::pg_catalog.regprocedure)
          <> '9580d50b368d29269983025249704dda'
     or pg_catalog.md5(
          pg_catalog.pg_get_viewdef('public.airfnb_v_truck_card'::pg_catalog.regclass, true)
        ) <> 'd252ca591e49263980a5072107ff8fc0'
     or (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc
          where oid = 'public.airfnb_recalc_truck_rating()'::pg_catalog.regprocedure)
          <> '06b8f300efdd0e8d2d418a8ae0ca48e5'
     or (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc
          where oid = 'public.airfnb_can_read_truck_child(text)'::pg_catalog.regprocedure)
          <> '63f8f31bbf345d3075b489257b6fdea5'
     or pg_catalog.has_table_privilege('anon', 'public.airfnb_truck_images', 'SELECT')
     or pg_catalog.has_column_privilege('anon', 'public.airfnb_truck_images', 'url', 'SELECT') then
    raise exception 'catalog runtime failed: old-candidate prestate differs';
  end if;
end
$old_prestate$;
\endif

\if :catalog_is_good
do $metadata$
declare
  v_owner oid := (select relowner from pg_catalog.pg_class
                   where oid = 'public.airfnb_trucks'::pg_catalog.regclass);
begin
  if (select pg_catalog.array_agg(value.enumlabel order by value.enumsortorder)
        from pg_catalog.pg_enum as value
       where value.enumtypid = 'public.airfnb_service_type'::pg_catalog.regtype)
       is distinct from array['food_truck','catering','bar']::name[]
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute
          where attrelid = 'public.airfnb_v_truck_card'::pg_catalog.regclass
            and attnum > 0 and not attisdropped) <> 28
     or (select relowner from pg_catalog.pg_class
          where oid = 'public.airfnb_v_truck_card'::pg_catalog.regclass) <> v_owner
     or (select reloptions from pg_catalog.pg_class
          where oid = 'public.airfnb_v_truck_card'::pg_catalog.regclass)
          is distinct from array['security_invoker=true']::text[]
     or pg_catalog.md5(
          pg_catalog.pg_get_viewdef('public.airfnb_v_truck_card'::pg_catalog.regclass, true)
        ) <> 'c3e262896aa919d75361132feff47380'
     or (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc
          where oid = 'public.airfnb_recalc_truck_rating()'::pg_catalog.regprocedure)
          <> '06b8f300efdd0e8d2d418a8ae0ca48e5'
     or (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc
          where oid = 'public.airfnb_guard_truck_moderation()'::pg_catalog.regprocedure)
          <> '9580d50b368d29269983025249704dda'
     or (select pg_catalog.md5(pg_catalog.string_agg(
          pg_catalog.format('%s:%s:%s', truck.id, truck.rating_avg, truck.rating_count),
          ',' order by truck.id)) from public.airfnb_trucks as truck)
          <> 'b7601dc5d1de93f854aaaf10085c33f7' then
    raise exception 'catalog runtime failed: final metadata';
  end if;
end
$metadata$;

begin;
do $fixture_identity$
begin
  if pg_catalog.current_database() <> pg_catalog.current_setting('catalog.runtime_database')
     or exists (select 1 from auth.users where id::text like 'f2610000-0000-4000-8000-%') then
    raise exception 'catalog runtime refused: unsafe fixture target or collision';
  end if;
end
$fixture_identity$;

insert into auth.users (id, email, raw_user_meta_data)
values
  ('f2610000-0000-4000-8000-000000000001', 'catalog-owner@example.invalid', '{"full_name":"Catalog Owner"}'::jsonb),
  ('f2610000-0000-4000-8000-000000000002', 'catalog-unrelated@example.invalid', '{"full_name":"Catalog Unrelated"}'::jsonb),
  ('f2610000-0000-4000-8000-000000000003', 'catalog-admin@example.invalid', '{"full_name":"Catalog Admin"}'::jsonb),
  ('f2610000-0000-4000-8000-000000000004', 'catalog-staff@example.invalid', '{"full_name":"Catalog Staff"}'::jsonb);
update public.airfnb_profiles
   set role = case id
     when 'f2610000-0000-4000-8000-000000000001' then 'owner'::public.airfnb_user_role
     when 'f2610000-0000-4000-8000-000000000003' then 'admin'::public.airfnb_user_role
     when 'f2610000-0000-4000-8000-000000000004' then 'staff'::public.airfnb_user_role
     else 'organizer'::public.airfnb_user_role end
 where id::text like 'f2610000-0000-4000-8000-%';

insert into public.airfnb_trucks
  (id, owner_id, slug, name, status, service_type, capacity, base_price)
values
  ('f2610000-0000-4000-8000-000000000010', 'f2610000-0000-4000-8000-000000000001', 'catalog-active', 'Catalog Active', 'active', 'catering', 120, 700),
  ('f2610000-0000-4000-8000-000000000011', 'f2610000-0000-4000-8000-000000000001', 'catalog-draft', 'Catalog Draft', 'draft', 'bar', 80, 400),
  ('f2610000-0000-4000-8000-000000000012', 'f2610000-0000-4000-8000-000000000002', 'catalog-unrelated', 'Catalog Unrelated', 'draft', 'food_truck', 60, 300),
  ('f2610000-0000-4000-8000-000000000013', 'f2610000-0000-4000-8000-000000000002', 'catalog-pending-admin', 'Catalog Pending Admin', 'pending_review', 'food_truck', 60, 300),
  ('f2610000-0000-4000-8000-000000000014', 'f2610000-0000-4000-8000-000000000002', 'catalog-pending-staff', 'Catalog Pending Staff', 'pending_review', 'food_truck', 60, 300);

insert into public.airfnb_categories (id, slug, name_pt, name_en)
values
  (9262, 'catalog-zeta', 'Catalog zeta', 'Catalog zeta'),
  (9263, 'catalog-alpha', 'Catalog alpha', 'Catalog alpha');
insert into public.airfnb_truck_categories (truck_id, category_id)
values
  ('f2610000-0000-4000-8000-000000000010', 9262),
  ('f2610000-0000-4000-8000-000000000010', 9263),
  ('f2610000-0000-4000-8000-000000000011', 9262);
insert into public.airfnb_truck_images (id, truck_id, url, kind, is_cover, sort_order)
values
  ('f2610000-0000-4000-8000-000000000020', 'f2610000-0000-4000-8000-000000000010', '/catalog/truck-plain.jpg', 'truck', false, 1),
  ('f2610000-0000-4000-8000-000000000021', 'f2610000-0000-4000-8000-000000000010', '/catalog/truck-cover.jpg', 'truck', true, 5),
  ('f2610000-0000-4000-8000-000000000022', 'f2610000-0000-4000-8000-000000000010', '/catalog/food-cover.jpg', 'food', true, 2),
  ('f2610000-0000-4000-8000-000000000023', 'f2610000-0000-4000-8000-000000000010', '/catalog/food.jpg', 'food', false, 1),
  ('f2610000-0000-4000-8000-000000000024', 'f2610000-0000-4000-8000-000000000010', '/catalog/venue.jpg', 'venue', false, 1),
  ('f2610000-0000-4000-8000-000000000025', 'f2610000-0000-4000-8000-000000000010', '/catalog/team.jpg', 'team', false, 1),
  ('f2610000-0000-4000-8000-000000000026', 'f2610000-0000-4000-8000-000000000010', '/catalog/other.jpg', 'other', false, 1),
  ('f2610000-0000-4000-8000-000000000027', 'f2610000-0000-4000-8000-000000000011', '/catalog/draft.jpg', 'truck', true, 1),
  ('f2610000-0000-4000-8000-000000000028', 'f2610000-0000-4000-8000-000000000010', '/catalog/a-food-tied.jpg', 'food', false, 1);

create temporary table catalog_runtime_checks (
  assertion_order integer primary key, assertion text not null unique,
  actual text not null, expected text not null
) on commit drop;
grant select, insert on table catalog_runtime_checks
  to anon, authenticated, service_role;

set local role anon;
insert into catalog_runtime_checks
select 10, 'anon_active_view_count', pg_catalog.count(*)::text, '1'
  from public.airfnb_v_truck_card where id::text like 'f2610000-0000-4000-8000-%';
insert into catalog_runtime_checks
select 11, 'anon_cover_ranking', cover_url, '/catalog/truck-cover.jpg'
  from public.airfnb_v_truck_card where id = 'f2610000-0000-4000-8000-000000000010';
insert into catalog_runtime_checks
select 12, 'anon_gallery_limit', pg_catalog.cardinality(gallery_urls)::text, '6'
  from public.airfnb_v_truck_card where id = 'f2610000-0000-4000-8000-000000000010';
insert into catalog_runtime_checks
select 13, 'anon_gallery_tie_order', pg_catalog.array_to_string(gallery_urls, ','),
       '/catalog/truck-cover.jpg,/catalog/truck-plain.jpg,/catalog/food-cover.jpg,/catalog/a-food-tied.jpg,/catalog/food.jpg,/catalog/venue.jpg'
  from public.airfnb_v_truck_card where id = 'f2610000-0000-4000-8000-000000000010';
insert into catalog_runtime_checks
select 14, 'anon_category_order', pg_catalog.array_to_string(category_slugs, ','),
       'catalog-alpha,catalog-zeta'
  from public.airfnb_v_truck_card where id = 'f2610000-0000-4000-8000-000000000010';
insert into catalog_runtime_checks
select 15, 'anon_service_type', service_type::text, 'catering'
  from public.airfnb_v_truck_card where id = 'f2610000-0000-4000-8000-000000000010';
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', 'f2610000-0000-4000-8000-000000000001', true);
set local role authenticated;
insert into catalog_runtime_checks
select 20, 'owner_draft_child_count', pg_catalog.count(*)::text, '1'
  from public.airfnb_truck_images where truck_id = 'f2610000-0000-4000-8000-000000000011';
insert into public.airfnb_trucks (owner_id, slug, name, status, service_type)
values ('f2610000-0000-4000-8000-000000000001', 'catalog-owner-valid', 'Catalog Owner Valid', 'draft', 'bar');
update public.airfnb_trucks set status = 'pending_review'
 where id = 'f2610000-0000-4000-8000-000000000011';
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', 'f2610000-0000-4000-8000-000000000002', true);
select pg_catalog.set_config('request.jwt.claim.role', 'admin', true);
set local role authenticated;
update public.airfnb_trucks set name = 'Forged Admin Change'
 where id = 'f2610000-0000-4000-8000-000000000010';
reset role;
insert into catalog_runtime_checks
select 30, 'forged_admin_claim_no_effect', name, 'Catalog Active'
  from public.airfnb_trucks where id = 'f2610000-0000-4000-8000-000000000010';

select pg_catalog.set_config('request.jwt.claim.sub', 'f2610000-0000-4000-8000-000000000003', true);
set local role authenticated;
select public.airfnb_admin_approve_truck('f2610000-0000-4000-8000-000000000013');
reset role;
insert into catalog_runtime_checks
select 40, 'admin_approve_rpc', status::text, 'active'
  from public.airfnb_trucks where id = 'f2610000-0000-4000-8000-000000000013';

select pg_catalog.set_config('request.jwt.claim.sub', 'f2610000-0000-4000-8000-000000000004', true);
set local role authenticated;
select public.airfnb_admin_approve_truck('f2610000-0000-4000-8000-000000000014');
reset role;
insert into catalog_runtime_checks
select 41, 'staff_approve_rpc', status::text, 'active'
  from public.airfnb_trucks where id = 'f2610000-0000-4000-8000-000000000014';

set local role service_role;
insert into catalog_runtime_checks
select 50, 'service_role_active_view_count', pg_catalog.count(*)::text, '3'
  from public.airfnb_v_truck_card where id::text like 'f2610000-0000-4000-8000-%';
reset role;

insert into public.airfnb_bookings (id, organizer_id, status)
values (
  'f2610000-0000-4000-8000-000000000060',
  'f2610000-0000-4000-8000-000000000002',
  'confirmed'
);
insert into public.airfnb_booking_trucks (booking_id, truck_id, agreed_price)
values (
  'f2610000-0000-4000-8000-000000000060',
  'f2610000-0000-4000-8000-000000000010',
  700
);
select pg_catalog.set_config('request.jwt.claim.sub', 'f2610000-0000-4000-8000-000000000002', true);
set local role authenticated;
insert into public.airfnb_reviews (
  booking_id, truck_id, rating_food, rating_service, rating_value, body
)
values (
  'f2610000-0000-4000-8000-000000000060',
  'f2610000-0000-4000-8000-000000000010',
  5, 4, 3, 'Catalog rating compatibility'
);
reset role;
insert into catalog_runtime_checks
select 60, 'rating_input_derived',
       pg_catalog.concat_ws(':', organizer_id::text, rating_overall::text, is_verified::text),
       'f2610000-0000-4000-8000-000000000002:4.0:true'
  from public.airfnb_reviews
 where booking_id = 'f2610000-0000-4000-8000-000000000060'
   and truck_id = 'f2610000-0000-4000-8000-000000000010';
insert into catalog_runtime_checks
select 61, 'rating_trigger_compatibility',
       pg_catalog.concat_ws(':', rating_avg::text, rating_count::text),
       '4.0:1'
  from public.airfnb_trucks
 where id = 'f2610000-0000-4000-8000-000000000010';

do $named_assertions$
declare
  v_check record;
begin
  for v_check in select assertion, actual, expected
                   from catalog_runtime_checks order by assertion_order
  loop
    if v_check.actual is distinct from v_check.expected then
      raise exception 'catalog runtime assertion failed: % actual=% expected=%',
        v_check.assertion, v_check.actual, v_check.expected;
    end if;
  end loop;
end
$named_assertions$;
rollback;
\endif
