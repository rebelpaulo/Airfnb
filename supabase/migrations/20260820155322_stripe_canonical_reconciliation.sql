-- Canonical, fail-closed Stripe reconciliation immediately after the verified
-- Marketplace workflow. This migration accepts only the exact pre-Stripe
-- legacy state, the 2026-08-18 Stripe candidate, or this final state.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local idle_in_transaction_session_timeout = '60s';

lock table
  public.airfnb_applications,
  public.airfnb_bookings,
  public.airfnb_lock_fees,
  public.airfnb_payments
in access exclusive mode;

do $lock_optional_ledger$
begin
  if pg_catalog.to_regclass('public.airfnb_stripe_events') is not null then
    execute 'lock table public.airfnb_stripe_events in access exclusive mode';
  end if;
end
$lock_optional_ledger$;

create temporary table airfnb_stripe_protected_functions_20260820
on commit drop as
select procedure.oid,
       procedure.proowner,
       procedure.proacl,
       procedure.prosecdef,
       procedure.provolatile,
       procedure.proconfig,
       pg_catalog.md5(procedure.prosrc) as body_hash
  from pg_catalog.pg_proc as procedure
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = procedure.pronamespace
 where namespace.nspname = 'public'
   and procedure.proname in (
     'airfnb_accept_application',
     'airfnb_expire_stale_lock_fees',
     'airfnb_calculate_lock_fee',
     'airfnb_supplier_lock_fee',
     'airfnb_can_submit_application',
     'airfnb_own_application_truck'
   );

create temporary table airfnb_stripe_protected_relations_20260820
on commit drop as
select relation.oid,
       relation.relowner,
       relation.relacl,
       relation.relrowsecurity,
       relation.relforcerowsecurity
  from pg_catalog.pg_class as relation
 where relation.oid in (
   'public.airfnb_applications'::pg_catalog.regclass,
   'public.airfnb_bookings'::pg_catalog.regclass
 );

do $preconditions$
declare
  v_owner oid := (
    select relation.relowner from pg_catalog.pg_class as relation
     where relation.oid = 'public.airfnb_payments'::pg_catalog.regclass
  );
  v_anon oid := (select oid from pg_catalog.pg_roles where rolname = 'anon');
  v_authenticated oid := (select oid from pg_catalog.pg_roles where rolname = 'authenticated');
  v_service_role oid := (select oid from pg_catalog.pg_roles where rolname = 'service_role');
  v_payment_columns integer := (
    select pg_catalog.count(*) from pg_catalog.pg_attribute
     where attrelid = 'public.airfnb_payments'::pg_catalog.regclass
       and attnum > 0 and not attisdropped
  );
  v_ledger oid := pg_catalog.to_regclass('public.airfnb_stripe_events');
  v_has_ledger boolean := v_ledger is not null;
  v_rpc oid := pg_catalog.to_regprocedure(
    'public.airfnb_reconcile_stripe_event(text,text,timestamp with time zone,uuid,uuid,uuid,text,bigint,text,text,bigint)'
  );
  v_legacy boolean := false;
  v_old boolean := false;
  v_final boolean := false;
