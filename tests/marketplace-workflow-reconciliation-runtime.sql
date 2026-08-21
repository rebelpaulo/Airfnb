\set ON_ERROR_STOP on

begin;
set local statement_timeout = '60s';

do $fixture_guard$
begin
  if pg_catalog.current_database() !~ '^fb_tailor_catalog_[0-9]+_[0-9]+_(legacy|old)$'
     or exists (
       select 1 from auth.users
        where id::text like 'f2620000-0000-4000-8000-%'
     ) then
    raise exception 'marketplace runtime refused: unsafe fixture target or collision';
  end if;
end
$fixture_guard$;

update public.airfnb_platform_settings
   set value = '1000'
 where key in (
   'rate_limit.event_requests_per_day',
   'rate_limit.applications_per_day_per_truck'
 );

insert into auth.users (id, email, raw_user_meta_data) values
  ('f2620000-0000-4000-8000-000000000001', 'market-organizer@example.invalid', '{}'),
  ('f2620000-0000-4000-8000-000000000002', 'market-supplier-a@example.invalid', '{}'),
  ('f2620000-0000-4000-8000-000000000003', 'market-supplier-b@example.invalid', '{}'),
  ('f2620000-0000-4000-8000-000000000004', 'market-admin@example.invalid', '{}'),
  ('f2620000-0000-4000-8000-000000000005', 'market-staff@example.invalid', '{}'),
  ('f2620000-0000-4000-8000-000000000006', 'market-outsider@example.invalid', '{}'),
  ('f2620000-0000-4000-8000-000000000007', 'market-metadata@example.invalid', '{"role":"admin"}'),
  ('f2620000-0000-4000-8000-000000000008', 'market-organizer-b@example.invalid', '{}');

update public.airfnb_profiles as profile
   set role = fixture.role::public.airfnb_user_role,
       display_name = fixture.display_name
  from (values
    ('f2620000-0000-4000-8000-000000000001'::uuid, 'organizer', 'Market Organizer'),
    ('f2620000-0000-4000-8000-000000000002'::uuid, 'owner', 'Market Supplier A'),
    ('f2620000-0000-4000-8000-000000000003'::uuid, 'owner', 'Market Supplier B'),
    ('f2620000-0000-4000-8000-000000000004'::uuid, 'admin', 'Market Admin'),
    ('f2620000-0000-4000-8000-000000000005'::uuid, 'staff', 'Market Staff'),
    ('f2620000-0000-4000-8000-000000000006'::uuid, 'organizer', 'Market Outsider'),
    ('f2620000-0000-4000-8000-000000000007'::uuid, 'organizer', 'Market Metadata'),
    ('f2620000-0000-4000-8000-000000000008'::uuid, 'organizer', 'Market Organizer B')
  ) as fixture(id, role, display_name)
 where profile.id = fixture.id;

insert into public.airfnb_trucks
  (id, owner_id, slug, name, status, service_type, base_city)
values
  ('f2620000-0000-4000-8000-000000000010', 'f2620000-0000-4000-8000-000000000002', 'market-supplier-a-active', 'Market Supplier A Active', 'active', 'food_truck', 'Lisboa'),
  ('f2620000-0000-4000-8000-000000000011', 'f2620000-0000-4000-8000-000000000003', 'market-supplier-b-active', 'Market Supplier B Active', 'active', 'catering', 'Porto'),
  ('f2620000-0000-4000-8000-000000000012', 'f2620000-0000-4000-8000-000000000002', 'market-supplier-a-draft', 'Market Supplier A Draft', 'draft', 'bar', 'Lisboa');

insert into public.airfnb_event_requests
  (id, organizer_id, title, start_at, end_at, expected_pax, slots_needed,
   applications_deadline, status, visibility, application_response_window_hours,
   city)
