-- airfnb_10_helpers_match_accept_cron
-- applied at 20260524134236


-- =========================================================================
-- 1. Lock-fee calculator
--    10% of proposed price, floor €25, cap €500. Easy to tweak later.
-- =========================================================================
create or replace function public.airfnb_calculate_lock_fee(p_application uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select greatest(25, least(500, round(a.proposed_price * 0.10, 2)))
    from public.airfnb_applications a where a.id = p_application;
$$;
revoke execute on function public.airfnb_calculate_lock_fee(uuid) from public, anon, authenticated;
grant  execute on function public.airfnb_calculate_lock_fee(uuid) to service_role;

-- =========================================================================
-- 2. Match score (0..100) between a truck and a request
-- =========================================================================
create or replace function public.airfnb_match_score(p_truck uuid, p_request uuid)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare
  score numeric := 0;
  t     record;
  r     record;
  cat_hit boolean;
begin
  select * into t from public.airfnb_trucks         where id = p_truck   and status = 'active';
  select * into r from public.airfnb_event_requests where id = p_request and status in ('open','reviewing');
  if t is null or r is null then return 0; end if;

  -- category match
  if coalesce(array_length(r.desired_categories, 1), 0) > 0 then
    select exists (
      select 1 from public.airfnb_truck_categories tc
      where tc.truck_id = t.id and tc.category_id = any(r.desired_categories)
    ) into cat_hit;
    if cat_hit then score := score + 30; end if;
  else
    score := score + 15;  -- no preference => neutral bonus
  end if;

  -- same city
  if t.base_city is not null and r.city is not null and lower(t.base_city) = lower(r.city) then
    score := score + 20;
  end if;

  -- capacity
  if t.capacity is not null and r.expected_pax is not null and t.capacity >= r.expected_pax then
    score := score + 15;
  end if;

  -- rating
  if t.rating_avg >= 4.5 then score := score + 10;
  elsif t.rating_avg >= 4.0 then score := score + 5;
  end if;

  -- availability on the day
  if not exists (
    select 1 from public.airfnb_truck_availability av
    where av.truck_id = t.id
      and av.date = r.start_at::date
      and av.status in ('blocked','booked')
  ) then score := score + 10; end if;

  -- featured
  if t.featured then score := score + 5; end if;

  -- budget alignment
  if t.base_price is not null and r.budget_max is not null
     and t.base_price <= r.budget_max then
    score := score + 10;
  end if;

  return least(score, 100);
end $$;

-- =========================================================================
-- 3. Feed for trucks — matching open requests
-- =========================================================================
create or replace function public.airfnb_find_matching_requests(p_truck uuid, p_limit int default 20)
returns table (
  request_id uuid,
  title text,
  city text,
  start_at timestamptz,
  expected_pax int,
  budget_min numeric,
  budget_max numeric,
  match_score numeric
)
language sql stable security invoker set search_path = public as $$
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

-- =========================================================================
-- 4. Suggestions for organizers — matching trucks for a request
-- =========================================================================
create or replace function public.airfnb_find_matching_trucks(p_request uuid, p_limit int default 12)
returns table (
  truck_id uuid,
  name text,
  base_city text,
  rating_avg numeric,
  match_score numeric
)
language sql stable security invoker set search_path = public as $$
  select t.id, t.name, t.base_city, t.rating_avg,
         public.airfnb_match_score(t.id, p_request) as match_score
    from public.airfnb_trucks t
   where t.status = 'active'
   order by match_score desc, t.rating_avg desc
   limit greatest(1, p_limit);
$$;

-- =========================================================================
-- 5. Accept application — atomic transaction
--    Run by request organizer or admin. Creates booking, lock_fee, conversation.
-- =========================================================================
create or replace function public.airfnb_accept_application(p_application uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  app          public.airfnb_applications%rowtype;
  req          public.airfnb_event_requests%rowtype;
  v_booking    uuid;
  v_lockfee_id uuid;
  v_conv_id    uuid;
  v_fee_amount numeric;
  v_awarded    int;
begin
  -- load + lock
  select * into app from public.airfnb_applications where id = p_application for update;
  if app is null then raise exception 'application not found'; end if;
  if app.status not in ('submitted','shortlisted') then
    raise exception 'application cannot be accepted (status=%)', app.status;
  end if;

  select * into req from public.airfnb_event_requests where id = app.request_id for update;
  if req is null then raise exception 'request not found'; end if;

  -- authz: only organizer or admin
  if auth.uid() is null or (auth.uid() <> req.organizer_id and not public.airfnb_is_admin()) then
    raise exception 'not authorized';
  end if;

  if req.status not in ('open','reviewing') then
    raise exception 'request is not accepting applications (status=%)', req.status;
  end if;

  -- compute fee
  v_fee_amount := public.airfnb_calculate_lock_fee(p_application);

  -- update application
  update public.airfnb_applications
     set status = 'accepted', decided_at = now()
   where id = p_application;

  -- create booking (status pending_lock_fee)
  insert into public.airfnb_bookings (
    event_id, organizer_id, status, starts_at, ends_at,
    pax_count, total_amount, currency, notes, application_id
  ) values (
    null, req.organizer_id, 'pending_lock_fee', req.start_at, req.end_at,
    req.expected_pax, app.proposed_price, 'EUR', req.notes, app.id
  ) returning id into v_booking;

  insert into public.airfnb_booking_trucks (booking_id, truck_id, agreed_price)
  values (v_booking, app.truck_id, app.proposed_price);

  -- create lock fee
  insert into public.airfnb_lock_fees (application_id, amount, due_until, status)
  values (app.id, v_fee_amount, now() + interval '48 hours', 'pending')
  returning id into v_lockfee_id;

  -- create conversation linked to application + booking
  insert into public.airfnb_conversations (booking_id, application_id)
  values (v_booking, app.id) returning id into v_conv_id;

  insert into public.airfnb_conversation_participants (conversation_id, user_id)
  values (v_conv_id, req.organizer_id);

  insert into public.airfnb_conversation_participants (conversation_id, user_id)
  select v_conv_id, t.owner_id from public.airfnb_trucks t where t.id = app.truck_id;

  -- notifications
  insert into public.airfnb_notifications (user_id, kind, payload)
    select t.owner_id, 'application.accepted',
           jsonb_build_object(
             'application_id', app.id, 'request_id', req.id,
             'lock_fee_id', v_lockfee_id, 'amount', v_fee_amount,
             'due_until', (now() + interval '48 hours')
           )
      from public.airfnb_trucks t where t.id = app.truck_id;

  -- if all slots filled, mark request as awarded
  select count(*) into v_awarded
    from public.airfnb_applications a2
    where a2.request_id = req.id and a2.status = 'accepted';
  if v_awarded >= req.slots_needed then
    update public.airfnb_event_requests
       set status = 'awarded', awarded_at = coalesce(awarded_at, now())
     where id = req.id;
  end if;

  return jsonb_build_object(
    'booking_id',   v_booking,
    'lock_fee_id',  v_lockfee_id,
    'amount',       v_fee_amount,
    'due_until',    (now() + interval '48 hours'),
    'conversation_id', v_conv_id
  );
end $$;

-- only authenticated users can call (the function itself enforces organizer/admin)
revoke execute on function public.airfnb_accept_application(uuid) from public, anon;
grant  execute on function public.airfnb_accept_application(uuid) to authenticated;

-- =========================================================================
-- 6. Shortlist / reject helpers (lightweight RPC wrappers)
-- =========================================================================
create or replace function public.airfnb_shortlist_application(p_application uuid)
returns void language plpgsql security definer set search_path = public as $$
declare app public.airfnb_applications%rowtype;
        req public.airfnb_event_requests%rowtype;
begin
  select * into app from public.airfnb_applications where id = p_application;
  if app is null then raise exception 'application not found'; end if;
  select * into req from public.airfnb_event_requests where id = app.request_id;
  if auth.uid() is null or (auth.uid() <> req.organizer_id and not public.airfnb_is_admin()) then
    raise exception 'not authorized'; end if;
  update public.airfnb_applications
     set status = 'shortlisted', shortlisted_at = now()
   where id = p_application and status = 'submitted';
end $$;
revoke execute on function public.airfnb_shortlist_application(uuid) from public, anon;
grant  execute on function public.airfnb_shortlist_application(uuid) to authenticated;

create or replace function public.airfnb_reject_application(p_application uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare app public.airfnb_applications%rowtype;
        req public.airfnb_event_requests%rowtype;
begin
  select * into app from public.airfnb_applications where id = p_application;
  if app is null then raise exception 'application not found'; end if;
  select * into req from public.airfnb_event_requests where id = app.request_id;
  if auth.uid() is null or (auth.uid() <> req.organizer_id and not public.airfnb_is_admin()) then
    raise exception 'not authorized'; end if;
  update public.airfnb_applications
     set status = 'rejected', decided_at = now()
   where id = p_application and status in ('submitted','shortlisted');
  insert into public.airfnb_notifications (user_id, kind, payload)
    select t.owner_id, 'application.rejected', jsonb_build_object('application_id', p_application, 'reason', p_reason)
      from public.airfnb_trucks t where t.id = app.truck_id;
end $$;
revoke execute on function public.airfnb_reject_application(uuid, text) from public, anon;
grant  execute on function public.airfnb_reject_application(uuid, text) to authenticated;

-- =========================================================================
-- 7. Expire stale lock fees and requests (called by pg_cron)
-- =========================================================================
create or replace function public.airfnb_expire_stale_lock_fees()
returns int language plpgsql security definer set search_path = public as $$
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

create or replace function public.airfnb_expire_stale_requests()
returns int language plpgsql security definer set search_path = public as $$
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

-- =========================================================================
-- 8. Schedule cron jobs (pg_cron)
-- =========================================================================
create extension if not exists pg_cron;

-- expire lock fees every 10 minutes
select cron.schedule(
  'airfnb_expire_lockfees',
  '*/10 * * * *',
  $$select public.airfnb_expire_stale_lock_fees();$$
) where not exists (select 1 from cron.job where jobname = 'airfnb_expire_lockfees');

-- expire stale requests hourly
select cron.schedule(
  'airfnb_expire_requests',
  '0 * * * *',
  $$select public.airfnb_expire_stale_requests();$$
) where not exists (select 1 from cron.job where jobname = 'airfnb_expire_requests');
;