begin
  if v_owner is null or v_anon is null or v_authenticated is null
     or v_service_role is null then
    raise exception 'stripe reconciliation refused: owner or API role is missing';
  end if;

  if v_owner <> (select oid from pg_catalog.pg_roles where rolname = current_user)
     or not exists (
       select 1 from pg_catalog.pg_roles
        where oid = v_owner and rolbypassrls
     ) or exists (
       select 1
         from unnest(array[
           'public.airfnb_applications'::pg_catalog.regclass,
           'public.airfnb_bookings'::pg_catalog.regclass,
           'public.airfnb_lock_fees'::pg_catalog.regclass,
           'public.airfnb_payments'::pg_catalog.regclass
         ]) as target(relation_oid)
         join pg_catalog.pg_class as relation on relation.oid = target.relation_oid
        where relation.relowner <> v_owner
     ) then
    raise exception 'stripe reconciliation refused: trusted owner alignment drifted';
  end if;

  if exists (
    select 1
      from unnest(array[
        'public.airfnb_applications'::pg_catalog.regclass,
        'public.airfnb_bookings'::pg_catalog.regclass,
        'public.airfnb_lock_fees'::pg_catalog.regclass,
        'public.airfnb_payments'::pg_catalog.regclass
      ]) as target(relation_oid)
      join pg_catalog.pg_class as relation on relation.oid = target.relation_oid
     where relation.relkind <> 'r'
        or not relation.relrowsecurity
        or relation.relforcerowsecurity
  ) then
    raise exception 'stripe reconciliation refused: base relation or RLS mode drifted';
  end if;

  -- Pin the immediate Marketplace predecessor and the writers that must keep
  -- working after service-role direct DML is removed.
  if not exists (
    select 1 from pg_catalog.pg_proc as procedure
     where procedure.oid = 'public.airfnb_supplier_lock_fee(uuid)'::pg_catalog.regprocedure
       and procedure.proowner = v_owner
       and procedure.prosecdef and procedure.provolatile = 's'
       and procedure.proconfig = array['search_path=""']::text[]
       and pg_catalog.md5(procedure.prosrc) = 'e73cb472f9bcc4eff83ced6b3357b47d'
       and pg_catalog.has_function_privilege(v_authenticated, procedure.oid, 'EXECUTE')
       and not pg_catalog.has_function_privilege(v_anon, procedure.oid, 'EXECUTE')
       and not pg_catalog.has_function_privilege(v_service_role, procedure.oid, 'EXECUTE')
  ) or not exists (
    select 1 from pg_catalog.pg_proc as procedure
     where procedure.oid = 'public.airfnb_can_submit_application(uuid,uuid)'::pg_catalog.regprocedure
       and procedure.proowner = v_owner
       and procedure.prosecdef and procedure.provolatile = 's'
       and procedure.proconfig = array['search_path=""']::text[]
       and pg_catalog.md5(procedure.prosrc) = 'c96f49df5f1b05fabea73bfdbf534a74'
  ) or not exists (
    select 1 from pg_catalog.pg_proc as procedure
     where procedure.oid = 'public.airfnb_expire_stale_lock_fees()'::pg_catalog.regprocedure
       and procedure.proowner = v_owner and procedure.prosecdef
       and procedure.provolatile = 'v'
       and procedure.proconfig = array['search_path=public']::text[]
       and pg_catalog.md5(procedure.prosrc) = '0c268c7b7201c1d64e83143d23961c95'
       and pg_catalog.has_function_privilege(v_service_role, procedure.oid, 'EXECUTE')
       and not pg_catalog.has_function_privilege(v_anon, procedure.oid, 'EXECUTE')
       and not pg_catalog.has_function_privilege(v_authenticated, procedure.oid, 'EXECUTE')
  ) or not exists (
    select 1 from pg_catalog.pg_proc as procedure
     where procedure.oid = 'public.airfnb_calculate_lock_fee(uuid)'::pg_catalog.regprocedure
       and procedure.proowner = v_owner and procedure.prosecdef
       and procedure.provolatile = 's'
       and procedure.proconfig = array['search_path=public']::text[]
       and pg_catalog.md5(procedure.prosrc) = '5955bc4f93e2f63ff040f47a756ff58f'
  ) then
    raise exception 'stripe reconciliation refused: Marketplace predecessor or writer drifted';
  end if;

  if (select pg_catalog.count(*) from pg_catalog.pg_attribute
       where attrelid = 'public.airfnb_lock_fees'::pg_catalog.regclass
         and attnum > 0 and not attisdropped) <> 13
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute
          where attrelid = 'public.airfnb_bookings'::pg_catalog.regclass
            and attnum > 0 and not attisdropped) <> 15
     or not exists (
       select 1 from pg_catalog.pg_indexes
        where schemaname = 'public' and tablename = 'airfnb_bookings'
          and indexname = 'airfnb_bookings_application_unique'
          and indexdef = 'CREATE UNIQUE INDEX airfnb_bookings_application_unique ON public.airfnb_bookings USING btree (application_id) WHERE (application_id IS NOT NULL)'
     ) then
    raise exception 'stripe reconciliation refused: Marketplace schema drifted';
  end if;

  v_legacy :=
    v_payment_columns = 11
    and not v_has_ledger
    and v_rpc is null
    and exists (
      select 1 from pg_catalog.pg_indexes
       where schemaname = 'public' and tablename = 'airfnb_payments'
         and indexname = 'airfnb_payments_provider_ref_unique'
         and indexdef like '%WHERE (provider_ref IS NOT NULL)'
    )
    and exists (
      select 1 from pg_catalog.pg_indexes
       where schemaname = 'public' and tablename = 'airfnb_lock_fees'
         and indexname = 'airfnb_lock_fees_provider_ref_uniq'
         and indexdef like '%WHERE (provider_ref IS NOT NULL)'
    )
    and not exists (
      select 1 from pg_catalog.pg_constraint
       where conrelid = 'public.airfnb_payments'::pg_catalog.regclass
         and conname in (
           'airfnb_payments_provider_ref_key','airfnb_payments_lock_fee_key',
           'airfnb_payments_refunded_amount_bounds','airfnb_payments_currency_eur'
         )
    );

  v_old :=
    v_payment_columns = 15
    and v_has_ledger and v_rpc is not null
    and not exists (
      select 1 from pg_catalog.pg_constraint
       where conname in ('airfnb_payments_currency_eur','airfnb_lock_fees_currency_eur','airfnb_stripe_events_currency_eur')
         and conrelid in (
           'public.airfnb_payments'::pg_catalog.regclass,
           'public.airfnb_lock_fees'::pg_catalog.regclass,
           v_ledger
         )
    )
    and exists (
      select 1 from pg_catalog.pg_proc as procedure
       where procedure.oid = v_rpc
         and procedure.proowner = v_owner
         and procedure.prosecdef and procedure.provolatile = 'v'
         and procedure.proconfig = array['search_path=pg_catalog, public']::text[]
         and pg_catalog.md5(procedure.prosrc) = '8ed2d10c58778e53fd40ce9b4628a42d'
    )
    and pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_payments', 'SELECT,INSERT,UPDATE,DELETE')
    and pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_lock_fees', 'SELECT,INSERT,UPDATE,DELETE');

  v_final :=
    v_payment_columns = 15
    and v_has_ledger and v_rpc is not null
    and exists (
      select 1 from pg_catalog.pg_proc as procedure
       where procedure.oid = v_rpc
         and procedure.proowner = v_owner
         and procedure.prosecdef and procedure.provolatile = 'v'
         and procedure.proconfig = array['search_path=""']::text[]
    )
    and exists (
      select 1 from pg_catalog.pg_constraint
       where conrelid = 'public.airfnb_payments'::pg_catalog.regclass
         and conname = 'airfnb_payments_currency_eur'
    )
    and exists (
      select 1 from pg_catalog.pg_constraint
       where conrelid = 'public.airfnb_lock_fees'::pg_catalog.regclass
         and conname = 'airfnb_lock_fees_currency_eur'
    )
    and exists (
      select 1 from pg_catalog.pg_constraint
       where conrelid = v_ledger
         and conname = 'airfnb_stripe_events_currency_eur'
    )
    and pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_payments', 'SELECT')
    and not pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_payments', 'INSERT,UPDATE,DELETE')
    and pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_lock_fees', 'SELECT')
    and not pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_lock_fees', 'INSERT,UPDATE,DELETE');

  if (v_legacy::integer + v_old::integer + v_final::integer) <> 1 then
    raise exception 'stripe reconciliation refused: mixed or unknown prestate';
  end if;

  if v_legacy and exists (select 1 from public.airfnb_payments) then
    raise exception 'stripe reconciliation refused: legacy payment binding is ambiguous';
  end if;

  if exists (
       select 1 from public.airfnb_lock_fees
        where currency is null or pg_catalog.upper(pg_catalog.btrim(currency::text)) <> 'EUR'
     ) or exists (
       select 1 from public.airfnb_bookings
        where application_id is not null
          and (currency is null or pg_catalog.upper(pg_catalog.btrim(currency::text)) <> 'EUR')
     ) or (not v_legacy and exists (
       select 1 from public.airfnb_payments
        where currency is not null
          and pg_catalog.upper(pg_catalog.btrim(currency::text)) <> 'EUR'
     )) then
    raise exception 'stripe reconciliation refused: non-EUR financial data exists';
  end if;

  if exists (
       select provider_ref from public.airfnb_lock_fees
        where provider_ref is not null group by provider_ref having pg_catalog.count(*) > 1
     ) or exists (
       select provider_ref from public.airfnb_payments
        where provider_ref is not null group by provider_ref having pg_catalog.count(*) > 1
     ) then
    raise exception 'stripe reconciliation refused: duplicate financial binding exists';
  end if;

  if not v_legacy then
    if exists (
      select lock_fee_id from public.airfnb_payments
       where lock_fee_id is not null
       group by lock_fee_id having pg_catalog.count(*) > 1
    ) then
      raise exception 'stripe reconciliation refused: duplicate financial binding exists';
    end if;

    if exists (
      select 1 from public.airfnb_payments
       where refunded_amount < 0
          or amount is not null and refunded_amount > amount
          or lock_fee_id is not null and application_id is null
    ) then
      raise exception 'stripe reconciliation refused: invalid payment/refund binding exists';
    end if;
  end if;