select fixture.id, fixture.organizer_id, fixture.title,
       '2035-08-20 12:00:00+00', '2035-08-20 18:00:00+00', 100,
       fixture.slots, '2035-08-10 00:00:00+00', 'open', fixture.visibility,
       48, 'Lisboa'
  from (values
    ('f2620000-0000-4000-8000-000000000100'::uuid, 'f2620000-0000-4000-8000-000000000001'::uuid, 'Decision actors', 8, 'public'),
    ('f2620000-0000-4000-8000-000000000110'::uuid, 'f2620000-0000-4000-8000-000000000001'::uuid, 'Default fee', 1, 'public'),
    ('f2620000-0000-4000-8000-000000000120'::uuid, 'f2620000-0000-4000-8000-000000000001'::uuid, 'Changed fee', 1, 'public'),
    ('f2620000-0000-4000-8000-000000000130'::uuid, 'f2620000-0000-4000-8000-000000000001'::uuid, 'Missing fee', 1, 'public'),
    ('f2620000-0000-4000-8000-000000000140'::uuid, 'f2620000-0000-4000-8000-000000000001'::uuid, 'Malformed fee', 1, 'public'),
    ('f2620000-0000-4000-8000-000000000150'::uuid, 'f2620000-0000-4000-8000-000000000001'::uuid, 'Negative fee', 1, 'public'),
    ('f2620000-0000-4000-8000-000000000160'::uuid, 'f2620000-0000-4000-8000-000000000001'::uuid, 'Oversized fee', 1, 'public'),
    ('f2620000-0000-4000-8000-000000000170'::uuid, 'f2620000-0000-4000-8000-000000000001'::uuid, 'Final slot', 1, 'public'),
    ('f2620000-0000-4000-8000-000000000180'::uuid, 'f2620000-0000-4000-8000-000000000001'::uuid, 'Multi slot', 2, 'public'),
    ('f2620000-0000-4000-8000-000000000190'::uuid, 'f2620000-0000-4000-8000-000000000001'::uuid, 'Public direct insert', 1, 'public'),
    ('f2620000-0000-4000-8000-000000000191'::uuid, 'f2620000-0000-4000-8000-000000000001'::uuid, 'Invited direct insert', 1, 'invite_only'),
    ('f2620000-0000-4000-8000-000000000192'::uuid, 'f2620000-0000-4000-8000-000000000008'::uuid, 'Private not invited', 1, 'invite_only')
  ) as fixture(id, organizer_id, title, slots, visibility);

insert into public.airfnb_request_invitations(request_id, truck_id, invited_by)
values (
  'f2620000-0000-4000-8000-000000000191',
  'f2620000-0000-4000-8000-000000000010',
  'f2620000-0000-4000-8000-000000000001'
);

insert into public.airfnb_applications
  (id, request_id, truck_id, proposed_price, status)
values
  ('f2620000-0000-4000-8000-000000000200', 'f2620000-0000-4000-8000-000000000100', 'f2620000-0000-4000-8000-000000000010', 700, 'submitted'),
  ('f2620000-0000-4000-8000-000000000201', 'f2620000-0000-4000-8000-000000000100', 'f2620000-0000-4000-8000-000000000011', 710, 'submitted'),
  ('f2620000-0000-4000-8000-000000000210', 'f2620000-0000-4000-8000-000000000110', 'f2620000-0000-4000-8000-000000000010', 720, 'submitted'),
  ('f2620000-0000-4000-8000-000000000220', 'f2620000-0000-4000-8000-000000000120', 'f2620000-0000-4000-8000-000000000010', 730, 'submitted'),
  ('f2620000-0000-4000-8000-000000000230', 'f2620000-0000-4000-8000-000000000130', 'f2620000-0000-4000-8000-000000000010', 740, 'submitted'),
  ('f2620000-0000-4000-8000-000000000240', 'f2620000-0000-4000-8000-000000000140', 'f2620000-0000-4000-8000-000000000010', 750, 'submitted'),
  ('f2620000-0000-4000-8000-000000000250', 'f2620000-0000-4000-8000-000000000150', 'f2620000-0000-4000-8000-000000000010', 760, 'submitted'),
  ('f2620000-0000-4000-8000-000000000260', 'f2620000-0000-4000-8000-000000000160', 'f2620000-0000-4000-8000-000000000010', 770, 'submitted'),
  ('f2620000-0000-4000-8000-000000000270', 'f2620000-0000-4000-8000-000000000170', 'f2620000-0000-4000-8000-000000000010', 780, 'submitted'),
  ('f2620000-0000-4000-8000-000000000271', 'f2620000-0000-4000-8000-000000000170', 'f2620000-0000-4000-8000-000000000011', 790, 'shortlisted'),
  ('f2620000-0000-4000-8000-000000000280', 'f2620000-0000-4000-8000-000000000180', 'f2620000-0000-4000-8000-000000000010', 800, 'submitted'),
  ('f2620000-0000-4000-8000-000000000281', 'f2620000-0000-4000-8000-000000000180', 'f2620000-0000-4000-8000-000000000011', 810, 'shortlisted');

