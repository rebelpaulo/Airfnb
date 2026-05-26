-- airfnb_truck_images was a single bucket of photos with no semantic
-- distinction between "this is the truck" and "this is the food we serve".
-- Cards in the catalogo showed whatever the owner happened to mark as
-- is_cover, which in our demo data is uniformly food-on-a-plate — fine
-- for an Instagram grid, useless for "I'm hiring a food truck for an
-- event and want to see what it LOOKS like".
--
-- Add a `kind` enum so cards can prefer truck exterior shots and the
-- detail-page carousel can group photos meaningfully later. Existing
-- rows backfill to 'food' because every seeded image is a food photo.

do $$ begin
  create type public.airfnb_truck_image_kind as enum (
    'truck',   -- exterior / interior of the truck itself
    'food',    -- dishes, plating
    'team',    -- crew on duty
    'venue',   -- truck deployed at a real event
    'other'
  );
exception when duplicate_object then null; end $$;

alter table public.airfnb_truck_images
  add column if not exists kind public.airfnb_truck_image_kind not null default 'other';

-- Backfill: every existing image in the system is a food shot (seeded
-- from Unsplash food-on-plate URLs). Categorise them so the view ordering
-- behaves sensibly until owners re-upload truck exteriors.
update public.airfnb_truck_images
   set kind = 'food'
 where kind = 'other';

-- Index supports the view's `where kind = 'truck'` cover lookup.
create index if not exists airfnb_truck_images_truck_kind_idx
  on public.airfnb_truck_images(truck_id, kind, sort_order);

-- Rewrite the truck-card view:
--   cover_url       — prefer kind='truck' (any), then is_cover, then sort_order
--   gallery_urls    — text[] ordered (truck → food → team → venue → other)
--                     so the card preview can cycle through up to ~5 photos
--                     starting with the truck shot
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
  (
    select url from public.airfnb_truck_images i
     where i.truck_id = t.id
     order by
       case i.kind
         when 'truck' then 1
         when 'food'  then 2
         when 'venue' then 3
         when 'team'  then 4
         else 5
       end,
       (case when i.is_cover then 0 else 1 end),
       i.sort_order
     limit 1
  ) as cover_url,
  (
    -- ORDER must run BEFORE the LIMIT, otherwise Postgres picks 6
    -- arbitrary rows and truck-priority ordering is lost (the outer
    -- array_agg(... order by) only sorts whatever rows survived the
    -- truncation). Inner select sorts the full set; outer LIMIT keeps
    -- the top 6 for the carousel.
    select array_agg(url order by kind_rank, is_cover_rank, sort_order)
      from (
        select
          url,
          case kind
            when 'truck' then 1
            when 'food'  then 2
            when 'venue' then 3
            when 'team'  then 4
            else 5
          end as kind_rank,
          case when is_cover then 0 else 1 end as is_cover_rank,
          sort_order
        from public.airfnb_truck_images
       where truck_id = t.id
       order by
         case kind
           when 'truck' then 1
           when 'food'  then 2
           when 'venue' then 3
           when 'team'  then 4
           else 5
         end,
         (case when is_cover then 0 else 1 end),
         sort_order
       limit 6
      ) ordered
  ) as gallery_urls,
  array(
    select c.slug from public.airfnb_truck_categories tc
    join public.airfnb_categories c on c.id = tc.category_id
    where tc.truck_id = t.id
  ) as category_slugs
from public.airfnb_trucks t
where t.status = 'active';

-- Reseed demo: add a truck-exterior cover photo per existing demo truck,
-- and demote existing photos to kind='food' (already done above). The
-- existing food image becomes the second photo in the carousel.
-- Source: Unsplash search for "food truck" exterior shots.
insert into public.airfnb_truck_images (truck_id, url, alt, is_cover, sort_order, kind)
select t.id, v.url, t.name || ' (truck)', false, -1, 'truck'
  from public.airfnb_trucks t
  join (values
    ('divine-burguers',      'https://images.unsplash.com/photo-1565123409695-7b5ef63a2efb?w=900&q=80'),
    ('gypsy-kitchen',        'https://images.unsplash.com/photo-1542684964-eedfeac80a96?w=900&q=80'),
    ('el-mexicano',          'https://images.unsplash.com/photo-1601758174039-7b50305a6f0d?w=900&q=80'),
    ('la-dolce-vita',        'https://images.unsplash.com/photo-1623661321398-9b0c4f6e9c79?w=900&q=80'),
    ('bbq-kings',            'https://images.unsplash.com/photo-1601925240970-98447f56e7f0?w=900&q=80'),
    ('sushi-zen',            'https://images.unsplash.com/photo-1565123409695-7b5ef63a2efb?w=900&q=80'),
    ('taco-fiesta',          'https://images.unsplash.com/photo-1601758174614-c4070ba1cb5d?w=900&q=80'),
    ('turkish-delights',     'https://images.unsplash.com/photo-1565123409695-7b5ef63a2efb?w=900&q=80'),
    ('portuguese-tradition', 'https://images.unsplash.com/photo-1601758125946-6ec2ef64daf8?w=900&q=80'),
    ('wok-and-roll',         'https://images.unsplash.com/photo-1542684964-eedfeac80a96?w=900&q=80'),
    ('pizza-vesuvio',        'https://images.unsplash.com/photo-1601925240970-98447f56e7f0?w=900&q=80'),
    ('creperia-pt',          'https://images.unsplash.com/photo-1623661321398-9b0c4f6e9c79?w=900&q=80')
  ) as v(truck_slug, url) on v.truck_slug = t.slug
on conflict do nothing;
