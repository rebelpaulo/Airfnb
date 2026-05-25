-- Truck owners pick which event kinds their truck caters for; landing-page
-- themed cards (Casamentos / Festivais / etc.) then deep-link into
-- `/catalogo?event_kind=<kind>` and the catalog filters to trucks that
-- declared that kind in their `compatible_event_kinds` array.
--
-- Backfill: existing trucks get an empty array; they won't match the new
-- filter until owners opt-in via the wizard. Plain catalog browsing is
-- unaffected.

alter table public.airfnb_trucks
  add column if not exists compatible_event_kinds public.airfnb_event_kind[] not null default '{}';

-- GIN index supports the `compatible_event_kinds @> ARRAY[<kind>]` (or the
-- equivalent supabase-js `.contains` / `.overlaps`) filter.
create index if not exists airfnb_trucks_event_kinds_gin_idx
  on public.airfnb_trucks using gin (compatible_event_kinds);

-- Extend the truck-card view so the catalog page can apply the filter
-- server-side and the chip on each card can show the matched kind.
drop view if exists public.airfnb_v_truck_card cascade;
create view public.airfnb_v_truck_card with (security_invoker = true) as
select
  t.id, t.slug, t.name, t.tagline, t.base_city, t.capacity,
  t.base_price, t.price_per_pax, t.min_event_pax, t.max_event_pax,
  t.service_radius_km,
  t.cuisine_types, t.dietary_options, t.catering_type, t.serves,
  t.setup_minutes, t.teardown_minutes,
  t.power_required_kw, t.sanitation_required,
  t.compatible_event_kinds,
  t.rating_avg, t.rating_count, t.featured, t.status,
  (select url from public.airfnb_truck_images i
     where i.truck_id = t.id and i.is_cover
     order by sort_order limit 1) as cover_url,
  array(
    select c.slug from public.airfnb_truck_categories tc
    join public.airfnb_categories c on c.id = tc.category_id
    where tc.truck_id = t.id
  ) as category_slugs
from public.airfnb_trucks t
where t.status = 'active';
