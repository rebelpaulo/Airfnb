-- airfnb_11_fix_function_security
-- applied at 20260524134351


-- match_score doesn't need elevated privileges; switch to SECURITY INVOKER
create or replace function public.airfnb_match_score(p_truck uuid, p_request uuid)
returns numeric language plpgsql stable security invoker set search_path = public as $$
declare
  score numeric := 0;
  t     record;
  r     record;
  cat_hit boolean;
begin
  select * into t from public.airfnb_trucks         where id = p_truck   and status = 'active';
  select * into r from public.airfnb_event_requests where id = p_request and status in ('open','reviewing');
  if t is null or r is null then return 0; end if;

  if coalesce(array_length(r.desired_categories, 1), 0) > 0 then
    select exists (
      select 1 from public.airfnb_truck_categories tc
      where tc.truck_id = t.id and tc.category_id = any(r.desired_categories)
    ) into cat_hit;
    if cat_hit then score := score + 30; end if;
  else
    score := score + 15;
  end if;

  if t.base_city is not null and r.city is not null and lower(t.base_city) = lower(r.city) then
    score := score + 20;
  end if;
  if t.capacity is not null and r.expected_pax is not null and t.capacity >= r.expected_pax then
    score := score + 15;
  end if;
  if t.rating_avg >= 4.5 then score := score + 10;
  elsif t.rating_avg >= 4.0 then score := score + 5;
  end if;
  if not exists (
    select 1 from public.airfnb_truck_availability av
    where av.truck_id = t.id and av.date = r.start_at::date and av.status in ('blocked','booked')
  ) then score := score + 10; end if;
  if t.featured then score := score + 5; end if;
  if t.base_price is not null and r.budget_max is not null and t.base_price <= r.budget_max then
    score := score + 10;
  end if;
  return least(score, 100);
end $$;

-- Lock cron-only functions: revoke from anon + authenticated (only service_role + cron will call)
revoke execute on function public.airfnb_expire_stale_lock_fees() from public, anon, authenticated;
revoke execute on function public.airfnb_expire_stale_requests()  from public, anon, authenticated;
grant  execute on function public.airfnb_expire_stale_lock_fees() to service_role;
grant  execute on function public.airfnb_expire_stale_requests()  to service_role;

-- Fix mutable search_path on truck_is_available
alter function public.airfnb_truck_is_available(uuid, date, date) set search_path = public;
;
