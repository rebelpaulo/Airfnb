\set ON_ERROR_STOP on

begin;
set local statement_timeout = '60s';
set local lock_timeout = '5s';

do $fixture_guard$
begin
  if pg_catalog.current_database() !~ '^fb_tailor_supplier_acl_[a-z0-9_]+$'
     or exists (
       select 1
         from auth.users
        where id::text like 'f2650000-0000-4000-8000-%'
     ) then
    raise exception 'supplier ACL runtime refused: unsafe fixture target or collision';
  end if;

  if pg_catalog.to_regprocedure('public.airfnb_supplier_services(uuid)') is null
     or pg_catalog.to_regprocedure('public.airfnb_public_service_detail(text)') is null
     or pg_catalog.to_regprocedure('public.airfnb_invitation_candidates(uuid)') is null
     or pg_catalog.to_regprocedure('public.airfnb_invite_request_services(uuid,uuid[])') is null
     or pg_catalog.to_regprocedure('public.airfnb_booking_service_context(uuid)') is null
     or pg_catalog.to_regprocedure('public.airfnb_request_application_service_context(uuid)') is null
     or pg_catalog.to_regprocedure('public.airfnb_supplier_export_data()') is null then
    raise exception 'supplier ACL runtime refused: follower RPC set is incomplete';
  end if;
end
$fixture_guard$;

-- The follower is an additive column-ACL migration.  The catalog predecessor
-- already grants the safe card columns (including category id/slug and image
-- URL metadata), while the follower adds category labels and owner-mutation
-- image ids.  No API role ever receives broad table SELECT or owner_id.
do $acl_matrix$
declare
  v_role name;
begin
  foreach v_role in array array['anon'::name, 'authenticated'::name, 'service_role'::name]
  loop
    if pg_catalog.has_table_privilege(v_role, 'public.airfnb_trucks', 'SELECT')
       or pg_catalog.has_table_privilege(v_role, 'public.airfnb_truck_images', 'SELECT')
       or pg_catalog.has_table_privilege(v_role, 'public.airfnb_truck_categories', 'SELECT')
       or pg_catalog.has_table_privilege(v_role, 'public.airfnb_categories', 'SELECT')
       or pg_catalog.has_column_privilege(
         v_role, 'public.airfnb_trucks', 'owner_id', 'SELECT'
       )
       or not pg_catalog.has_column_privilege(
         v_role, 'public.airfnb_categories', 'name_pt', 'SELECT'
       )
       or not pg_catalog.has_column_privilege(
         v_role, 'public.airfnb_categories', 'name_en', 'SELECT'
       )
       or not pg_catalog.has_column_privilege(
         v_role, 'public.airfnb_categories', 'icon', 'SELECT'
       ) then
      raise exception 'supplier ACL runtime failed: catalog column ACL for %', v_role;
    end if;
  end loop;

  if not pg_catalog.has_column_privilege(
       'authenticated', 'public.airfnb_truck_images', 'id', 'SELECT'
     )
     or pg_catalog.has_column_privilege(
       'anon', 'public.airfnb_truck_images', 'id', 'SELECT'
     )
     or pg_catalog.has_column_privilege(
       'service_role', 'public.airfnb_truck_images', 'id', 'SELECT'
     ) then
    raise exception 'supplier ACL runtime failed: image id ACL';
  end if;
end
$acl_matrix$;

do $function_acl_matrix$
declare
  v_contract record;
begin
  for v_contract in
    select *
      from (values
        ('public.airfnb_supplier_services(uuid)'::regprocedure, false, true, false),
        ('public.airfnb_public_service_detail(text)'::regprocedure, true, true, false),
        ('public.airfnb_invitation_candidates(uuid)'::regprocedure, false, true, false),
        ('public.airfnb_invite_request_services(uuid,uuid[])'::regprocedure, false, true, false),
        ('public.airfnb_booking_service_context(uuid)'::regprocedure, false, true, false),
        ('public.airfnb_request_application_service_context(uuid)'::regprocedure, false, true, false),
        ('public.airfnb_supplier_export_data()'::regprocedure, false, true, false)
      ) as contract(function_oid, anon_execute, authenticated_execute, service_execute)
  loop
    if exists (
         select 1
           from pg_catalog.aclexplode((
             select coalesce(
                      procedure.proacl,
                      pg_catalog.acldefault('f', procedure.proowner)
                    )
               from pg_catalog.pg_proc as procedure
              where procedure.oid = v_contract.function_oid
           )) as privilege
          where privilege.grantee = 0
            and privilege.privilege_type = 'EXECUTE'
       )
       or pg_catalog.has_function_privilege('anon', v_contract.function_oid, 'EXECUTE')
            is distinct from v_contract.anon_execute
       or pg_catalog.has_function_privilege('authenticated', v_contract.function_oid, 'EXECUTE')
            is distinct from v_contract.authenticated_execute
       or pg_catalog.has_function_privilege('service_role', v_contract.function_oid, 'EXECUTE')
            is distinct from v_contract.service_execute then
      raise exception 'supplier ACL runtime failed: execute ACL for %',
        v_contract.function_oid;
    end if;
  end loop;
end
$function_acl_matrix$;

do $review_policy_contract$
begin
  if not exists (
    select 1
      from pg_catalog.pg_policy as policy
     where policy.polrelid = 'public.airfnb_organizer_reviews'::regclass
       and policy.polname = 'airfnb_org_reviews_participant_insert'
       and policy.polcmd = 'a'
       and policy.polpermissive
       and policy.polroles = array['authenticated'::regrole::oid]
       and policy.polqual is null
       and pg_catalog.md5(
             pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
           ) = '64f6778971e136463d322c17b734dc76'
  ) then
    raise exception 'supplier ACL runtime failed: review policy contract';
  end if;
