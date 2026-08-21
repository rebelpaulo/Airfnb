-- One atomic database boundary for Stripe lock-fee payments and refunds.
--
-- Stripe webhooks are at-least-once and can arrive out of order. Event IDs
-- deduplicate deliveries, while the non-partial provider-reference and
-- lock-fee constraints prevent distinct events from duplicating or rebinding a
-- financial record. Rejected calls raise and therefore roll back the event-log
-- insert together with every other write in this transaction.

begin;

-- ---------------------------------------------------------------------------
-- Make the payment row carry the complete marketplace linkage. Partial refunds
-- remain status=paid with refunded_amount populated; only a full refund moves
-- the payment, lock fee and booking to their terminal refunded states.
-- ---------------------------------------------------------------------------

alter table public.airfnb_payments
  add column application_id uuid
    references public.airfnb_applications(id),
  add column lock_fee_id uuid
    references public.airfnb_lock_fees(id),
  add column refunded_amount numeric(10,2) not null default 0,
  add column last_provider_event_at timestamptz;

alter table public.airfnb_payments
  add constraint airfnb_payments_refunded_amount_bounds
    check (
      refunded_amount >= 0
      and (amount is null or refunded_amount <= amount)
    ),
  add constraint airfnb_payments_lock_fee_key unique (lock_fee_id);

-- Replace partial unique indexes. PostgreSQL unique constraints still permit
-- multiple NULL values, but can now be inferred deterministically by
-- ON CONFLICT (provider_ref).
drop index if exists public.airfnb_payments_provider_ref_unique;
drop index if exists public.airfnb_lock_fees_provider_ref_uniq;

alter table public.airfnb_payments
  add constraint airfnb_payments_provider_ref_key unique (provider_ref);

alter table public.airfnb_lock_fees
  add constraint airfnb_lock_fees_provider_ref_key unique (provider_ref);

-- Financial state is never directly client-writable. The service role invokes
-- the SECURITY DEFINER reconciliation function below.
drop policy if exists airfnb_payments_write on public.airfnb_payments;
revoke insert, update, delete on table public.airfnb_payments
  from anon, authenticated;
revoke insert, update, delete on table public.airfnb_lock_fees
  from anon, authenticated;
grant select, insert, update, delete on table public.airfnb_payments
  to service_role;
grant select, insert, update, delete on table public.airfnb_lock_fees
  to service_role;

-- ---------------------------------------------------------------------------
-- Durable, service-role-only Stripe event ledger.
-- ---------------------------------------------------------------------------

create table public.airfnb_stripe_events (
  event_id                 text primary key,
  event_type               text not null,
  event_created_at         timestamptz not null,
  provider_ref             text not null,
  application_id           uuid not null
    references public.airfnb_applications(id),
  lock_fee_id              uuid not null
    references public.airfnb_lock_fees(id),
  booking_id               uuid not null
    references public.airfnb_bookings(id),
  amount_minor             bigint not null check (amount_minor > 0),
  currency                 char(3) not null,
  payment_status           text not null,
  refunded_amount_minor    bigint not null default 0
    check (
      refunded_amount_minor >= 0
      and refunded_amount_minor <= amount_minor
    ),
  processing_result        text,
  processed_at             timestamptz,
  received_at              timestamptz not null default now()
);

create index airfnb_stripe_events_provider_time_idx
  on public.airfnb_stripe_events(provider_ref, event_created_at desc);

alter table public.airfnb_stripe_events enable row level security;
alter table public.airfnb_stripe_events force row level security;

revoke all on table public.airfnb_stripe_events
  from public, anon, authenticated, service_role;
grant select on table public.airfnb_stripe_events to service_role;

