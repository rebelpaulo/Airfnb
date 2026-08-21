\set ON_ERROR_STOP on

select :'privacy_runtime_phase' = 'setup' as privacy_is_setup,
       :'privacy_runtime_phase' = 'assert_pre_historical' as privacy_is_pre_historical,
       :'privacy_runtime_phase' = 'assert_pre_storage' as privacy_is_pre_storage,
       :'privacy_runtime_phase' = 'assert_good' as privacy_is_good
\gset

\if :privacy_is_setup
begin;

select pg_catalog.set_config(
         'privacy.runtime_database',
         :'privacy_runtime_database',
         true
       ),
       pg_catalog.set_config('privacy.prestate', :'privacy_prestate', true);

do $clone_identity$
begin
  if pg_catalog.current_database() <> pg_catalog.current_setting('privacy.runtime_database')
     or pg_catalog.current_database() !~ '^fb_tailor_privacy_[0-9]+_[0-9]+_(historical|storage)$'
     or pg_catalog.current_setting('privacy.prestate') not in ('historical', 'storage') then
    raise exception 'privacy runtime refused: unsafe clone identity or prestate';
  end if;

  if exists (
    select 1 from auth.users where id::text like 'f2500000-0000-4000-8000-%'
  ) or exists (
    select 1 from public.airfnb_event_requests
     where id::text like 'f2500000-0000-4000-8000-%'
  ) then
    raise exception 'privacy runtime refused: fixture already exists';
  end if;
end
$clone_identity$;

\if :privacy_prestate_historical
revoke select on table public.airfnb_event_requests
  from public, anon, authenticated;
revoke select (
  id, organizer_id, title, kind, description, start_at, end_at, city,
  address_id, expected_pax, slots_needed, budget_min, budget_max,
  desired_categories, dietary_requirements, applications_deadline,
  power_available, water_available, notes, status, visibility, awarded_at,
  created_at, updated_at, discovery_mode, accepted_deal_types, min_fixed_fee,
  min_revenue_share_pct, recommended_slots, slot_breakdown,
  application_response_window_hours, contact_name, contact_email,
  contact_phone, address_line, locality, budget_estimate, budget_flexible,
  catering_type, desired_cuisines, setup_minutes, teardown_minutes,
  energy_need, energy_assistance, sanitation_level, extra_services,
  selection_mode, assistance_requested, water_provided, wc_provided
) on table public.airfnb_event_requests from public, anon, authenticated;
grant select on table public.airfnb_event_requests to anon, authenticated;

drop policy airfnb_truck_cat_read on public.airfnb_truck_categories;
create policy airfnb_truck_cat_read
  on public.airfnb_truck_categories
  for select
  using (true);
grant select on table public.airfnb_truck_categories to anon, authenticated;
grant select on table public.airfnb_truck_availability to anon, authenticated;
\endif

insert into auth.users (id, email, raw_user_meta_data)
values
  ('f2500000-0000-4000-8000-000000000001', 'privacy-owner@example.invalid', '{"full_name":"Privacy Owner"}'::jsonb),
  ('f2500000-0000-4000-8000-000000000002', 'privacy-unrelated@example.invalid', '{"full_name":"Privacy Unrelated"}'::jsonb),
  ('f2500000-0000-4000-8000-000000000003', 'privacy-invited@example.invalid', '{"full_name":"Privacy Invited"}'::jsonb),
  ('f2500000-0000-4000-8000-000000000004', 'privacy-admin@example.invalid', '{"full_name":"Privacy Admin"}'::jsonb),
  ('f2500000-0000-4000-8000-000000000005', 'privacy-staff@example.invalid', '{"full_name":"Privacy Staff"}'::jsonb);

update public.airfnb_profiles
   set role = case id
     when 'f2500000-0000-4000-8000-000000000003' then 'owner'::public.airfnb_user_role
     when 'f2500000-0000-4000-8000-000000000004' then 'admin'::public.airfnb_user_role
     when 'f2500000-0000-4000-8000-000000000005' then 'staff'::public.airfnb_user_role
     else 'organizer'::public.airfnb_user_role
   end
 where id::text like 'f2500000-0000-4000-8000-%';