end
$review_policy_contract$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('f2650000-0000-4000-8000-000000000001', 'supplier-acl-organizer@example.invalid', '{}'),
  ('f2650000-0000-4000-8000-000000000002', 'supplier-acl-owner-a@example.invalid', '{}'),
  ('f2650000-0000-4000-8000-000000000003', 'supplier-acl-owner-b@example.invalid', '{}'),
  ('f2650000-0000-4000-8000-000000000004', 'supplier-acl-admin@example.invalid', '{}'),
  ('f2650000-0000-4000-8000-000000000005', 'supplier-acl-outsider@example.invalid', '{}'),
  ('f2650000-0000-4000-8000-000000000006', 'supplier-acl-organizer-b@example.invalid', '{}');

update public.airfnb_profiles as profile
   set role = fixture.role::public.airfnb_user_role,
       display_name = fixture.display_name,
       full_name = fixture.full_name,
       phone = fixture.phone,
       vat_number = fixture.vat_number,
       company_name = fixture.company_name,
       avatar_url = fixture.avatar_url,
       created_at = fixture.created_at
  from (values
    ('f2650000-0000-4000-8000-000000000001'::uuid, 'organizer', 'Runtime Organizer', 'Organizer Private Name', '+351910000001', 'PT000000001', 'Organizer Private Co', null::text, '2018-01-01 00:00:00+00'::timestamptz),
    ('f2650000-0000-4000-8000-000000000002'::uuid, 'owner', 'Runtime Supplier A', 'Supplier A Private Name', '+351910000002', 'PT000000002', 'Supplier A Private Co', 'https://cdn.example.invalid/avatar-a.png', '2019-02-03 00:00:00+00'::timestamptz),
    ('f2650000-0000-4000-8000-000000000003'::uuid, 'owner', 'Runtime Supplier B', 'Supplier B Private Name', '+351910000003', 'PT000000003', 'Supplier B Private Co', null::text, '2020-01-01 00:00:00+00'::timestamptz),
    ('f2650000-0000-4000-8000-000000000004'::uuid, 'admin', 'Runtime Admin', 'Admin Private Name', '+351910000004', 'PT000000004', 'Admin Private Co', null::text, '2021-01-01 00:00:00+00'::timestamptz),
    ('f2650000-0000-4000-8000-000000000005'::uuid, 'organizer', 'Runtime Outsider', 'Outsider Private Name', '+351910000005', 'PT000000005', 'Outsider Private Co', null::text, '2022-01-01 00:00:00+00'::timestamptz),
    ('f2650000-0000-4000-8000-000000000006'::uuid, 'organizer', 'Runtime Organizer B', 'Organizer B Private Name', '+351910000006', 'PT000000006', 'Organizer B Private Co', null::text, '2023-01-01 00:00:00+00'::timestamptz)
  ) as fixture(
    id, role, display_name, full_name, phone, vat_number, company_name,
    avatar_url, created_at
  )
 where profile.id = fixture.id;

do $profile_fixture_assert$
begin
  if (select pg_catalog.count(*)
        from public.airfnb_profiles
       where id::text like 'f2650000-0000-4000-8000-%') <> 6 then
    raise exception 'supplier ACL runtime failed: auth/profile fixture trigger';
  end if;
end
$profile_fixture_assert$;

insert into public.airfnb_categories(id, slug, name_pt, name_en, icon)
values (265001, 'supplier-acl-runtime', 'Cozinha Runtime', 'Runtime Cuisine', 'utensils');

insert into public.airfnb_trucks (
  id, owner_id, slug, name, tagline, description, base_city, capacity,
  min_event_pax, max_event_pax, status, cuisine_types, dietary_options,
  service_type, homologation_expires_at, insurance_expires_at
) values
  (
    'f2650000-0000-4000-8000-000000000010',
    'f2650000-0000-4000-8000-000000000002',
    'supplier-acl-owner-a-active', 'Supplier A Active', 'Safe public tagline',
    'Safe public description', 'Lisboa', 220, 20, 500, 'active',
    array['portuguesa'], array['vegan'::public.airfnb_dietary_tag],
    'food_truck', '2040-05-06', '2041-06-07'
  ),
  (
    'f2650000-0000-4000-8000-000000000011',
    'f2650000-0000-4000-8000-000000000003',
    'supplier-acl-owner-b-active', 'Supplier B Active', null, null,
    'Lisboa', 180, 20, 400, 'active', array['portuguesa'], '{}',
    'catering', null, null
  ),
  (
    'f2650000-0000-4000-8000-000000000012',
    'f2650000-0000-4000-8000-000000000002',
    'supplier-acl-owner-a-draft', 'Supplier A Draft', null, null,
    'Lisboa', 200, 20, 400, 'draft', array['portuguesa'], '{}',
    'bar', null, null
  ),
  (
    'f2650000-0000-4000-8000-000000000013',
    'f2650000-0000-4000-8000-000000000003',
    'supplier-acl-owner-b-ineligible', 'Supplier B Ineligible', null, null,
    'Porto', 20, 10, 30, 'active', array['japonesa'], '{}',
    'food_truck', null, null
  );

insert into public.airfnb_truck_images
  (id, truck_id, url, alt, sort_order, is_cover, kind)
values (
  'f2650000-0000-4000-8000-000000000020',
  'f2650000-0000-4000-8000-000000000010',
  'https://cdn.example.invalid/supplier-a-truck.png',
  'Supplier A truck', 0, true, 'truck'
);