-- A third sibling needs a distinct truck because request/truck is unique.
insert into public.airfnb_trucks
  (id, owner_id, slug, name, status, service_type, base_city)
values (
  'f2620000-0000-4000-8000-000000000013',
  'f2620000-0000-4000-8000-000000000002',
  'market-supplier-a-second', 'Market Supplier A Second', 'active', 'bar', 'Lisboa'
);
insert into public.airfnb_applications
  (id, request_id, truck_id, proposed_price, status)
values (
  'f2620000-0000-4000-8000-000000000282',
  'f2620000-0000-4000-8000-000000000180',
  'f2620000-0000-4000-8000-000000000013', 820, 'submitted'
);

do $catalog_acl$
begin
  if pg_catalog.has_table_privilege('authenticated', 'public.airfnb_applications', 'UPDATE')
     or pg_catalog.has_table_privilege('authenticated', 'public.airfnb_applications', 'DELETE')
     or not pg_catalog.has_column_privilege('authenticated', 'public.airfnb_applications', 'request_id', 'INSERT')
     or pg_catalog.has_column_privilege('authenticated', 'public.airfnb_applications', 'id', 'INSERT')
     or not pg_catalog.has_table_privilege('authenticated', 'public.airfnb_bookings', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'public.airfnb_bookings', 'INSERT')
     or not pg_catalog.has_table_privilege('authenticated', 'public.airfnb_booking_trucks', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'public.airfnb_booking_trucks', 'UPDATE')
     or pg_catalog.has_table_privilege('authenticated', 'public.airfnb_lock_fees', 'SELECT')
     or not pg_catalog.has_table_privilege('service_role', 'public.airfnb_lock_fees', 'SELECT,INSERT,UPDATE,DELETE')
     or not pg_catalog.has_function_privilege('authenticated', 'public.airfnb_can_submit_application(uuid,uuid)', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'public.airfnb_can_submit_application(uuid,uuid)', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', 'public.airfnb_can_submit_application(uuid,uuid)', 'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated', 'public.airfnb_own_application_truck()', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'public.airfnb_own_application_truck()', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', 'public.airfnb_own_application_truck()', 'EXECUTE') then
    raise exception 'marketplace runtime failed: table ACL matrix';
  end if;
end
$catalog_acl$;

-- Authenticated supplier can insert only for an owned active service and a
-- public or explicitly invited request. It cannot forge keys or mutate rows.
select pg_catalog.set_config('request.jwt.claim.sub', 'f2620000-0000-4000-8000-000000000002', true);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
do $authenticated_supplier_prerequisites$
begin
  if not public.airfnb_can_manage_truck(
    'f2620000-0000-4000-8000-000000000010'
  ) then
    raise exception 'marketplace runtime failed: supplier ownership helper';
  end if;
  if (
    select pg_catalog.count(*)
      from public.airfnb_v_truck_card as truck
     where truck.id = 'f2620000-0000-4000-8000-000000000010'
  ) <> 1 then
    raise exception 'marketplace runtime failed: active supplier card visibility';
  end if;
  if not public.airfnb_can_submit_application(
       'f2620000-0000-4000-8000-000000000190',
       'f2620000-0000-4000-8000-000000000010'
     )
     or not public.airfnb_can_submit_application(
       'f2620000-0000-4000-8000-000000000191',
       'f2620000-0000-4000-8000-000000000010'
     )
     or public.airfnb_can_submit_application(
       'f2620000-0000-4000-8000-000000000192',
       'f2620000-0000-4000-8000-000000000010'
     )
     or public.airfnb_can_submit_application(
       'f2620000-0000-4000-8000-000000000190',
       'f2620000-0000-4000-8000-000000000011'
     )
     or public.airfnb_can_submit_application(
       'f2620000-0000-4000-8000-000000000190',
       'f2620000-0000-4000-8000-000000000012'
     ) then
    raise exception 'marketplace runtime failed: application submission helper matrix';
  end if;
  if (select pg_catalog.count(*)
        from public.airfnb_own_application_truck() as truck
       where truck.truck_id = 'f2620000-0000-4000-8000-000000000010'
         and truck.truck_name = 'Market Supplier A Active'
         and truck.truck_status = 'active') <> 1 then
    raise exception 'marketplace runtime failed: own application truck projection';
  end if;