insert into public.airfnb_addresses (id, owner_id, label, line1, city, country)
values (
  'f2500000-0000-4000-8000-000000000010',
  'f2500000-0000-4000-8000-000000000001',
  'Private venue', 'Rua Privada 10', 'Lisboa', 'PT'
);

insert into public.airfnb_trucks (
  id, owner_id, slug, name, base_city, capacity, rating_avg, featured,
  base_price, status
)
values (
  'f2500000-0000-4000-8000-000000000020',
  'f2500000-0000-4000-8000-000000000003',
  'privacy-runtime-truck', 'Privacy Runtime Truck', 'Lisboa', 200, 4.8,
  true, 500, 'active'
);

insert into public.airfnb_categories (id, slug, name_pt, name_en)
values
  (9250, 'privacy-runtime-hit', 'Categoria compatível', 'Matching category'),
  (9251, 'privacy-runtime-miss', 'Categoria incompatível', 'Non-matching category');

insert into public.airfnb_truck_categories (truck_id, category_id)
values ('f2500000-0000-4000-8000-000000000020', 9250);

insert into public.airfnb_event_requests (
  id, organizer_id, title, kind, description, start_at, end_at, city,
  address_id, expected_pax, slots_needed, budget_min, budget_max,
  desired_categories, dietary_requirements, applications_deadline,
  power_available, notes, status, visibility, contact_name, contact_email,
  contact_phone, address_line, locality, desired_cuisines, setup_minutes,
  energy_need, energy_assistance, sanitation_level
)
values
  (
    'f2500000-0000-4000-8000-000000000030',
    'f2500000-0000-4000-8000-000000000001',
    'Public privacy fixture', 'corporate', 'Public brief',
    '2032-06-10 12:00:00+00', '2032-06-10 18:00:00+00', 'Lisboa',
    'f2500000-0000-4000-8000-000000000010', 100, 1, 400, 900,
    '{}', '{}', '2032-06-01 00:00:00+00', true,
    'Public operational note', 'open', 'public', 'Public Contact',
    'public-contact@example.invalid', '+351910000030', 'Rua Pública 30',
    'Lisboa', '{portuguesa}', 45, 'ate_3kw', false, 'wc_proximo'
  ),
  (
    'f2500000-0000-4000-8000-000000000031',
    'f2500000-0000-4000-8000-000000000001',
    'Private privacy fixture', 'private', 'Private brief',
    '2032-06-11 12:00:00+00', '2032-06-11 18:00:00+00', 'Lisboa',
    'f2500000-0000-4000-8000-000000000010', 100, 1, 400, 900,
    '{}', '{}', '2032-06-01 00:00:00+00', true,
    'Private operational note', 'open', 'invite_only', 'Private Contact',
    'private-contact@example.invalid', '+351910000031', 'Rua Privada 31',
    'Lisboa', '{portuguesa}', 45, 'ate_3kw', false, 'wc_proximo'
  );

insert into public.airfnb_event_requests (
  id, organizer_id, title, start_at, city, expected_pax, budget_max,
  desired_categories, status, visibility
)
values
  (
    'f2500000-0000-4000-8000-000000000032',
    'f2500000-0000-4000-8000-000000000001',
    'Category hit available', '2032-06-12 12:00:00+00', 'Lisboa', 100, 900,
    '{9250}', 'open', 'public'
  ),
  (
    'f2500000-0000-4000-8000-000000000033',
    'f2500000-0000-4000-8000-000000000001',
    'Category hit blocked', '2032-06-13 12:00:00+00', 'Lisboa', 100, 900,
    '{9250}', 'open', 'public'
  ),
  (
    'f2500000-0000-4000-8000-000000000034',
    'f2500000-0000-4000-8000-000000000001',
    'Category miss available', '2032-06-14 12:00:00+00', 'Lisboa', 100, 900,
    '{9251}', 'open', 'public'
  ),
  (
    'f2500000-0000-4000-8000-000000000035',
    'f2500000-0000-4000-8000-000000000001',
    'Category miss blocked', '2032-06-15 12:00:00+00', 'Lisboa', 100, 900,
    '{9251}', 'open', 'public'
  ),
  (
    'f2500000-0000-4000-8000-000000000036',
    'f2500000-0000-4000-8000-000000000001',
    'Draft request', '2032-06-16 12:00:00+00', 'Lisboa', 100, 900,
    '{9250}', 'draft', 'public'
  );