insert into public.airfnb_truck_categories(truck_id, category_id)
values ('f2650000-0000-4000-8000-000000000010', 265001);

insert into public.airfnb_menu_items
  (id, truck_id, name, description, price, category, sort_order)
values (
  'f2650000-0000-4000-8000-000000000030',
  'f2650000-0000-4000-8000-000000000010',
  'Runtime Menu', 'Safe menu description', 12.50, 'Main', 0
);

insert into public.airfnb_truck_documents
  (id, truck_id, kind, url, issued_at, expires_at)
values (
  'f2650000-0000-4000-8000-000000000040',
  'f2650000-0000-4000-8000-000000000010',
  'asae', 'https://private-doc.example.invalid/supplier-a.pdf',
  '2039-01-02', '2040-01-02'
);

insert into public.airfnb_event_requests (
  id, organizer_id, title, start_at, end_at, expected_pax, slots_needed,
  applications_deadline, status, visibility, city, locality,
  desired_cuisines, application_response_window_hours
) values
  (
    'f2650000-0000-4000-8000-000000000100',
    'f2650000-0000-4000-8000-000000000001',
    'Supplier ACL Open Request', '2035-08-20 12:00:00+00',
    '2035-08-20 18:00:00+00', 100, 2, '2035-08-10 00:00:00+00',
    'open', 'public', 'Lisboa', 'Lisboa', array['portuguesa'], 48
  ),
  (
    'f2650000-0000-4000-8000-000000000110',
    'f2650000-0000-4000-8000-000000000006',
    'Supplier ACL Forged Request', '2035-09-20 12:00:00+00',
    '2035-09-20 18:00:00+00', 100, 1, '2035-09-10 00:00:00+00',
    'open', 'public', 'Lisboa', 'Lisboa', array['portuguesa'], 48
  ),
  (
    'f2650000-0000-4000-8000-000000000120',
    'f2650000-0000-4000-8000-000000000001',
    'Supplier ACL Closed Request', '2035-10-20 12:00:00+00',
    '2035-10-20 18:00:00+00', 100, 1, '2035-10-10 00:00:00+00',
    'closed', 'public', 'Lisboa', 'Lisboa', array['portuguesa'], 48
  );

insert into public.airfnb_applications (
  id, request_id, truck_id, proposed_price, cover_message, status,
  deal_type, proposed_fixed_to_organizer, proposed_revenue_share_pct
) values
  (
    'f2650000-0000-4000-8000-000000000200',
    'f2650000-0000-4000-8000-000000000100',
    'f2650000-0000-4000-8000-000000000010',
    700, 'Supplier A proposal', 'submitted', 'fixed', 0, 0
  ),
  (
    'f2650000-0000-4000-8000-000000000201',
    'f2650000-0000-4000-8000-000000000100',
    'f2650000-0000-4000-8000-000000000011',
    710, 'Supplier B proposal', 'shortlisted', 'fixed', 0, 0
  );

insert into public.airfnb_events
  (id, organizer_id, title, kind, start_at, end_at, expected_pax, city, status)
values (
  'f2650000-0000-4000-8000-000000000300',
  'f2650000-0000-4000-8000-000000000001',
  'Supplier ACL Runtime Event', 'corporate',
  '2035-08-20 12:00:00+00', '2035-08-20 18:00:00+00',
  100, 'Lisboa', 'confirmed'
);

insert into public.airfnb_bookings (
  id, event_id, organizer_id, status, starts_at, ends_at, pax_count,
  total_amount, currency, application_id
) values (
  'f2650000-0000-4000-8000-000000000310',
  'f2650000-0000-4000-8000-000000000300',
  'f2650000-0000-4000-8000-000000000001',
  'completed', '2035-08-20 12:00:00+00', '2035-08-20 18:00:00+00',
  100, 1410, 'EUR', 'f2650000-0000-4000-8000-000000000200'
);

insert into public.airfnb_booking_trucks(booking_id, truck_id, agreed_price)
values
  ('f2650000-0000-4000-8000-000000000310', 'f2650000-0000-4000-8000-000000000010', 700),
  ('f2650000-0000-4000-8000-000000000310', 'f2650000-0000-4000-8000-000000000011', 710);

insert into public.airfnb_lock_fees (
  id, application_id, amount, platform_fee, organizer_share, currency,
  due_until, status, provider_ref
) values (
  'f2650000-0000-4000-8000-000000000320',
  'f2650000-0000-4000-8000-000000000200',
  50, 25, 25, 'EUR', '2035-08-11 00:00:00+00', 'paid',
  'supplier-acl-runtime-lock'
);

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'f2650000-0000-4000-8000-000000000002', true
);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
insert into public.airfnb_organizer_reviews (
  booking_id, truck_id, rating_reliability,
  rating_communication, rating_payment, body
) values (
  'f2650000-0000-4000-8000-000000000310',
  'f2650000-0000-4000-8000-000000000010',
  5, 4, 5, 'Runtime organizer review'
);
reset role;

do $legitimate_owner_review$
begin
  if not exists (
       select 1
         from public.airfnb_organizer_reviews as review
        where review.booking_id = 'f2650000-0000-4000-8000-000000000310'
          and review.truck_id = 'f2650000-0000-4000-8000-000000000010'
          and review.organizer_id = 'f2650000-0000-4000-8000-000000000001'
          and review.rating_overall = 4.7
          and review.is_verified
     )
     or not exists (
       select 1
         from public.airfnb_profiles as profile
        where profile.id = 'f2650000-0000-4000-8000-000000000001'
          and profile.organizer_rating_avg = 4.7
          and profile.organizer_rating_count = 1
     ) then
    raise exception 'legitimate owner review or organizer aggregate failed';
  end if;