-- ---------------------------------------------------------------------------
-- Atomic reconciliation RPC.
--
-- Monetary inputs use Stripe's integer minor units. For charge.refunded,
-- p_refunded_amount_minor is Stripe's cumulative amount_refunded value.
-- ---------------------------------------------------------------------------

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
set search_path = pg_catalog, public
as $function$
declare
  v_event_type text := lower(btrim(p_event_type));
  v_event_id text := btrim(p_event_id);
  v_provider_ref text := btrim(p_payment_intent);
  v_currency char(3);
  v_payment_status text := lower(btrim(p_payment_status));
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
  -- Basic webhook-shape validation happens before any durable write.
  if v_event_id is null or v_event_id = '' then
    raise exception 'stripe event id is required';
  end if;
  if v_event_type is null
     or v_event_type not in ('checkout.session.completed', 'charge.refunded') then
    raise exception 'unsupported stripe event type: %', p_event_type;
  end if;
  if p_event_created_at is null
     or p_event_created_at > now() + interval '5 minutes' then
    raise exception 'invalid stripe event time';
  end if;
  if p_application_id is null or p_lock_fee_id is null or p_booking_id is null then
    raise exception 'application, lock fee and booking ids are required';
  end if;
  if v_provider_ref is null or v_provider_ref = '' then
    raise exception 'stripe payment intent is required';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'stripe amount must be positive';
  end if;
  if p_refunded_amount_minor is null
     or p_refunded_amount_minor < 0
     or p_refunded_amount_minor > p_amount_minor then
    raise exception 'invalid cumulative refunded amount';
  end if;
  if p_currency is null or btrim(p_currency) !~ '^[A-Za-z]{3}$' then
    raise exception 'invalid stripe currency';
  end if;
  if v_payment_status is null or v_payment_status = '' then
    raise exception 'stripe payment status is required';
  end if;

  v_currency := upper(btrim(p_currency))::char(3);
  v_amount := (p_amount_minor::numeric / 100)::numeric(10,2);
  v_refunded_amount :=
    (p_refunded_amount_minor::numeric / 100)::numeric(10,2);

  if v_event_type = 'checkout.session.completed' then
    if v_payment_status <> 'paid' then
      raise exception 'checkout session is not paid (status=%)', p_payment_status;
    end if;
    if p_refunded_amount_minor <> 0 then
      raise exception 'payment event cannot carry a refunded amount';
    end if;
  elsif v_payment_status not in ('paid', 'succeeded') then
    raise exception 'refunded charge is not succeeded (status=%)', p_payment_status;
  elsif p_refunded_amount_minor = 0 then
    raise exception 'refund event must carry a refunded amount';
  end if;

  -- The primary key deduplicates identical webhook delivery attempts. A reused
  -- event ID with different financial data is rejected rather than acknowledged.
  insert into public.airfnb_stripe_events (
    event_id,
    event_type,
    event_created_at,
    provider_ref,
    application_id,
    lock_fee_id,
    booking_id,
    amount_minor,
    currency,
    payment_status,
    refunded_amount_minor
  ) values (
    v_event_id,
    v_event_type,
    p_event_created_at,
    v_provider_ref,
    p_application_id,
    p_lock_fee_id,
    p_booking_id,
    p_amount_minor,
    v_currency,
    v_payment_status,
    p_refunded_amount_minor
  )
  on conflict (event_id) do nothing
  returning true into v_event_inserted;

  if not coalesce(v_event_inserted, false) then
    select *
      into v_existing_event
      from public.airfnb_stripe_events
     where event_id = v_event_id
     for update;

    if v_existing_event.event_type is distinct from v_event_type
       or v_existing_event.event_created_at is distinct from p_event_created_at
       or v_existing_event.provider_ref is distinct from v_provider_ref
       or v_existing_event.application_id is distinct from p_application_id
       or v_existing_event.lock_fee_id is distinct from p_lock_fee_id
       or v_existing_event.booking_id is distinct from p_booking_id
       or v_existing_event.amount_minor is distinct from p_amount_minor
       or v_existing_event.currency is distinct from v_currency
       or v_existing_event.payment_status is distinct from v_payment_status
       or v_existing_event.refunded_amount_minor
          is distinct from p_refunded_amount_minor then
      raise exception 'stripe event id was replayed with different data';
    end if;

    return jsonb_build_object(
      'ok', true,
      'duplicate_event', true,
      'result', v_existing_event.processing_result,
      'event_id', v_event_id
    );
  end if;

  -- Lock every marketplace object before testing or changing state. These
  -- exact IDs must describe one accepted application and its one lock fee and
  -- booking; no caller-supplied ID can be rebound to another object.
  -- Match the stale-lock-fee sweeper's lock order (lock fee, application,
  -- booking) so concurrent expiry and webhook work cannot deadlock each other.
  select *
    into v_lock_fee
    from public.airfnb_lock_fees
   where id = p_lock_fee_id
   for update;
  if not found then
    raise exception 'lock fee not found';
  end if;

  select *
    into v_application
    from public.airfnb_applications
   where id = p_application_id
   for update;
  if not found then
    raise exception 'application not found';
  end if;

  select *
    into v_booking
    from public.airfnb_bookings
   where id = p_booking_id
   for update;
  if not found then
    raise exception 'booking not found';
  end if;

  if v_application.status <> 'accepted'::public.airfnb_application_status then
    raise exception 'application is not accepted (status=%)', v_application.status;
  end if;
  if v_lock_fee.application_id <> v_application.id
     or v_booking.application_id is distinct from v_application.id then
    raise exception 'application, lock fee and booking linkage mismatch';
  end if;
  if v_lock_fee.created_at is null
     or v_booking.created_at is null
     or p_event_created_at < v_lock_fee.created_at
     or p_event_created_at < v_booking.created_at then
    raise exception 'stripe event predates the lock fee or booking';
  end if;
  if v_lock_fee.amount is distinct from v_amount
     or upper(btrim(v_lock_fee.currency::text)) <> v_currency::text
     or v_booking.currency is null
     or upper(btrim(v_booking.currency::text)) <> v_currency::text then
    raise exception 'stripe amount or currency mismatch';
  end if;

  select *
    into v_payment
    from public.airfnb_payments
   where provider_ref = v_provider_ref
   for update;
  v_payment_found := found;

  if v_payment_found then
    if v_payment.application_id is distinct from v_application.id
       or v_payment.lock_fee_id is distinct from v_lock_fee.id
       or v_payment.booking_id is distinct from v_booking.id
       or v_payment.amount is distinct from v_amount
       or upper(btrim(v_payment.currency::text)) <> v_currency::text
       or v_payment.method <> 'stripe'::public.airfnb_payment_method
       or v_payment.direction
          <> 'truck_to_platform'::public.airfnb_payment_direction
       or v_payment.kind <> 'lock_fee'::public.airfnb_payment_kind then
      raise exception 'payment intent is already bound to different data';
    end if;
  end if;

  if v_lock_fee.provider_ref is not null
     and v_lock_fee.provider_ref <> v_provider_ref then
    raise exception 'lock fee is already bound to another payment intent';
  end if;

  if v_event_type = 'checkout.session.completed' then
    -- Stripe's event timestamp, not webhook receipt time, determines whether
    -- the payment was made inside the lock-fee acceptance window.
    if p_event_created_at > v_lock_fee.due_until then
      raise exception 'lock fee payment arrived after its due time';
    end if;

    if v_payment_found then
      if v_payment.status not in (
           'paid'::public.airfnb_payment_status,
           'refunded'::public.airfnb_payment_status
         )
         or v_lock_fee.status not in (
           'paid'::public.airfnb_lock_fee_status,
           'refunded'::public.airfnb_lock_fee_status
         )
         or v_booking.status not in (
           'confirmed'::public.airfnb_booking_status,
           'refunded'::public.airfnb_booking_status
         ) then
        raise exception 'existing payment has inconsistent marketplace state';
      end if;

      v_result := 'payment_replay';
    else
      if v_lock_fee.status <> 'pending'::public.airfnb_lock_fee_status then
        raise exception 'lock fee is not pending (status=%)', v_lock_fee.status;
      end if;
      if v_booking.status <> 'pending_lock_fee'::public.airfnb_booking_status then
        raise exception 'booking is not pending lock fee (status=%)', v_booking.status;
      end if;
      if v_lock_fee.provider_ref is not null then
        raise exception 'lock fee has a provider reference without a payment';
      end if;

      -- A different provider reference for this lock fee cannot slip through;
      -- the lock_fee_id unique constraint is an additional concurrency guard.
      if exists (
        select 1
          from public.airfnb_payments p
         where p.lock_fee_id = v_lock_fee.id
      ) then
        raise exception 'lock fee already has a payment record';
      end if;

      update public.airfnb_lock_fees
         set status = 'paid'::public.airfnb_lock_fee_status,
             paid_at = p_event_created_at,
             provider_ref = v_provider_ref,
             provider_event_log = provider_event_log || jsonb_build_array(
               jsonb_build_object(
                 'id', v_event_id,
                 'type', v_event_type,
                 'created_at', p_event_created_at
               )
             )
       where id = v_lock_fee.id;

      insert into public.airfnb_payments (
        booking_id,
        application_id,
        lock_fee_id,
        amount,
        currency,
        method,
        status,
        direction,
        kind,
        provider_ref,
        paid_at,
        refunded_amount,
        last_provider_event_at
      ) values (
        v_booking.id,
        v_application.id,
        v_lock_fee.id,
        v_amount,
        v_currency,
        'stripe'::public.airfnb_payment_method,
        'paid'::public.airfnb_payment_status,
        'truck_to_platform'::public.airfnb_payment_direction,
        'lock_fee'::public.airfnb_payment_kind,
        v_provider_ref,
        p_event_created_at,
        0,
        p_event_created_at
      );

      update public.airfnb_bookings
         set status = 'confirmed'::public.airfnb_booking_status
       where id = v_booking.id;

      v_result := 'payment_confirmed';
    end if;
  else
    -- Refund events resolve strictly through the already-reconciled payment.
    -- A refund delivered before its payment is rejected transactionally; a
    -- Stripe retry can succeed after the payment event has been processed.
    if not v_payment_found then
      raise exception 'refund arrived before its payment was reconciled';
    end if;
    if v_payment.status not in (
         'paid'::public.airfnb_payment_status,
         'refunded'::public.airfnb_payment_status
       ) then
      raise exception 'payment cannot be refunded (status=%)', v_payment.status;
    end if;
    if v_payment.paid_at is null or p_event_created_at < v_payment.paid_at then
      raise exception 'refund event predates payment';
    end if;
    if v_lock_fee.status not in (
         'paid'::public.airfnb_lock_fee_status,
         'refunded'::public.airfnb_lock_fee_status
       ) then
      raise exception 'lock fee cannot be refunded (status=%)', v_lock_fee.status;
    end if;
    if v_booking.status not in (
         'confirmed'::public.airfnb_booking_status,
         'refunded'::public.airfnb_booking_status
       ) then
      raise exception 'booking cannot be refunded (status=%)', v_booking.status;
    end if;

    if v_refunded_amount < v_payment.refunded_amount then
      -- Stripe refund amounts are cumulative. An older partial-refund event
      -- delivered late is recorded but can never regress the financial state.
      v_result := 'stale_refund_ignored';
    elsif v_refunded_amount = v_payment.refunded_amount then
      v_result := 'refund_replay';
    elsif v_refunded_amount < v_amount then
      if v_payment.status = 'refunded'::public.airfnb_payment_status
         or v_lock_fee.status = 'refunded'::public.airfnb_lock_fee_status
         or v_booking.status = 'refunded'::public.airfnb_booking_status then
        raise exception 'partial refund conflicts with full-refund state';
      end if;

      update public.airfnb_payments
         set refunded_amount = v_refunded_amount,
             last_provider_event_at = greatest(
               coalesce(last_provider_event_at, p_event_created_at),
               p_event_created_at
             )
       where id = v_payment.id;

      update public.airfnb_lock_fees
         set provider_event_log = provider_event_log || jsonb_build_array(
               jsonb_build_object(
                 'id', v_event_id,
                 'type', v_event_type,
                 'created_at', p_event_created_at,
                 'refunded_amount', v_refunded_amount
               )
             )
       where id = v_lock_fee.id;

      v_result := 'partial_refund_recorded';
    else
      update public.airfnb_payments
         set status = 'refunded'::public.airfnb_payment_status,
             refunded_amount = v_amount,
             last_provider_event_at = greatest(
               coalesce(last_provider_event_at, p_event_created_at),
               p_event_created_at
             )
       where id = v_payment.id;

      update public.airfnb_lock_fees
         set status = 'refunded'::public.airfnb_lock_fee_status,
             refunded_at = coalesce(refunded_at, p_event_created_at),
             provider_event_log = provider_event_log || jsonb_build_array(
               jsonb_build_object(
                 'id', v_event_id,
                 'type', v_event_type,
                 'created_at', p_event_created_at,
                 'refunded_amount', v_amount
               )
             )
       where id = v_lock_fee.id;

      update public.airfnb_bookings
         set status = 'refunded'::public.airfnb_booking_status
       where id = v_booking.id;

      v_result := 'full_refund_reconciled';
    end if;
  end if;

  update public.airfnb_stripe_events
     set processing_result = v_result,
         processed_at = now()
   where event_id = v_event_id;

  return jsonb_build_object(
    'ok', true,
    'duplicate_event', false,
    'result', v_result,
    'event_id', v_event_id,
    'application_id', v_application.id,
    'lock_fee_id', v_lock_fee.id,
    'booking_id', v_booking.id,
    'payment_intent', v_provider_ref,
    'refunded_amount', v_refunded_amount
  );
end
$function$;

revoke execute on function public.airfnb_reconcile_stripe_event(
  text, text, timestamptz, uuid, uuid, uuid, text, bigint, text, text, bigint
) from public, anon, authenticated, service_role;
grant execute on function public.airfnb_reconcile_stripe_event(
  text, text, timestamptz, uuid, uuid, uuid, text, bigint, text, text, bigint
) to service_role;

commit;
