\set ON_ERROR_STOP on

begin;
set local statement_timeout = '60s';

do $guard$
begin
  if pg_catalog.current_database() !~ '^fb_tailor_stripe_[0-9]+_[0-9]+_(legacy|old)$'
     or exists (select 1 from auth.users where id::text like 'f2660000-0000-4000-8000-%') then
    raise exception 'stripe runtime refused unsafe fixture target';
  end if;
end
$guard$;

insert into auth.users(id,email,raw_user_meta_data) values
  ('f2660000-0000-4000-8000-000000000001','stripe-organizer@example.invalid','{}'),
  ('f2660000-0000-4000-8000-000000000002','stripe-supplier@example.invalid','{}');
update public.airfnb_profiles
   set role=case when id='f2660000-0000-4000-8000-000000000001'
                 then 'organizer'::public.airfnb_user_role
                 else 'owner'::public.airfnb_user_role end
 where id in ('f2660000-0000-4000-8000-000000000001','f2660000-0000-4000-8000-000000000002');

insert into public.airfnb_trucks(id,owner_id,slug,name,status,service_type,base_city)
values ('f2660000-0000-4000-8000-000000000010','f2660000-0000-4000-8000-000000000002',
        'stripe-runtime','Stripe Runtime','active','food_truck','Lisboa');

insert into public.airfnb_event_requests(
  id,organizer_id,title,start_at,end_at,expected_pax,slots_needed,
  applications_deadline,status,visibility,application_response_window_hours,city
) values
  ('f2660000-0000-4000-8000-000000000100','f2660000-0000-4000-8000-000000000001',
   'Stripe primary',pg_catalog.now() + interval '2 days',pg_catalog.now() + interval '2 days 6 hours',100,1,
   pg_catalog.now() + interval '1 day','awarded','public',48,'Lisboa'),
  ('f2660000-0000-4000-8000-000000000101','f2660000-0000-4000-8000-000000000001',
   'Stripe secondary',pg_catalog.now() + interval '3 days',pg_catalog.now() + interval '3 days 6 hours',100,1,
   pg_catalog.now() + interval '1 day','awarded','public',48,'Lisboa');

insert into public.airfnb_applications(id,request_id,truck_id,proposed_price,status,created_at,updated_at)
values
  ('f2660000-0000-4000-8000-000000000200','f2660000-0000-4000-8000-000000000100',
   'f2660000-0000-4000-8000-000000000010',500,'accepted',pg_catalog.now() - interval '1 hour',pg_catalog.now() - interval '1 hour'),
  ('f2660000-0000-4000-8000-000000000201','f2660000-0000-4000-8000-000000000101',
   'f2660000-0000-4000-8000-000000000010',500,'accepted',pg_catalog.now() - interval '1 hour',pg_catalog.now() - interval '1 hour');

insert into public.airfnb_bookings(
  id,organizer_id,status,starts_at,ends_at,total_amount,currency,application_id,created_at,updated_at
) values
  ('f2660000-0000-4000-8000-000000000300','f2660000-0000-4000-8000-000000000001',
   'pending_lock_fee',pg_catalog.now() + interval '2 days',pg_catalog.now() + interval '2 days 6 hours',500,'EUR',
   'f2660000-0000-4000-8000-000000000200',pg_catalog.now() - interval '1 hour',pg_catalog.now() - interval '1 hour'),
  ('f2660000-0000-4000-8000-000000000301','f2660000-0000-4000-8000-000000000001',
   'pending_lock_fee',pg_catalog.now() + interval '3 days',pg_catalog.now() + interval '3 days 6 hours',500,'EUR',
   'f2660000-0000-4000-8000-000000000201',pg_catalog.now() - interval '1 hour',pg_catalog.now() - interval '1 hour');

insert into public.airfnb_lock_fees(
  id,application_id,amount,currency,due_until,status,created_at,platform_fee,organizer_share
) values
  ('f2660000-0000-4000-8000-000000000400','f2660000-0000-4000-8000-000000000200',
   50,'EUR',pg_catalog.now() + interval '1 day','pending',pg_catalog.now() - interval '1 hour',25,25),
  ('f2660000-0000-4000-8000-000000000401','f2660000-0000-4000-8000-000000000201',
   50,'EUR',pg_catalog.now() + interval '1 day','pending',pg_catalog.now() - interval '1 hour',25,25);

-- API roles can call only the service-role RPC; they cannot mutate its tables.
set local role anon;
do $anon_rpc_denied$ begin
  begin
    perform public.airfnb_reconcile_stripe_event('evt-denied','checkout.session.completed',
      pg_catalog.now() - interval '30 minutes','f2660000-0000-4000-8000-000000000200',
      'f2660000-0000-4000-8000-000000000400','f2660000-0000-4000-8000-000000000300',
      'pi-denied',5000,'EUR','paid',0);
    raise exception 'anon unexpectedly executed reconciliation';
  exception when sqlstate '42501' then null; end;