end
$legitimate_owner_review$;

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'f2650000-0000-4000-8000-000000000005', true
);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
do $outsider_review_denial$
begin
  begin
    insert into public.airfnb_organizer_reviews (
      booking_id, truck_id, rating_reliability,
      rating_communication, rating_payment, body
    ) values (
      'f2650000-0000-4000-8000-000000000310',
      'f2650000-0000-4000-8000-000000000011',
      5, 5, 5, 'Forged outsider organizer review'
    );
    raise exception 'outsider unexpectedly inserted organizer review';
  exception when sqlstate '42501' then null;
  end;
end
$outsider_review_denial$;
reset role;

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'f2650000-0000-4000-8000-000000000001', true
);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
insert into public.airfnb_reviews (
  booking_id, truck_id, rating_food, rating_service, rating_value, body
) values (
  'f2650000-0000-4000-8000-000000000310',
  'f2650000-0000-4000-8000-000000000011',
  5, 4, 3, 'Legitimate organizer review of service'
);
reset role;

do $legitimate_organizer_review$
begin
  if not exists (
       select 1
         from public.airfnb_reviews as review
        where review.booking_id = 'f2650000-0000-4000-8000-000000000310'
          and review.truck_id = 'f2650000-0000-4000-8000-000000000011'
          and review.organizer_id = 'f2650000-0000-4000-8000-000000000001'
          and review.rating_overall = 4.0
          and review.is_verified
     )
     or not exists (
       select 1
         from public.airfnb_trucks as truck
        where truck.id = 'f2650000-0000-4000-8000-000000000011'
          and truck.rating_avg = 4.0
          and truck.rating_count = 1
     ) then
    raise exception 'legitimate organizer review or truck aggregate failed';
  end if;
end
$legitimate_organizer_review$;

select pg_catalog.set_config('request.jwt.claim.sub', '', true);
select pg_catalog.set_config('request.jwt.claim.role', 'anon', true);
set local role anon;
do $anon_review_denial$
begin
  begin
    insert into public.airfnb_organizer_reviews (
      booking_id, truck_id, rating_reliability,
      rating_communication, rating_payment, body
    ) values (
      'f2650000-0000-4000-8000-000000000310',
      'f2650000-0000-4000-8000-000000000011',
      5, 5, 5, 'Forged anonymous organizer review'
    );
    raise exception 'anon unexpectedly inserted organizer review';
  exception when sqlstate '42501' then null;
  end;
end
$anon_review_denial$;
reset role;

-- Prove the column ACLs with real API-role statements, not catalog metadata
-- alone. Public child-table RLS still decides which rows are visible.
select pg_catalog.set_config('request.jwt.claim.sub', '', true);
select pg_catalog.set_config('request.jwt.claim.role', 'anon', true);
set local role anon;
do $anon_column_statements$
begin
  perform category.name_pt, category.name_en, category.icon
    from public.airfnb_categories as category
   where category.id = 265001;
  begin
    perform truck.owner_id
      from public.airfnb_trucks as truck
     where truck.id = 'f2650000-0000-4000-8000-000000000010';
    raise exception 'anon unexpectedly selected owner_id';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform image.id
      from public.airfnb_truck_images as image
     where image.id = 'f2650000-0000-4000-8000-000000000020';
    raise exception 'anon unexpectedly selected image id';
  exception when sqlstate '42501' then null;
  end;
end
$anon_column_statements$;
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', 'f2650000-0000-4000-8000-000000000002', true);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
do $authenticated_column_statements$
begin
  perform category.name_pt, category.name_en, category.icon
    from public.airfnb_categories as category
   where category.id = 265001;
  if (select pg_catalog.count(*)
        from public.airfnb_truck_images as image
       where image.id = 'f2650000-0000-4000-8000-000000000020') <> 1 then
    raise exception 'authenticated owner did not read owned image id';
  end if;
  begin
    perform truck.owner_id
      from public.airfnb_trucks as truck
     where truck.id = 'f2650000-0000-4000-8000-000000000010';
    raise exception 'authenticated unexpectedly selected owner_id';
  exception when sqlstate '42501' then null;
  end;
end
$authenticated_column_statements$;
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', '', true);
select pg_catalog.set_config('request.jwt.claim.role', 'service_role', true);
set local role service_role;
do $service_column_statements$
begin
  perform category.name_pt, category.name_en, category.icon
    from public.airfnb_categories as category
   where category.id = 265001;
  begin
    perform truck.owner_id
      from public.airfnb_trucks as truck
     where truck.id = 'f2650000-0000-4000-8000-000000000010';
    raise exception 'service_role unexpectedly selected owner_id';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform image.id
      from public.airfnb_truck_images as image
     where image.id = 'f2650000-0000-4000-8000-000000000020';
    raise exception 'service_role unexpectedly selected image id';
  exception when sqlstate '42501' then null;
  end;
end
$service_column_statements$;
reset role;

-- Anonymous callers get only the public detail RPC.  It must expose the active
-- service with derived compliance states, never owner ids, profile PII, exact
-- compliance dates, or private document URLs. Drafts and malformed slugs stay
-- closed.
select pg_catalog.set_config('request.jwt.claim.sub', '', true);
select pg_catalog.set_config('request.jwt.claim.role', 'anon', true);
set local role anon;
do $anon_public_projection$
declare
  v_payload jsonb;
  v_owner_keys text[];