end
$authenticated_supplier_prerequisites$;
do $authenticated_application_insert$
declare
  v_context text;
  v_detail text;
  v_hint text;
begin
  insert into public.airfnb_applications(request_id, truck_id, proposed_price)
  values ('f2620000-0000-4000-8000-000000000190', 'f2620000-0000-4000-8000-000000000010', 500);
exception when others then
  get stacked diagnostics
    v_context = pg_exception_context,
    v_detail = pg_exception_detail,
    v_hint = pg_exception_hint;
  raise exception 'authenticated application insert failed: sqlstate=% message=% context=% detail=% hint=%',
    sqlstate, sqlerrm, v_context, v_detail, v_hint;
end
$authenticated_application_insert$;
insert into public.airfnb_applications(request_id, truck_id, proposed_price)
values ('f2620000-0000-4000-8000-000000000191', 'f2620000-0000-4000-8000-000000000010', 510);
do $application_denials$
begin
  begin
    insert into public.airfnb_applications(request_id, truck_id, proposed_price)
    values ('f2620000-0000-4000-8000-000000000192', 'f2620000-0000-4000-8000-000000000010', 520);
    raise exception 'private non-invited application unexpectedly inserted';
  exception when sqlstate '42501' then null;
  end;
  begin
    insert into public.airfnb_applications(request_id, truck_id, proposed_price)
    values ('f2620000-0000-4000-8000-000000000192', 'f2620000-0000-4000-8000-000000000012', 520);
    raise exception 'inactive service application unexpectedly inserted';
  exception when sqlstate '42501' then null;
  end;
  begin
    update public.airfnb_applications set proposed_price = 1
     where id = 'f2620000-0000-4000-8000-000000000200';
    raise exception 'authenticated application update unexpectedly allowed';
  exception when sqlstate '42501' then null;
  end;
  begin
    delete from public.airfnb_applications
     where id = 'f2620000-0000-4000-8000-000000000200';
    raise exception 'authenticated application delete unexpectedly allowed';
  exception when sqlstate '42501' then null;
  end;
  begin
    insert into public.airfnb_bookings(organizer_id)
    values ('f2620000-0000-4000-8000-000000000001');
    raise exception 'authenticated booking mutation unexpectedly allowed';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform pg_catalog.count(*) from public.airfnb_lock_fees;
    raise exception 'authenticated lock fee read unexpectedly allowed';
  exception when sqlstate '42501' then null;
  end;
end
$application_denials$;
reset role;

-- Organizer, DB-backed admin and DB-backed staff are valid decision actors.
select pg_catalog.set_config('request.jwt.claim.sub', 'f2620000-0000-4000-8000-000000000001', true);
set local role authenticated;
select public.airfnb_shortlist_application('f2620000-0000-4000-8000-000000000200');
select public.airfnb_reject_application('f2620000-0000-4000-8000-000000000201', 'runtime rejection');
reset role;
do $organizer_decisions$
begin
  if (select status from public.airfnb_applications where id = 'f2620000-0000-4000-8000-000000000200') <> 'shortlisted'
     or (select status from public.airfnb_applications where id = 'f2620000-0000-4000-8000-000000000201') <> 'rejected' then
    raise exception 'marketplace runtime failed: organizer decisions';
  end if;
end
$organizer_decisions$;