end
$preconditions$;

do $legacy_shape$
begin
  if not exists (
    select 1 from pg_catalog.pg_attribute
     where attrelid = 'public.airfnb_payments'::pg_catalog.regclass
       and attname = 'application_id' and not attisdropped
  ) then
    alter table public.airfnb_payments
      add column application_id uuid references public.airfnb_applications(id),
      add column lock_fee_id uuid references public.airfnb_lock_fees(id),
      add column refunded_amount numeric(10,2) not null default 0,
      add column last_provider_event_at timestamptz;
  end if;
end
$legacy_shape$;

drop index if exists public.airfnb_payments_provider_ref_unique;
drop index if exists public.airfnb_lock_fees_provider_ref_uniq;

do $constraints$
begin
  if not exists (select 1 from pg_catalog.pg_constraint where conrelid='public.airfnb_payments'::pg_catalog.regclass and conname='airfnb_payments_refunded_amount_bounds') then
    alter table public.airfnb_payments add constraint airfnb_payments_refunded_amount_bounds
      check (refunded_amount >= 0 and (amount is null or refunded_amount <= amount));
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint where conrelid='public.airfnb_payments'::pg_catalog.regclass and conname='airfnb_payments_lock_fee_key') then
    alter table public.airfnb_payments add constraint airfnb_payments_lock_fee_key unique(lock_fee_id);
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint where conrelid='public.airfnb_payments'::pg_catalog.regclass and conname='airfnb_payments_provider_ref_key') then
    alter table public.airfnb_payments add constraint airfnb_payments_provider_ref_key unique(provider_ref);
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint where conrelid='public.airfnb_lock_fees'::pg_catalog.regclass and conname='airfnb_lock_fees_provider_ref_key') then
    alter table public.airfnb_lock_fees add constraint airfnb_lock_fees_provider_ref_key unique(provider_ref);
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint where conrelid='public.airfnb_payments'::pg_catalog.regclass and conname='airfnb_payments_currency_eur') then
    alter table public.airfnb_payments add constraint airfnb_payments_currency_eur
      check (currency is null or pg_catalog.upper(pg_catalog.btrim(currency::text)) = 'EUR');
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint where conrelid='public.airfnb_lock_fees'::pg_catalog.regclass and conname='airfnb_lock_fees_currency_eur') then
    alter table public.airfnb_lock_fees add constraint airfnb_lock_fees_currency_eur
      check (pg_catalog.upper(pg_catalog.btrim(currency::text)) = 'EUR');
  end if;