begin
  v_payload := public.airfnb_public_service_detail('supplier-acl-owner-a-active');

  select pg_catalog.array_agg(owner_key.key_name order by owner_key.key_name)
    into v_owner_keys
    from pg_catalog.jsonb_object_keys(v_payload -> 'owner')
      as owner_key(key_name);

  if v_payload is null
     or v_payload ->> 'id' <> 'f2650000-0000-4000-8000-000000000010'
     or v_payload ->> 'homologation_state' <> 'valid'
     or v_payload ->> 'insurance_state' <> 'valid'
     or v_payload #>> '{owner,display_name}' <> 'Runtime Supplier A'
     or v_payload #>> '{owner,member_since_year}' <> '2019'
     or v_owner_keys is distinct from array[
       'avatar_url','display_name','member_since_year'
     ]::text[]
     or v_payload::text ~ '"(owner_id|email|full_name|phone|vat_number|company_name|homologation_expires_at|insurance_expires_at)"'
     or v_payload::text like '%private-doc.example.invalid%'
     or v_payload::text like '%2040-01-02%'
     or pg_catalog.jsonb_array_length(v_payload -> 'images') <> 1
     or pg_catalog.jsonb_array_length(v_payload -> 'menu_items') <> 1
     or pg_catalog.jsonb_array_length(v_payload -> 'categories') <> 1
     or pg_catalog.jsonb_array_length(v_payload -> 'document_states') <> 1
     or v_payload #>> '{document_states,0,kind}' <> 'asae'
     or v_payload #>> '{document_states,0,state}' <> 'valid' then
    raise exception 'supplier ACL runtime failed: public detail privacy projection %',
      v_payload;
  end if;

  if public.airfnb_public_service_detail('supplier-acl-owner-a-draft') is not null
     or public.airfnb_public_service_detail('') is not null
     or public.airfnb_public_service_detail(pg_catalog.repeat('x', 201)) is not null then
    raise exception 'supplier ACL runtime failed: public detail negative inputs';
  end if;
end
$anon_public_projection$;

do $anon_private_rpc_denials$
declare
  v_sql text;
begin
  foreach v_sql in array array[
    'select * from public.airfnb_supplier_services(null)',
    'select * from public.airfnb_invitation_candidates(''f2650000-0000-4000-8000-000000000100'')',
    'select * from public.airfnb_invite_request_services(''f2650000-0000-4000-8000-000000000100'', array[''f2650000-0000-4000-8000-000000000010'']::uuid[])',
    'select * from public.airfnb_booking_service_context(''f2650000-0000-4000-8000-000000000310'')',
    'select * from public.airfnb_request_application_service_context(''f2650000-0000-4000-8000-000000000100'')',
    'select public.airfnb_supplier_export_data()'
  ]
  loop
    begin
      execute v_sql;
      raise exception 'anon unexpectedly executed private RPC: %', v_sql;
    exception when sqlstate '42501' then null;
    end;
  end loop;
end
$anon_private_rpc_denials$;
reset role;

-- Supplier A sees both owned services (including its draft), one participant
-- booking row, and only its bounded export collections. No projection may
-- smuggle owner_id back into the client contract.
select pg_catalog.set_config('request.jwt.claim.sub', 'f2650000-0000-4000-8000-000000000002', true);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
do $supplier_a_matrix$
declare
  v_export jsonb;
begin
  if (select pg_catalog.count(*)
        from public.airfnb_supplier_services(null)) <> 2
     or (select pg_catalog.count(*)
           from public.airfnb_supplier_services(
             'f2650000-0000-4000-8000-000000000010'
           )) <> 1
     or exists (
       select 1
         from public.airfnb_supplier_services(null) as service
        where pg_catalog.to_jsonb(service) ? 'owner_id'
     ) then
    raise exception 'supplier ACL runtime failed: supplier services owner scope';
  end if;

  if (select pg_catalog.count(*)
        from public.airfnb_booking_service_context(
          'f2650000-0000-4000-8000-000000000310'
        ) as context
       where context.truck_id = 'f2650000-0000-4000-8000-000000000010'
         and context.is_owned
         and not context.is_organizer) <> 1
     or (select pg_catalog.count(*)
           from public.airfnb_booking_service_context(
             'f2650000-0000-4000-8000-000000000310'
           )) <> 1
     or (select pg_catalog.count(*)
           from public.airfnb_request_application_service_context(
             'f2650000-0000-4000-8000-000000000100'
           )) <> 0 then
    raise exception 'supplier ACL runtime failed: supplier participant scope';
  end if;

  v_export := public.airfnb_supplier_export_data();
  if pg_catalog.jsonb_array_length(v_export -> 'trucks_as_owner') <> 2
     or pg_catalog.jsonb_array_length(v_export -> 'applications_as_owner') <> 1
     or pg_catalog.jsonb_array_length(v_export -> 'reviews_left_for_organizers') <> 1
     or pg_catalog.jsonb_array_length(v_export -> 'lock_fees') <> 1
     or v_export::text ~ '"owner_id"'
     or v_export #>> '{trucks_as_owner,0,name}' not like 'Supplier A%'
     or v_export #>> '{applications_as_owner,0,truck_id}'
          <> 'f2650000-0000-4000-8000-000000000010' then
    raise exception 'supplier ACL runtime failed: supplier export scope %', v_export;
  end if;

  if (select pg_catalog.count(*)
        from public.airfnb_invitation_candidates(
          'f2650000-0000-4000-8000-000000000100'
        )) <> 0 then
    raise exception 'supplier unexpectedly received organizer candidates';
  end if;