insert into public.airfnb_truck_availability (truck_id, date, status)
values
  ('f2500000-0000-4000-8000-000000000020', '2032-06-13', 'blocked'),
  ('f2500000-0000-4000-8000-000000000020', '2032-06-15', 'booked');

insert into public.airfnb_request_invitations (request_id, truck_id, invited_by)
values (
  'f2500000-0000-4000-8000-000000000031',
  'f2500000-0000-4000-8000-000000000020',
  'f2500000-0000-4000-8000-000000000001'
);

commit;
\endif

\if :privacy_is_pre_historical
begin;
set local role anon;
select contact_email as exposed_email
  from public.airfnb_event_requests
 where id = 'f2500000-0000-4000-8000-000000000030'
\gset
select pg_catalog.count(*) as exposed_category_rows
  from public.airfnb_truck_categories
 where truck_id = 'f2500000-0000-4000-8000-000000000020'
\gset
reset role;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  'f2500000-0000-4000-8000-000000000003',
  true
);
set local role authenticated;
select public.airfnb_match_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000030'
       ) as baseline_score
\gset
reset role;
select public.airfnb_match_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000032'
       ) as hit_available,
       public.airfnb_match_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000033'
       ) as hit_blocked,
       public.airfnb_match_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000034'
       ) as miss_available,
       public.airfnb_match_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000035'
       ) as miss_blocked
\gset historical_
select :'exposed_email' = 'public-contact@example.invalid'
       and :'exposed_category_rows'::integer = 1
       and :'baseline_score'::numeric = 85
       and :'historical_hit_available'::numeric = 100
       and :'historical_hit_blocked'::numeric = 90
       and :'historical_miss_available'::numeric = 70
       and :'historical_miss_blocked'::numeric = 60
       as privacy_historical_preproof_ok
\gset
\if :privacy_historical_preproof_ok
\else
select 1 / 0 as privacy_runtime_failed_historical_predecessor;
\endif
rollback;
\endif

\if :privacy_is_pre_storage
begin;
select public.airfnb_match_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000030'
       ) as baseline_score,
       public.airfnb_match_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000032'
       ) as hit_available,
       public.airfnb_match_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000033'
       ) as hit_blocked,
       public.airfnb_match_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000034'
       ) as miss_available,
       public.airfnb_match_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000035'
       ) as miss_blocked
\gset
select :'baseline_score'::numeric = 85
       and :'hit_available'::numeric = 100
       and :'hit_blocked'::numeric = 90
       and :'miss_available'::numeric = 70
       and :'miss_blocked'::numeric = 60
       as privacy_storage_preproof_ok
\gset
\if :privacy_storage_preproof_ok
\else
select 1 / 0 as privacy_runtime_failed_storage_candidate_baseline;
\endif
rollback;
\endif

\if :privacy_is_good
begin;

do $catalog_proof$
declare
  v_table oid := 'public.airfnb_event_requests'::regclass;
begin
  if (select pg_catalog.count(*) from pg_catalog.pg_policy where polrelid = v_table) <> 4
     or exists (
       select 1
         from pg_catalog.pg_attribute as attribute
         cross join pg_catalog.pg_roles as api_role
        where attribute.attrelid = v_table
          and attribute.attname in (
            'contact_name', 'contact_email', 'contact_phone',
            'address_line', 'address_id'
          )
          and api_role.rolname in ('anon', 'authenticated')
          and pg_catalog.has_column_privilege(
            api_role.oid, v_table, attribute.attnum, 'SELECT'
          )
     ) then
    raise exception 'privacy runtime failed: catalog privacy postcondition';
  end if;
end
$catalog_proof$;

set local role anon;
select pg_catalog.count(*) filter (
         where id = 'f2500000-0000-4000-8000-000000000030'
       ) as public,
       pg_catalog.count(*) filter (
         where id = 'f2500000-0000-4000-8000-000000000031'
       ) as private
  from public.airfnb_event_requests
\gset anon_
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', 'f2500000-0000-4000-8000-000000000002', true);
set local role authenticated;
select pg_catalog.count(*) filter (
         where id = 'f2500000-0000-4000-8000-000000000030'
       ) as public,
       pg_catalog.count(*) filter (
         where id = 'f2500000-0000-4000-8000-000000000031'
       ) as private
  from public.airfnb_event_requests