-- Unrelated, anonymous, missing-sub and metadata-only roles must all fail.
select pg_catalog.set_config('request.jwt.claim.sub', 'f2620000-0000-4000-8000-000000000006', true);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
do $unrelated_denial$
begin
  begin
    perform public.airfnb_accept_application('f2620000-0000-4000-8000-000000000210');
    raise exception 'unrelated organizer unexpectedly authorized';
  exception when sqlstate '42501' then null;
  end;
end
$unrelated_denial$;
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
do $missing_sub_denial$
begin
  begin
    perform public.airfnb_accept_application('f2620000-0000-4000-8000-000000000210');
    raise exception 'missing-sub caller unexpectedly authorized';
  exception when sqlstate '42501' then null;
  end;
end
$missing_sub_denial$;
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', 'f2620000-0000-4000-8000-000000000007', true);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
do $metadata_denial$
begin
  begin
    perform public.airfnb_accept_application('f2620000-0000-4000-8000-000000000210');
    raise exception 'metadata role unexpectedly authorized';
  exception when sqlstate '42501' then null;
  end;
end
$metadata_denial$;
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', '', true);
select pg_catalog.set_config('request.jwt.claim.role', 'anon', true);
set local role anon;
do $anon_denial$
begin
  begin
    perform public.airfnb_accept_application('f2620000-0000-4000-8000-000000000210');
    raise exception 'anonymous caller unexpectedly authorized';
  exception when sqlstate '42501' then null;
  end;
end
$anon_denial$;
reset role;

-- Fee values are read at execution time from settings.
update public.airfnb_platform_settings set value = '25'
 where key in ('lock_fee.platform_fee', 'lock_fee.organizer_share');
select pg_catalog.set_config('request.jwt.claim.sub', 'f2620000-0000-4000-8000-000000000001', true);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select public.airfnb_accept_application('f2620000-0000-4000-8000-000000000210');
reset role;

do $default_fee_and_retry$
declare
  v_before text;
  v_after text;
begin
  if (select pg_catalog.concat_ws(':', amount, platform_fee, organizer_share)
        from public.airfnb_lock_fees where application_id = 'f2620000-0000-4000-8000-000000000210') <> '50.00:25.00:25.00' then
    raise exception 'marketplace runtime failed: default fee split';
  end if;
  select pg_catalog.concat_ws(':',
    (select count(*) from public.airfnb_bookings where application_id = 'f2620000-0000-4000-8000-000000000210'),
    (select count(*) from public.airfnb_lock_fees where application_id = 'f2620000-0000-4000-8000-000000000210'),
    (select count(*) from public.airfnb_conversations where application_id = 'f2620000-0000-4000-8000-000000000210')
  ) into v_before;
  begin
    perform public.airfnb_accept_application('f2620000-0000-4000-8000-000000000210');
    raise exception 'same-application retry unexpectedly succeeded';
  exception when sqlstate '55000' then
    if sqlerrm <> 'application is not eligible for acceptance' then raise; end if;
  end;
  select pg_catalog.concat_ws(':',
    (select count(*) from public.airfnb_bookings where application_id = 'f2620000-0000-4000-8000-000000000210'),
    (select count(*) from public.airfnb_lock_fees where application_id = 'f2620000-0000-4000-8000-000000000210'),
    (select count(*) from public.airfnb_conversations where application_id = 'f2620000-0000-4000-8000-000000000210')
  ) into v_after;
  if v_after is distinct from v_before then
    raise exception 'same-application retry produced side effects';
  end if;
end
$default_fee_and_retry$;

update public.airfnb_platform_settings set value = '31' where key = 'lock_fee.platform_fee';
update public.airfnb_platform_settings set value = '7' where key = 'lock_fee.organizer_share';
select pg_catalog.set_config('request.jwt.claim.sub', 'f2620000-0000-4000-8000-000000000004', true);
set local role authenticated;
select public.airfnb_accept_application('f2620000-0000-4000-8000-000000000220');
reset role;

delete from public.airfnb_platform_settings
 where key in ('lock_fee.platform_fee', 'lock_fee.organizer_share');
select pg_catalog.set_config('request.jwt.claim.sub', 'f2620000-0000-4000-8000-000000000005', true);
set local role authenticated;
select public.airfnb_accept_application('f2620000-0000-4000-8000-000000000230');
reset role;

