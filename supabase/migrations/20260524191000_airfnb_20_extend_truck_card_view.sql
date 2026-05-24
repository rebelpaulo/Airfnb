-- airfnb_20: extend the public catalog view with all filterable columns the
-- /catalogo filter modal needs (cuisine, dietary, price-per-pax, setup time,
-- power, sanitation).
--
-- `create or replace view` cannot reshape the column order/insert new columns
-- in the middle of an existing definition, so we drop+create. `cascade` is
-- only used to follow any downstream views/grants in dev; no tables depend on
-- this view.
--
-- The view stays `security_invoker = true` so it inherits the underlying RLS.

drop view if exists public.airfnb_v_truck_card cascade;
create view public.airfnb_v_truck_card with (security_invoker = true) as
select
  t.id, t.slug, t.name, t.tagline, t.base_city, t.capacity,
  t.base_price, t.price_per_pax, t.min_event_pax, t.max_event_pax,
  t.service_radius_km,
  t.cuisine_types, t.dietary_options,
  t.setup_minutes, t.teardown_minutes,
  t.power_required_kw, t.sanitation_required,
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