\gset unrelated_
select public.airfnb_match_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000030'
       ) as public_score,
       public.airfnb_match_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000031'
       ) as private_score
\gset unrelated_
select public.airfnb_match_category_availability_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000032'
       ) as helper_hit_available,
       public.airfnb_match_category_availability_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000033'
       ) as helper_hit_blocked,
       public.airfnb_match_category_availability_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000034'
       ) as helper_miss_available,
       public.airfnb_match_category_availability_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000035'
       ) as helper_miss_blocked,
       public.airfnb_match_category_availability_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000030'
       ) as helper_no_preference,
       public.airfnb_match_category_availability_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000031'
       ) as helper_private
\gset unrelated_
select public.airfnb_match_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000032'
       ) as score_hit_available,
       public.airfnb_match_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000033'
       ) as score_hit_blocked,
       public.airfnb_match_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000034'
       ) as score_miss_available,
       public.airfnb_match_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000035'
       ) as score_miss_blocked
\gset unrelated_
select pg_catalog.count(*) as private_rpc_rows
  from public.airfnb_private_event_requests('f2500000-0000-4000-8000-000000000031')
\gset unrelated_
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', 'f2500000-0000-4000-8000-000000000003', true);
set local role authenticated;
select pg_catalog.count(*) as private_rows
  from public.airfnb_event_requests
 where id = 'f2500000-0000-4000-8000-000000000031'
\gset invited_
select public.airfnb_user_owns_invited_truck('f2500000-0000-4000-8000-000000000031') as helper,
       public.airfnb_match_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000031'
       ) as score
\gset invited_
select public.airfnb_match_category_availability_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000031'
       ) as private_helper_score
\gset invited_
select pg_catalog.count(*) as batch_rows
  from public.airfnb_match_scores_batch(
    array['f2500000-0000-4000-8000-000000000020']::uuid[],
    array[
      'f2500000-0000-4000-8000-000000000030',
      'f2500000-0000-4000-8000-000000000031'
    ]::uuid[]
  )
 where score = 85
\gset invited_
select pg_catalog.count(*) as matching_request_rows
  from public.airfnb_find_matching_requests(
    'f2500000-0000-4000-8000-000000000020', 20
  )
 where request_id in (
   'f2500000-0000-4000-8000-000000000030',
   'f2500000-0000-4000-8000-000000000031'
 ) and match_score = 85
\gset invited_
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', 'f2500000-0000-4000-8000-000000000001', true);
set local role authenticated;
select pg_catalog.count(*) as private_rows,
       pg_catalog.bool_and(public.airfnb_user_organizes_request(id)) as helper
  from public.airfnb_event_requests
 where id = 'f2500000-0000-4000-8000-000000000031'
\gset owner_
select pg_catalog.count(*) as private_rpc_rows,
       pg_catalog.min(contact_email) as private_email
  from public.airfnb_private_event_requests('f2500000-0000-4000-8000-000000000031')
\gset owner_
select public.airfnb_match_category_availability_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000031'
       ) as private_helper_score,
       public.airfnb_match_category_availability_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000036'
       ) as draft_helper_score
\gset owner_
select pg_catalog.count(*) as matching_truck_rows
  from public.airfnb_find_matching_trucks('f2500000-0000-4000-8000-000000000031', 12)
 where truck_id = 'f2500000-0000-4000-8000-000000000020' and match_score = 85
\gset owner_
select pg_catalog.count(*) as recommended_truck_rows
  from public.airfnb_recommend_trucks_for_request('f2500000-0000-4000-8000-000000000031', 12)
 where truck_id = 'f2500000-0000-4000-8000-000000000020'
   and match_score = 85 and already_invited and not already_applied
\gset owner_
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', 'f2500000-0000-4000-8000-000000000004', true);
set local role authenticated;
select public.airfnb_is_admin() as helper,
       pg_catalog.count(*) filter (
         where id = 'f2500000-0000-4000-8000-000000000031'
       ) as private_rows
  from public.airfnb_event_requests
\gset admin_
select pg_catalog.count(*) as private_rpc_rows,
       pg_catalog.min(contact_email) as private_email
  from public.airfnb_private_event_requests('f2500000-0000-4000-8000-000000000031')