insert into public.airfnb_platform_settings(key, "group", description, value, secret)
values
  ('lock_fee.platform_fee', 'lock_fee', 'runtime', '', false),
  ('lock_fee.organizer_share', 'lock_fee', 'runtime', 'not-an-int', false);
select pg_catalog.set_config('request.jwt.claim.sub', '', true);
select pg_catalog.set_config('request.jwt.claim.role', 'service_role', true);
set local role authenticated;
select public.airfnb_accept_application('f2620000-0000-4000-8000-000000000240');
reset role;

update public.airfnb_platform_settings set value = '-5' where key = 'lock_fee.platform_fee';
update public.airfnb_platform_settings set value = '-8' where key = 'lock_fee.organizer_share';
set local role service_role;
select public.airfnb_accept_application('f2620000-0000-4000-8000-000000000250');
reset role;

do $fee_matrix$
begin
  if (select pg_catalog.concat_ws(':', amount, platform_fee, organizer_share)
        from public.airfnb_lock_fees where application_id = 'f2620000-0000-4000-8000-000000000220') <> '38.00:31.00:7.00'
     or (select pg_catalog.concat_ws(':', amount, platform_fee, organizer_share)
        from public.airfnb_lock_fees where application_id = 'f2620000-0000-4000-8000-000000000230') <> '50.00:25.00:25.00'
     or (select pg_catalog.concat_ws(':', amount, platform_fee, organizer_share)
        from public.airfnb_lock_fees where application_id = 'f2620000-0000-4000-8000-000000000240') <> '50.00:25.00:25.00'
     or (select pg_catalog.concat_ws(':', amount, platform_fee, organizer_share)
        from public.airfnb_lock_fees where application_id = 'f2620000-0000-4000-8000-000000000250') <> '0.00:0.00:0.00' then
    raise exception 'marketplace runtime failed: dynamic fee matrix';
  end if;
end
$fee_matrix$;

-- An oversized fee must fail after no durable mutation of the application or
-- any dependent side-effect table.
update public.airfnb_platform_settings set value = '2147483647' where key = 'lock_fee.platform_fee';
update public.airfnb_platform_settings set value = '0' where key = 'lock_fee.organizer_share';
select pg_catalog.set_config('request.jwt.claim.sub', 'f2620000-0000-4000-8000-000000000001', true);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
do $oversized_atomic$
begin
  begin
    perform public.airfnb_accept_application('f2620000-0000-4000-8000-000000000260');
    raise exception 'oversized fee unexpectedly accepted';
  exception when sqlstate '22003' then null;
  end;
end
$oversized_atomic$;
reset role;
do $oversized_assert$
begin
  if (select status from public.airfnb_applications where id = 'f2620000-0000-4000-8000-000000000260') <> 'submitted'
     or exists (select 1 from public.airfnb_bookings where application_id = 'f2620000-0000-4000-8000-000000000260')
     or exists (select 1 from public.airfnb_lock_fees where application_id = 'f2620000-0000-4000-8000-000000000260')
     or exists (select 1 from public.airfnb_conversations where application_id = 'f2620000-0000-4000-8000-000000000260') then
    raise exception 'oversized fee failure was not atomic';
  end if;
end
$oversized_assert$;

-- Restore a safe fee and prove one-slot and multi-slot terminal semantics.
update public.airfnb_platform_settings set value = '25'
 where key in ('lock_fee.platform_fee', 'lock_fee.organizer_share');
select pg_catalog.set_config('request.jwt.claim.sub', 'f2620000-0000-4000-8000-000000000001', true);
set local role authenticated;
select public.airfnb_accept_application('f2620000-0000-4000-8000-000000000270');
do $final_slot_loser$
begin
  begin
    perform public.airfnb_accept_application('f2620000-0000-4000-8000-000000000271');
    raise exception 'final-slot loser unexpectedly accepted';
  exception when sqlstate '55000' then
    if sqlerrm <> 'request has no remaining slots' then raise; end if;
  end;