end
$constraints$;

alter table public.airfnb_lock_fees alter column currency set not null;

create table if not exists public.airfnb_stripe_events (
  event_id text primary key,
  event_type text not null,
  event_created_at timestamptz not null,
  provider_ref text not null,
  application_id uuid not null references public.airfnb_applications(id),
  lock_fee_id uuid not null references public.airfnb_lock_fees(id),
  booking_id uuid not null references public.airfnb_bookings(id),
  amount_minor bigint not null check (amount_minor > 0),
  currency char(3) not null,
  payment_status text not null,
  refunded_amount_minor bigint not null default 0
    check (refunded_amount_minor >= 0 and refunded_amount_minor <= amount_minor),
  processing_result text,
  processed_at timestamptz,
  received_at timestamptz not null default pg_catalog.now()
);

create index if not exists airfnb_stripe_events_provider_time_idx
  on public.airfnb_stripe_events(provider_ref, event_created_at desc);

do $ledger_constraints$
begin
  if not exists (select 1 from pg_catalog.pg_constraint where conrelid='public.airfnb_stripe_events'::pg_catalog.regclass and conname='airfnb_stripe_events_currency_eur') then
    alter table public.airfnb_stripe_events add constraint airfnb_stripe_events_currency_eur
      check (pg_catalog.btrim(currency::text) = 'EUR');
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint where conrelid='public.airfnb_stripe_events'::pg_catalog.regclass and conname='airfnb_stripe_events_type_check') then
    alter table public.airfnb_stripe_events add constraint airfnb_stripe_events_type_check
      check (event_type in ('checkout.session.completed','charge.refunded'));
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint where conrelid='public.airfnb_stripe_events'::pg_catalog.regclass and conname='airfnb_stripe_events_processed_check') then
    alter table public.airfnb_stripe_events add constraint airfnb_stripe_events_processed_check
      check ((processing_result is null and processed_at is null) or (processing_result is not null and processed_at is not null));
  end if;
