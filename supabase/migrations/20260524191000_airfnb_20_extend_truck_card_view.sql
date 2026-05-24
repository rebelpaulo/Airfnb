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

-- DEFENSIVE: cuisine_types / dietary_options / teardown_minutes /
-- sanitation_required canonically belong to migration 17 (Bloco 2 / PR #5).
-- If this migration runs in a fresh environment where Bloco 2 hasn't landed
-- yet, the view definition below would fail with "column does not exist".
-- Adding them here with IF NOT EXISTS is idempotent and keeps the migration
-- self-contained — once Bloco 2 merges, these statements become no-ops.
do $$ begin
  create type airfnb_dietary_tag as enum ('vegan','vegetarian','gluten_free','lactose_free','nut_free','halal','kosher','spicy');
exception when duplicate_object then null;
end $$;

alter table public.airfnb_trucks
  add column if not exists cuisine_types       text[]               default '{}',
  add column if not exists dietary_options     airfnb_dietary_tag[] default '{}',
  add column if not exists teardown_minutes    int                  default 60,
  add column if not exists sanitation_required text                 default 'none',
  add column if not exists catering_type       text                 default 'fixed',
  -- "serves" tracks what the truck offers (food / drinks / both) — the
  -- catalog filter modal exposes this as "Tipo de Catering".
  add column if not exists serves              text                 default 'food_and_drinks';

do $$ begin
  alter table public.airfnb_trucks
    add constraint airfnb_trucks_serves_chk
    check (serves in ('food','drinks','food_and_drinks'));
exception when duplicate_object then null;
end $$;

drop view if exists public.airfnb_v_truck_card cascade;
create view public.airfnb_v_truck_card with (security_invoker = true) as
select
  t.id, t.slug, t.name, t.tagline, t.base_city, t.capacity,
  t.base_price, t.price_per_pax, t.min_event_pax, t.max_event_pax,
  t.service_radius_km,
  t.cuisine_types, t.dietary_options, t.catering_type, t.serves,
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