end
$final_slot_loser$;
reset role;
do $final_slot_assert$
begin
  if (select status from public.airfnb_applications where id = 'f2620000-0000-4000-8000-000000000271') <> 'shortlisted'
     or exists (select 1 from public.airfnb_bookings where application_id = 'f2620000-0000-4000-8000-000000000271')
     or exists (select 1 from public.airfnb_lock_fees where application_id = 'f2620000-0000-4000-8000-000000000271') then
    raise exception 'final-slot loser changed application state';
  end if;
end
$final_slot_assert$;

set local role authenticated;
select public.airfnb_accept_application('f2620000-0000-4000-8000-000000000280');
reset role;
do $multi_first$
begin
  if (select status from public.airfnb_event_requests where id = 'f2620000-0000-4000-8000-000000000180') <> 'open'
     or (select status from public.airfnb_applications where id = 'f2620000-0000-4000-8000-000000000281') <> 'shortlisted'
     or (select status from public.airfnb_applications where id = 'f2620000-0000-4000-8000-000000000282') <> 'submitted' then
    raise exception 'non-winning sibling changed state';
  end if;
end
$multi_first$;
set local role authenticated;
select public.airfnb_accept_application('f2620000-0000-4000-8000-000000000281');
reset role;
do $multi_terminal$
begin
  if (select status from public.airfnb_event_requests where id = 'f2620000-0000-4000-8000-000000000180') <> 'awarded'
     or (select count(*) from public.airfnb_applications
          where request_id = 'f2620000-0000-4000-8000-000000000180' and status = 'accepted') <> 2
     or (select status from public.airfnb_applications where id = 'f2620000-0000-4000-8000-000000000282') <> 'submitted' then
    raise exception 'marketplace runtime failed: exactly slots_needed accepted';
  end if;
end
$multi_terminal$;

-- The supplier projection is owner-only, authenticated-only, excludes signed
-- service role calls, and is not executable by the database service role.
select pg_catalog.set_config('request.jwt.claim.sub', 'f2620000-0000-4000-8000-000000000002', true);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
do $supplier_projection_owner$
begin
  if (select count(*) from public.airfnb_supplier_lock_fee('f2620000-0000-4000-8000-000000000210')) <> 1 then
    raise exception 'marketplace runtime failed: supplier lock fee owner projection';
  end if;
end
$supplier_projection_owner$;
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', 'f2620000-0000-4000-8000-000000000003', true);
set local role authenticated;
do $supplier_projection_cross_tenant$
begin
  if (select count(*) from public.airfnb_supplier_lock_fee('f2620000-0000-4000-8000-000000000210')) <> 0 then
    raise exception 'supplier lock fee leaked cross-tenant data';
  end if;
end
$supplier_projection_cross_tenant$;
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
do $supplier_projection_missing_sub$
begin
  if (select count(*) from public.airfnb_supplier_lock_fee('f2620000-0000-4000-8000-000000000210')) <> 0 then
    raise exception 'supplier lock fee leaked to missing-sub caller';
  end if;
  if (select count(*) from public.airfnb_own_application_truck()) <> 0 then
    raise exception 'own application truck leaked to missing-sub caller';
  end if;
end
$supplier_projection_missing_sub$;
reset role;

select pg_catalog.set_config('request.jwt.claim.role', 'service_role', true);
set local role authenticated;
do $supplier_projection_signed_service$
begin
  if (select count(*) from public.airfnb_supplier_lock_fee('f2620000-0000-4000-8000-000000000210')) <> 0 then
    raise exception 'supplier lock fee leaked to signed service role';
  end if;
  if (select count(*) from public.airfnb_own_application_truck()) <> 0 then
    raise exception 'own application truck leaked to signed service role';
  end if;
end
$supplier_projection_signed_service$;
reset role;

set local role service_role;
do $supplier_projection_service_acl$
begin
  begin
    perform public.airfnb_supplier_lock_fee('f2620000-0000-4000-8000-000000000210');
    raise exception 'service role unexpectedly executed supplier lock fee projection';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform public.airfnb_own_application_truck();
    raise exception 'service role unexpectedly executed own application truck projection';
  exception when sqlstate '42501' then null;
  end;
end
$supplier_projection_service_acl$;
reset role;

rollback;
\echo 'marketplace workflow runtime passed'