end
$ledger_constraints$;

alter table public.airfnb_stripe_events enable row level security;
alter table public.airfnb_stripe_events force row level security;

revoke all on table public.airfnb_payments from public, anon, authenticated, service_role;
revoke all on table public.airfnb_lock_fees from public, anon, authenticated, service_role;
revoke all on table public.airfnb_stripe_events from public, anon, authenticated, service_role;
grant select on table public.airfnb_payments, public.airfnb_lock_fees,
  public.airfnb_stripe_events to service_role;

create or replace function public.airfnb_reconcile_stripe_event(
  p_event_id text,
  p_event_type text,
  p_event_created_at timestamptz,
  p_application_id uuid,
  p_lock_fee_id uuid,
  p_booking_id uuid,
  p_payment_intent text,
  p_amount_minor bigint,
  p_currency text,
  p_payment_status text,
  p_refunded_amount_minor bigint default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
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
$function$;

revoke all on function public.airfnb_reconcile_stripe_event(
  text,text,timestamptz,uuid,uuid,uuid,text,bigint,text,text,bigint
) from public, anon, authenticated, service_role;
grant execute on function public.airfnb_reconcile_stripe_event(
  text,text,timestamptz,uuid,uuid,uuid,text,bigint,text,text,bigint
) to service_role;

do $postconditions$
declare
  v_owner oid := (select relowner from pg_catalog.pg_class where oid='public.airfnb_payments'::pg_catalog.regclass);
  v_anon oid := (select oid from pg_catalog.pg_roles where rolname='anon');
  v_authenticated oid := (select oid from pg_catalog.pg_roles where rolname='authenticated');
  v_service_role oid := (select oid from pg_catalog.pg_roles where rolname='service_role');
  v_rpc regprocedure := 'public.airfnb_reconcile_stripe_event(text,text,timestamp with time zone,uuid,uuid,uuid,text,bigint,text,text,bigint)'::regprocedure;
begin
  if (select pg_catalog.count(*) from pg_catalog.pg_attribute where attrelid='public.airfnb_payments'::regclass and attnum>0 and not attisdropped) <> 15
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute where attrelid='public.airfnb_stripe_events'::regclass and attnum>0 and not attisdropped) <> 14
     or exists (select 1 from pg_catalog.pg_policy where polrelid='public.airfnb_stripe_events'::regclass)
     or not (select relrowsecurity and relforcerowsecurity from pg_catalog.pg_class where oid='public.airfnb_stripe_events'::regclass) then
    raise exception 'stripe reconciliation failed: schema or ledger RLS postcondition';
  end if;

  if exists (
    select 1
      from (values
        ('public.airfnb_payments'::regclass),
        ('public.airfnb_lock_fees'::regclass),
        ('public.airfnb_stripe_events'::regclass)
      ) as target(relation_oid)
     where not pg_catalog.has_table_privilege(v_service_role,target.relation_oid,'SELECT')
        or pg_catalog.has_table_privilege(v_service_role,target.relation_oid,'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
        or pg_catalog.has_table_privilege(v_anon,target.relation_oid,'SELECT,INSERT,UPDATE,DELETE')
        or pg_catalog.has_table_privilege(v_authenticated,target.relation_oid,'SELECT,INSERT,UPDATE,DELETE')
  ) then
    raise exception 'stripe reconciliation failed: financial table ACL postcondition';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc as procedure
     where procedure.oid=v_rpc and procedure.proowner=v_owner
       and procedure.prosecdef and procedure.provolatile='v'
       and procedure.prorettype='jsonb'::regtype
       and procedure.pronargdefaults=1
       and procedure.proconfig=array['search_path=""']::text[]
       and procedure.proargnames=array[
         'p_event_id','p_event_type','p_event_created_at','p_application_id',
         'p_lock_fee_id','p_booking_id','p_payment_intent','p_amount_minor',
         'p_currency','p_payment_status','p_refunded_amount_minor'
       ]::text[]
       and pg_catalog.has_function_privilege(v_service_role,procedure.oid,'EXECUTE')
       and not pg_catalog.has_function_privilege(v_anon,procedure.oid,'EXECUTE')
       and not pg_catalog.has_function_privilege(v_authenticated,procedure.oid,'EXECUTE')
       and not exists (
         select 1 from pg_catalog.aclexplode(procedure.proacl) as privilege
          where privilege.grantee not in (v_owner,v_service_role)
             or privilege.privilege_type <> 'EXECUTE'
             or privilege.is_grantable
       )
  ) then
    raise exception 'stripe reconciliation failed: RPC catalog or ACL postcondition';
  end if;

  if exists (
    select 1 from airfnb_stripe_protected_functions_20260820 as original
    left join pg_catalog.pg_proc as procedure on procedure.oid=original.oid
   where procedure.oid is null
      or procedure.proowner<>original.proowner
      or procedure.proacl is distinct from original.proacl
      or procedure.prosecdef<>original.prosecdef
      or procedure.provolatile<>original.provolatile
      or procedure.proconfig is distinct from original.proconfig
      or pg_catalog.md5(procedure.prosrc)<>original.body_hash
  ) or exists (
    select 1 from airfnb_stripe_protected_relations_20260820 as original
    left join pg_catalog.pg_class as relation on relation.oid=original.oid
   where relation.oid is null
      or relation.relowner<>original.relowner
      or relation.relacl is distinct from original.relacl
      or relation.relrowsecurity<>original.relrowsecurity
      or relation.relforcerowsecurity<>original.relforcerowsecurity
  ) then
    raise exception 'stripe reconciliation failed: protected Marketplace object changed';
  end if;
end
$postconditions$;

commit;