end
$supplier_a_matrix$;
reset role;

-- The organizer owns request 100 and booking 310. Candidate filtering must
-- return exactly the two active Lisbon/cuisine/capacity matches. Application
-- and booking projections are organizer-wide, while supplier projections and
-- exports remain empty.
select pg_catalog.set_config('request.jwt.claim.sub', 'f2650000-0000-4000-8000-000000000001', true);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
do $organizer_read_matrix$
declare
  v_export jsonb;
begin
  if (select pg_catalog.count(*)
        from public.airfnb_supplier_services(null)) <> 0
     or (select pg_catalog.count(*)
           from public.airfnb_invitation_candidates(
             'f2650000-0000-4000-8000-000000000100'
           )) <> 2
     or exists (
       select 1
         from public.airfnb_invitation_candidates(
           'f2650000-0000-4000-8000-000000000100'
         ) as candidate
        where candidate.truck_id not in (
          'f2650000-0000-4000-8000-000000000010',
          'f2650000-0000-4000-8000-000000000011'
        )
           or candidate.already_invited
           or pg_catalog.to_jsonb(candidate) ? 'owner_id'
     )
     or (select pg_catalog.count(*)
           from public.airfnb_invitation_candidates(
             'f2650000-0000-4000-8000-000000000120'
           )) <> 0 then
    raise exception 'supplier ACL runtime failed: invitation candidate scope';
  end if;

  if (select pg_catalog.count(*)
        from public.airfnb_booking_service_context(
          'f2650000-0000-4000-8000-000000000310'
        ) as context
       where context.is_organizer
         and not context.is_owned
         and context.request_id = 'f2650000-0000-4000-8000-000000000100') <> 2
     or exists (
       select 1
         from public.airfnb_booking_service_context(
           'f2650000-0000-4000-8000-000000000310'
         ) as context
        where pg_catalog.to_jsonb(context) ? 'owner_id'
     )
     or (select pg_catalog.count(*)
           from public.airfnb_request_application_service_context(
             'f2650000-0000-4000-8000-000000000100'
           )) <> 2
     or exists (
       select 1
         from public.airfnb_request_application_service_context(
           'f2650000-0000-4000-8000-000000000100'
         ) as context
        where pg_catalog.to_jsonb(context) ? 'owner_id'
     ) then
    raise exception 'supplier ACL runtime failed: organizer context projections';
  end if;

  v_export := public.airfnb_supplier_export_data();
  if pg_catalog.jsonb_array_length(v_export -> 'trucks_as_owner') <> 0
     or pg_catalog.jsonb_array_length(v_export -> 'applications_as_owner') <> 0
     or pg_catalog.jsonb_array_length(v_export -> 'reviews_left_for_organizers') <> 0
     or pg_catalog.jsonb_array_length(v_export -> 'lock_fees') <> 0 then
    raise exception 'supplier ACL runtime failed: organizer supplier export';
  end if;
end
$organizer_read_matrix$;

-- Invite validation is all-or-nothing. Malformed arrays, a forged request,
-- closed requests and a mixed eligible/ineligible set may not produce either
-- invitation or notification rows.
do $invite_negative_matrix$
declare
  v_many uuid[];
begin
  select pg_catalog.array_agg(pg_catalog.md5('supplier-acl-' || value::text)::uuid)
    into v_many
    from pg_catalog.generate_series(1, 81) as value;

  begin
    perform public.airfnb_invite_request_services(null, array[
      'f2650000-0000-4000-8000-000000000010'::uuid
    ]);
    raise exception 'null request unexpectedly invited';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.airfnb_invite_request_services(
      'f2650000-0000-4000-8000-000000000100', null
    );
    raise exception 'null service array unexpectedly invited';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.airfnb_invite_request_services(
      'f2650000-0000-4000-8000-000000000100', array[]::uuid[]
    );
    raise exception 'empty service array unexpectedly invited';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.airfnb_invite_request_services(
      'f2650000-0000-4000-8000-000000000100', v_many
    );
    raise exception 'oversized service array unexpectedly invited';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.airfnb_invite_request_services(
      'f2650000-0000-4000-8000-000000000110', array[
        'f2650000-0000-4000-8000-000000000010'::uuid
      ]
    );
    raise exception 'forged request unexpectedly invited';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform public.airfnb_invite_request_services(
      'f2650000-0000-4000-8000-000000000120', array[
        'f2650000-0000-4000-8000-000000000010'::uuid
      ]
    );
    raise exception 'closed request unexpectedly invited';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.airfnb_invite_request_services(
      'f2650000-0000-4000-8000-000000000100', array[
        'f2650000-0000-4000-8000-000000000011'::uuid,
        'f2650000-0000-4000-8000-000000000013'::uuid
      ]
    );
    raise exception 'mixed eligibility array unexpectedly invited';
  exception when sqlstate '22023' then null;
  end;

end
$invite_negative_matrix$;

reset role;
do $invite_negative_atomicity$
begin
  if exists (
       select 1
         from public.airfnb_request_invitations as invitation
        where invitation.request_id::text like 'f2650000-0000-4000-8000-%'
     )
     or exists (
       select 1
         from public.airfnb_notifications as notification
        where notification.kind = 'request.invited'
          and notification.payload ->> 'request_id' like 'f2650000-0000-4000-8000-%'
     ) then
    raise exception 'supplier ACL runtime failed: invite negative atomicity';
  end if;
end
$invite_negative_atomicity$;
select pg_catalog.set_config(
  'request.jwt.claim.sub', 'f2650000-0000-4000-8000-000000000001', true
);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