end $anon_rpc_denied$;
reset role;

set local role authenticated;
do $authenticated_rpc_denied$ begin
  begin
    perform public.airfnb_reconcile_stripe_event('evt-denied','checkout.session.completed',
      pg_catalog.now() - interval '30 minutes','f2660000-0000-4000-8000-000000000200',
      'f2660000-0000-4000-8000-000000000400','f2660000-0000-4000-8000-000000000300',
      'pi-denied',5000,'EUR','paid',0);
    raise exception 'authenticated unexpectedly executed reconciliation';
  exception when sqlstate '42501' then null; end;
end $authenticated_rpc_denied$;
reset role;

set local role service_role;
do $service_direct_dml_denied$ begin
  begin
    update public.airfnb_lock_fees set amount=amount where id='f2660000-0000-4000-8000-000000000400';
    raise exception 'service role unexpectedly updated lock fee';
  exception when sqlstate '42501' then null; end;
  begin
    insert into public.airfnb_payments(id) values ('f2660000-0000-4000-8000-000000000999');
    raise exception 'service role unexpectedly inserted payment';
  exception when sqlstate '42501' then null; end;
end $service_direct_dml_denied$;

select public.airfnb_reconcile_stripe_event(
  'evt-primary','checkout.session.completed',pg_catalog.now() - interval '30 minutes',
  'f2660000-0000-4000-8000-000000000200','f2660000-0000-4000-8000-000000000400',
  'f2660000-0000-4000-8000-000000000300','pi-primary',5000,'eur','paid',0
);
reset role;

do $initial_payment$
begin
  if (select count(*) from public.airfnb_payments where provider_ref='pi-primary') <> 1
     or (select status from public.airfnb_lock_fees where id='f2660000-0000-4000-8000-000000000400') <> 'paid'
     or (select status from public.airfnb_bookings where id='f2660000-0000-4000-8000-000000000300') <> 'confirmed'
     or (select processing_result from public.airfnb_stripe_events where event_id='evt-primary') <> 'payment_confirmed' then
    raise exception 'initial payment reconciliation failed';
  end if;
end
$initial_payment$;
\echo 'INITIAL_PAYMENT_VERIFIED'

set local role service_role;
select public.airfnb_reconcile_stripe_event(
  'evt-primary','checkout.session.completed',pg_catalog.now() - interval '30 minutes',
  'f2660000-0000-4000-8000-000000000200','f2660000-0000-4000-8000-000000000400',
  'f2660000-0000-4000-8000-000000000300','pi-primary',5000,'EUR','paid',0
);
do $conflicting_duplicate$ begin
  begin
    perform public.airfnb_reconcile_stripe_event(
      'evt-primary','checkout.session.completed',pg_catalog.now() - interval '30 minutes',
      'f2660000-0000-4000-8000-000000000200','f2660000-0000-4000-8000-000000000400',
      'f2660000-0000-4000-8000-000000000300','pi-primary',4900,'EUR','paid',0);
    raise exception 'conflicting duplicate unexpectedly succeeded';
  exception when sqlstate '23505' then null; end;
end $conflicting_duplicate$;
select public.airfnb_reconcile_stripe_event(
  'evt-payment-replay','checkout.session.completed',pg_catalog.now() - interval '29 minutes',
  'f2660000-0000-4000-8000-000000000200','f2660000-0000-4000-8000-000000000400',
  'f2660000-0000-4000-8000-000000000300','pi-primary',5000,'EUR','paid',0
);
reset role;
do $duplicate_assert$ begin
  if (select count(*) from public.airfnb_payments where provider_ref='pi-primary') <> 1
     or (select count(*) from public.airfnb_stripe_events where event_id='evt-primary') <> 1
     or (select processing_result from public.airfnb_stripe_events where event_id='evt-payment-replay') <> 'payment_replay' then
    raise exception 'duplicate/conflict matrix failed';
  end if;
end $duplicate_assert$;
\echo 'DUPLICATE_CONFLICT_VERIFIED'

set local role service_role;
do $refund_before_payment$ begin
  begin
    perform public.airfnb_reconcile_stripe_event(
      'evt-refund-before','charge.refunded',pg_catalog.now() - interval '20 minutes',
      'f2660000-0000-4000-8000-000000000201','f2660000-0000-4000-8000-000000000401',
      'f2660000-0000-4000-8000-000000000301','pi-secondary',5000,'EUR','succeeded',1000);
    raise exception 'refund-before-payment unexpectedly succeeded';
  exception when sqlstate '55000' then null; end;
end $refund_before_payment$;
reset role;
do $refund_before_atomic$ begin
  if exists (select 1 from public.airfnb_stripe_events where event_id='evt-refund-before')
     or exists (select 1 from public.airfnb_payments where provider_ref='pi-secondary') then
    raise exception 'refund-before-payment was not atomic';
  end if;
