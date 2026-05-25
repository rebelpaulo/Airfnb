-- airfnb_29: admin dashboard support — metrics view + truck moderation RPCs.
--
-- The view is SECURITY DEFINER via a wrapping function (Postgres views run as
-- the invoker), so admin pages can read aggregate counts even if RLS would
-- otherwise restrict individual rows. The two RPCs (approve/reject) gate on
-- airfnb_is_admin() so non-admin authenticated users can't flip statuses.

create or replace function public.airfnb_admin_metrics()
returns table (
  trucks_total         int,
  trucks_active        int,
  trucks_pending       int,
  organizers_total     int,
  requests_open        int,
  bookings_confirmed   int,
  lockfees_paid_count  int,
  lockfees_paid_total  numeric,
  revenue_platform     numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select
    (select count(*)::int from public.airfnb_trucks),
    (select count(*)::int from public.airfnb_trucks where status = 'active'),
    (select count(*)::int from public.airfnb_trucks where status = 'pending_review'),
    (select count(*)::int from public.airfnb_profiles where role in ('organizer','owner','admin','staff')),
    (select count(*)::int from public.airfnb_event_requests where status in ('open','reviewing')),
    (select count(*)::int from public.airfnb_bookings where status in ('confirmed','completed')),
    (select count(*)::int from public.airfnb_lock_fees where status = 'paid'),
    (select coalesce(sum(amount),       0) from public.airfnb_lock_fees where status = 'paid'),
    (select coalesce(sum(platform_fee), 0) from public.airfnb_lock_fees where status = 'paid')
  where public.airfnb_is_admin();
$$;
revoke execute on function public.airfnb_admin_metrics() from public, anon;
grant  execute on function public.airfnb_admin_metrics() to authenticated;

-- Pending-review trucks for the moderation queue. Includes owner name and
-- first cover image url so the admin can decide without an extra round-trip.
create or replace function public.airfnb_admin_pending_trucks(p_limit int default 50)
returns table (
  id           uuid,
  slug         text,
  name         text,
  base_city    text,
  owner_id     uuid,
  owner_name   text,
  cover_url    text,
  description  text,
  created_at   timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select t.id, t.slug, t.name, t.base_city, t.owner_id, p.display_name,
         (select url from public.airfnb_truck_images i where i.truck_id = t.id and i.is_cover order by sort_order limit 1),
         t.description,
         t.created_at
    from public.airfnb_trucks t
    left join public.airfnb_profiles p on p.id = t.owner_id
   where t.status = 'pending_review' and public.airfnb_is_admin()
   order by t.created_at desc
   limit greatest(1, p_limit);
$$;
revoke execute on function public.airfnb_admin_pending_trucks(int) from public, anon;
grant  execute on function public.airfnb_admin_pending_trucks(int) to authenticated;

-- Status flips: approve (→ active) or reject (→ archived with reason note).
create or replace function public.airfnb_admin_approve_truck(p_truck uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.airfnb_is_admin() then
    raise exception 'not authorized';
  end if;
  update public.airfnb_trucks
     set status = 'active', updated_at = now()
   where id = p_truck and status = 'pending_review';
end $$;
revoke execute on function public.airfnb_admin_approve_truck(uuid) from public, anon;
grant  execute on function public.airfnb_admin_approve_truck(uuid) to authenticated;

create or replace function public.airfnb_admin_reject_truck(p_truck uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.airfnb_is_admin() then
    raise exception 'not authorized';
  end if;
  update public.airfnb_trucks
     set status = 'archived', updated_at = now()
   where id = p_truck and status = 'pending_review';

  -- Notify the owner with the reason
  insert into public.airfnb_notifications (user_id, kind, payload)
    select owner_id, 'truck.rejected',
           jsonb_build_object('truck_id', p_truck, 'reason', p_reason)
      from public.airfnb_trucks where id = p_truck;
end $$;
revoke execute on function public.airfnb_admin_reject_truck(uuid, text) from public, anon;
grant  execute on function public.airfnb_admin_reject_truck(uuid, text) to authenticated;