do $invite_success_and_retry$
declare
  v_first integer;
  v_retry integer;
begin
  select pg_catalog.count(*)
    into v_first
    from public.airfnb_invite_request_services(
      'f2650000-0000-4000-8000-000000000100', array[
        'f2650000-0000-4000-8000-000000000010'::uuid,
        'f2650000-0000-4000-8000-000000000010'::uuid,
        null::uuid
      ]
    );

  select pg_catalog.count(*)
    into v_retry
    from public.airfnb_invite_request_services(
      'f2650000-0000-4000-8000-000000000100', array[
        'f2650000-0000-4000-8000-000000000010'::uuid
      ]
    );

  if v_first <> 1
     or v_retry <> 0
     or not exists (
       select 1
         from public.airfnb_invitation_candidates(
           'f2650000-0000-4000-8000-000000000100'
         ) as candidate
        where candidate.truck_id = 'f2650000-0000-4000-8000-000000000010'
          and candidate.already_invited
    ) then
    raise exception 'supplier ACL runtime failed: invite retry contract first=% retry=%',
      v_first, v_retry;
  end if;
end
$invite_success_and_retry$;
reset role;

-- The notification belongs to the supplier and is intentionally invisible to
-- the organizer under RLS, so durable side effects are counted as the database
-- owner only after the authenticated RPC calls have completed.
do $invite_success_side_effects$
begin
  if (select pg_catalog.count(*)
        from public.airfnb_request_invitations as invitation
       where invitation.request_id = 'f2650000-0000-4000-8000-000000000100') <> 1
     or (select pg_catalog.count(*)
           from public.airfnb_notifications as notification
          where notification.kind = 'request.invited'
            and notification.payload ->> 'request_id'
                  = 'f2650000-0000-4000-8000-000000000100') <> 1 then
    raise exception 'supplier ACL runtime failed: invite durable side effects';
  end if;
end
$invite_success_side_effects$;

-- Supplier B is a second participant and sees only its booking row, never A's.
select pg_catalog.set_config('request.jwt.claim.sub', 'f2650000-0000-4000-8000-000000000003', true);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
do $supplier_b_participant$
begin
  if (select pg_catalog.count(*)
        from public.airfnb_booking_service_context(
          'f2650000-0000-4000-8000-000000000310'
        ) as context
       where context.truck_id = 'f2650000-0000-4000-8000-000000000011'
         and context.is_owned
         and not context.is_organizer) <> 1
     or (select pg_catalog.count(*)
           from public.airfnb_booking_service_context(
             'f2650000-0000-4000-8000-000000000310'
           )) <> 1 then
    raise exception 'supplier ACL runtime failed: second participant scope';
  end if;
end
$supplier_b_participant$;
reset role;

-- A database-backed admin may inspect request applications, but is not made a
-- booking participant, request organizer, or supplier owner by that role.
select pg_catalog.set_config('request.jwt.claim.sub', 'f2650000-0000-4000-8000-000000000004', true);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
do $admin_matrix$
begin
  if (select pg_catalog.count(*)
        from public.airfnb_request_application_service_context(
          'f2650000-0000-4000-8000-000000000100'
        )) <> 2
     or (select pg_catalog.count(*)
           from public.airfnb_booking_service_context(
             'f2650000-0000-4000-8000-000000000310'
           )) <> 0
     or (select pg_catalog.count(*)
           from public.airfnb_invitation_candidates(
             'f2650000-0000-4000-8000-000000000100'
           )) <> 0
     or (select pg_catalog.count(*)
           from public.airfnb_supplier_services(null)) <> 0 then
    raise exception 'supplier ACL runtime failed: admin boundary';
  end if;
end
$admin_matrix$;
reset role;

-- An unrelated authenticated caller receives empty stable projections and an
-- empty supplier export. Mutation attempts fail with 42501.
select pg_catalog.set_config('request.jwt.claim.sub', 'f2650000-0000-4000-8000-000000000005', true);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
do $unrelated_matrix$
declare
  v_export jsonb;
begin
  if (select pg_catalog.count(*) from public.airfnb_supplier_services(null)) <> 0
     or (select pg_catalog.count(*)
           from public.airfnb_invitation_candidates(
             'f2650000-0000-4000-8000-000000000100'
           )) <> 0
     or (select pg_catalog.count(*)
           from public.airfnb_booking_service_context(
             'f2650000-0000-4000-8000-000000000310'
           )) <> 0
     or (select pg_catalog.count(*)
           from public.airfnb_request_application_service_context(
             'f2650000-0000-4000-8000-000000000100'
           )) <> 0 then
    raise exception 'supplier ACL runtime failed: unrelated read boundary';
  end if;

  v_export := public.airfnb_supplier_export_data();
  if pg_catalog.jsonb_array_length(v_export -> 'trucks_as_owner') <> 0
     or pg_catalog.jsonb_array_length(v_export -> 'applications_as_owner') <> 0
     or pg_catalog.jsonb_array_length(v_export -> 'reviews_left_for_organizers') <> 0
     or pg_catalog.jsonb_array_length(v_export -> 'lock_fees') <> 0 then
    raise exception 'supplier ACL runtime failed: unrelated export boundary';
  end if;

  begin
    perform public.airfnb_invite_request_services(
      'f2650000-0000-4000-8000-000000000100', array[
        'f2650000-0000-4000-8000-000000000011'::uuid
      ]
    );
    raise exception 'unrelated caller unexpectedly invited';
  exception when sqlstate '42501' then null;
  end;
end
$unrelated_matrix$;
reset role;