end $refund_before_atomic$;

set local role service_role;
select public.airfnb_reconcile_stripe_event(
  'evt-partial-1','charge.refunded',pg_catalog.now() - interval '20 minutes',
  'f2660000-0000-4000-8000-000000000200','f2660000-0000-4000-8000-000000000400',
  'f2660000-0000-4000-8000-000000000300','pi-primary',5000,'EUR','succeeded',1000);
select public.airfnb_reconcile_stripe_event(
  'evt-partial-equal','charge.refunded',pg_catalog.now() - interval '19 minutes',
  'f2660000-0000-4000-8000-000000000200','f2660000-0000-4000-8000-000000000400',
  'f2660000-0000-4000-8000-000000000300','pi-primary',5000,'EUR','succeeded',1000);
select public.airfnb_reconcile_stripe_event(
  'evt-partial-stale','charge.refunded',pg_catalog.now() - interval '18 minutes',
  'f2660000-0000-4000-8000-000000000200','f2660000-0000-4000-8000-000000000400',
  'f2660000-0000-4000-8000-000000000300','pi-primary',5000,'EUR','succeeded',500);
select public.airfnb_reconcile_stripe_event(
  'evt-full','charge.refunded',pg_catalog.now() - interval '17 minutes',
  'f2660000-0000-4000-8000-000000000200','f2660000-0000-4000-8000-000000000400',
  'f2660000-0000-4000-8000-000000000300','pi-primary',5000,'EUR','succeeded',5000);
select public.airfnb_reconcile_stripe_event(
  'evt-after-full','charge.refunded',pg_catalog.now() - interval '16 minutes',
  'f2660000-0000-4000-8000-000000000200','f2660000-0000-4000-8000-000000000400',
  'f2660000-0000-4000-8000-000000000300','pi-primary',5000,'EUR','succeeded',2000);
reset role;

do $refund_assert$
begin
  if (select refunded_amount from public.airfnb_payments where provider_ref='pi-primary') <> 50
     or (select status from public.airfnb_payments where provider_ref='pi-primary') <> 'refunded'
     or (select status from public.airfnb_lock_fees where id='f2660000-0000-4000-8000-000000000400') <> 'refunded'
     or (select status from public.airfnb_bookings where id='f2660000-0000-4000-8000-000000000300') <> 'refunded'
     or (select processing_result from public.airfnb_stripe_events where event_id='evt-partial-equal') <> 'refund_replay'
     or (select processing_result from public.airfnb_stripe_events where event_id='evt-partial-stale') <> 'stale_refund_ignored'
     or (select processing_result from public.airfnb_stripe_events where event_id='evt-after-full') <> 'stale_refund_ignored' then
    raise exception 'refund monotonicity matrix failed';
  end if;
end
$refund_assert$;
\echo 'REFUND_MONOTONICITY_VERIFIED'

set local role service_role;
do $invalid_matrix$
declare v_events bigint := (select count(*) from public.airfnb_stripe_events);
begin
  begin
    perform public.airfnb_reconcile_stripe_event(
      'evt-invalid-currency','checkout.session.completed',pg_catalog.now() - interval '10 minutes',
      'f2660000-0000-4000-8000-000000000201','f2660000-0000-4000-8000-000000000401',
      'f2660000-0000-4000-8000-000000000301','pi-secondary',5000,'USD','paid',0);
    raise exception 'non-EUR unexpectedly accepted'; exception when sqlstate '22023' then null; end;
  begin
    perform public.airfnb_reconcile_stripe_event(
      'evt-invalid-amount','checkout.session.completed',pg_catalog.now() - interval '10 minutes',
      'f2660000-0000-4000-8000-000000000201','f2660000-0000-4000-8000-000000000401',
      'f2660000-0000-4000-8000-000000000301','pi-secondary',0,'EUR','paid',0);
    raise exception 'zero amount unexpectedly accepted'; exception when sqlstate '22023' then null; end;
  begin
    perform public.airfnb_reconcile_stripe_event(
      'evt-invalid-status','checkout.session.completed',pg_catalog.now() - interval '10 minutes',
      'f2660000-0000-4000-8000-000000000201','f2660000-0000-4000-8000-000000000401',
      'f2660000-0000-4000-8000-000000000301','pi-secondary',5000,'EUR','unpaid',0);
    raise exception 'unpaid event unexpectedly accepted'; exception when sqlstate '22023' then null; end;
  if (select count(*) from public.airfnb_stripe_events) <> v_events then
    raise exception 'invalid input left ledger residue';
  end if;
end
$invalid_matrix$;
reset role;
\echo 'INVALID_MATRIX_VERIFIED'

rollback;
\echo 'stripe canonical runtime passed'