\gset admin_
select public.airfnb_match_category_availability_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000031'
       ) as private_helper_score
\gset admin_
select pg_catalog.count(*) as bulk_rpc_rows
  from public.airfnb_private_event_requests(null)
\gset admin_
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', 'f2500000-0000-4000-8000-000000000005', true);
set local role authenticated;
select public.airfnb_is_admin() as helper,
       pg_catalog.count(*) filter (
         where id = 'f2500000-0000-4000-8000-000000000031'
       ) as private_rows
  from public.airfnb_event_requests
\gset staff_
select pg_catalog.count(*) as private_rpc_rows
  from public.airfnb_private_event_requests('f2500000-0000-4000-8000-000000000031')
\gset staff_
select public.airfnb_match_category_availability_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000031'
       ) as private_helper_score
\gset staff_
select pg_catalog.count(*) as bulk_rpc_rows
  from public.airfnb_private_event_requests(null)
\gset staff_
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select public.airfnb_match_category_availability_score(
         'f2500000-0000-4000-8000-000000000020',
         'f2500000-0000-4000-8000-000000000030'
       ) as helper_score
\gset null_actor_
reset role;

set local role service_role;
select pg_catalog.count(*) as request_rows,
       pg_catalog.count(contact_email) as pii_rows
  from public.airfnb_event_requests
 where id in (
   'f2500000-0000-4000-8000-000000000030',
   'f2500000-0000-4000-8000-000000000031'
 )
\gset service_
reset role;

select :'anon_public'::integer = 1 and :'anon_private'::integer = 0
   and :'unrelated_public'::integer = 1 and :'unrelated_private'::integer = 0
   and :'unrelated_public_score'::numeric = 85 and :'unrelated_private_score'::numeric = 0
   and :'unrelated_helper_hit_available'::numeric = 40
   and :'unrelated_helper_hit_blocked'::numeric = 30
   and :'unrelated_helper_miss_available'::numeric = 10
   and :'unrelated_helper_miss_blocked'::numeric = 0
   and :'unrelated_helper_no_preference'::numeric = 25
   and :'unrelated_helper_private'::numeric = 0
   and :'unrelated_score_hit_available'::numeric = 100
   and :'unrelated_score_hit_blocked'::numeric = 90
   and :'unrelated_score_miss_available'::numeric = 70
   and :'unrelated_score_miss_blocked'::numeric = 60
   and :'unrelated_score_hit_available'::numeric
       - :'unrelated_score_miss_available'::numeric = 30
   and :'unrelated_score_hit_available'::numeric
       - :'unrelated_score_hit_blocked'::numeric = 10
   and :'unrelated_private_rpc_rows'::integer = 0
   and :'invited_private_rows'::integer = 1 and :'invited_helper'::boolean
   and :'invited_score'::numeric = 85 and :'invited_batch_rows'::integer = 2
   and :'invited_private_helper_score'::numeric = 25
   and :'invited_matching_request_rows'::integer = 2
   and :'owner_private_rows'::integer = 1 and :'owner_helper'::boolean
   and :'owner_private_rpc_rows'::integer = 1
   and :'owner_private_email' = 'private-contact@example.invalid'
   and :'owner_private_helper_score'::numeric = 25
   and :'owner_draft_helper_score'::numeric = 0
   and :'owner_matching_truck_rows'::integer = 1
   and :'owner_recommended_truck_rows'::integer = 1
   and :'admin_helper'::boolean and :'admin_private_rows'::integer = 1
   and :'admin_private_rpc_rows'::integer = 1
   and :'admin_private_email' = 'private-contact@example.invalid'
   and :'admin_private_helper_score'::numeric = 25
   and :'admin_bulk_rpc_rows'::integer = 0
   and :'staff_helper'::boolean and :'staff_private_rows'::integer = 1
   and :'staff_private_rpc_rows'::integer = 1
   and :'staff_private_helper_score'::numeric = 25
   and :'staff_bulk_rpc_rows'::integer = 0
   and :'null_actor_helper_score'::numeric = 0
   and :'service_request_rows'::integer = 2 and :'service_pii_rows'::integer = 2
  as privacy_role_paths_ok
\gset
\if :privacy_role_paths_ok
\else
select 1 / 0 as privacy_runtime_failed_role_paths;
\endif

rollback;
\endif