-- A forged JWT user_metadata role is not used anywhere in these decisions.
update auth.users
   set raw_user_meta_data = '{"role":"admin"}'::jsonb
 where id = 'f2650000-0000-4000-8000-000000000005';
set local role authenticated;
do $metadata_forgery_denial$
begin
  if (select pg_catalog.count(*)
        from public.airfnb_request_application_service_context(
          'f2650000-0000-4000-8000-000000000100'
        )) <> 0 then
    raise exception 'user_metadata role forged request application access';
  end if;
end
$metadata_forgery_denial$;
reset role;

-- A service-role JWT presented through the authenticated database role is
-- rejected by every private helper. The supplier service projection is the
-- deliberate empty-set form; public detail remains public and privacy-safe.
select pg_catalog.set_config('request.jwt.claim.sub', 'f2650000-0000-4000-8000-000000000002', true);
select pg_catalog.set_config('request.jwt.claim.role', 'service_role', true);
set local role authenticated;
do $signed_service_claim_matrix$
begin
  if (select pg_catalog.count(*) from public.airfnb_supplier_services(null)) <> 0
     or public.airfnb_public_service_detail('supplier-acl-owner-a-active') is null then
    raise exception 'supplier ACL runtime failed: signed service projection boundary';
  end if;

  begin
    perform public.airfnb_invitation_candidates(
      'f2650000-0000-4000-8000-000000000100'
    );
    raise exception 'signed service claim unexpectedly read candidates';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform public.airfnb_invite_request_services(
      'f2650000-0000-4000-8000-000000000100', array[
        'f2650000-0000-4000-8000-000000000011'::uuid
      ]
    );
    raise exception 'signed service claim unexpectedly invited';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform public.airfnb_booking_service_context(
      'f2650000-0000-4000-8000-000000000310'
    );
    raise exception 'signed service claim unexpectedly read booking context';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform public.airfnb_request_application_service_context(
      'f2650000-0000-4000-8000-000000000100'
    );
    raise exception 'signed service claim unexpectedly read application context';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform public.airfnb_supplier_export_data();
    raise exception 'signed service claim unexpectedly exported supplier data';
  exception when sqlstate '42501' then null;
  end;
end
$signed_service_claim_matrix$;
reset role;

-- The real service_role database role has no EXECUTE on any of the seven RPCs,
-- including the otherwise-public detail endpoint.
select pg_catalog.set_config('request.jwt.claim.sub', '', true);
select pg_catalog.set_config('request.jwt.claim.role', 'service_role', true);
set local role service_role;
do $service_role_rpc_denials$
declare
  v_sql text;
begin
  foreach v_sql in array array[
    'select * from public.airfnb_supplier_services(null)',
    'select public.airfnb_public_service_detail(''supplier-acl-owner-a-active'')',
    'select * from public.airfnb_invitation_candidates(''f2650000-0000-4000-8000-000000000100'')',
    'select * from public.airfnb_invite_request_services(''f2650000-0000-4000-8000-000000000100'', array[''f2650000-0000-4000-8000-000000000011'']::uuid[])',
    'select * from public.airfnb_booking_service_context(''f2650000-0000-4000-8000-000000000310'')',
    'select * from public.airfnb_request_application_service_context(''f2650000-0000-4000-8000-000000000100'')',
    'select public.airfnb_supplier_export_data()'
  ]
  loop
    begin
      execute v_sql;
      raise exception 'service_role unexpectedly executed RPC: %', v_sql;
    exception when sqlstate '42501' then null;
    end;
  end loop;
end
$service_role_rpc_denials$;
reset role;

-- Missing-sub authenticated callers must not inherit the prior actor through
-- session state. Stable owner projections return empty; authorization helpers
-- raise 42501 before reading or mutating tenant data.
select pg_catalog.set_config('request.jwt.claim.sub', '', true);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
do $missing_sub_matrix$
begin
  if (select pg_catalog.count(*) from public.airfnb_supplier_services(null)) <> 0 then
    raise exception 'missing-sub caller received supplier services';
  end if;
  begin
    perform public.airfnb_invitation_candidates(
      'f2650000-0000-4000-8000-000000000100'
    );
    raise exception 'missing-sub caller received candidates';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform public.airfnb_booking_service_context(
      'f2650000-0000-4000-8000-000000000310'
    );
    raise exception 'missing-sub caller received booking context';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform public.airfnb_request_application_service_context(
      'f2650000-0000-4000-8000-000000000100'
    );
    raise exception 'missing-sub caller received application context';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform public.airfnb_supplier_export_data();
    raise exception 'missing-sub caller exported supplier data';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform public.airfnb_invite_request_services(
      'f2650000-0000-4000-8000-000000000100', array[
        'f2650000-0000-4000-8000-000000000011'::uuid
      ]
    );
    raise exception 'missing-sub caller invited';
  exception when sqlstate '42501' then null;
  end;
end
$missing_sub_matrix$;
reset role;

-- No negative-path or retry may have added a second invitation/notification.
do $final_side_effect_assert$
begin
  if (select pg_catalog.count(*)
        from public.airfnb_request_invitations as invitation
       where invitation.request_id::text like 'f2650000-0000-4000-8000-%') <> 1
     or (select pg_catalog.count(*)
           from public.airfnb_notifications as notification
          where notification.kind = 'request.invited'
            and notification.payload ->> 'request_id'
                  like 'f2650000-0000-4000-8000-%') <> 1 then
    raise exception 'supplier ACL runtime failed: final invite side effects drifted';
  end if;
end
$final_side_effect_assert$;

rollback;
\echo 'supplier ACL caller reconciliation runtime passed'
