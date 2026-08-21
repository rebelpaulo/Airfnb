-- Model the three supplier directions without renaming the legacy
-- airfnb_trucks relation. Existing rows remain valid food-truck suppliers and
-- new rows can opt into catering or bar explicitly.

begin;

do $$
begin
  create type public.airfnb_service_type as enum (
    'food_truck',
    'catering',
    'bar'
  );
exception
  when duplicate_object then null;
end
$$;

alter table public.airfnb_trucks
  add column if not exists service_type public.airfnb_service_type
    not null default 'food_truck';

-- The default on ADD COLUMN backfills legacy rows. Keep this explicit update
-- for installations where a previous interrupted attempt left the column
-- nullable, then restore the intended invariant.
update public.airfnb_trucks
   set service_type = 'food_truck'::public.airfnb_service_type
 where service_type is null;

alter table public.airfnb_trucks
  alter column service_type set default 'food_truck'::public.airfnb_service_type,
  alter column service_type set not null;

create index if not exists airfnb_trucks_active_service_type_idx
  on public.airfnb_trucks(service_type)
  where status = 'active'::public.airfnb_truck_status;

-- The moderation migration deliberately replaced table-wide writes with
-- column grants. Extend that boundary by this one non-moderation column only.
grant insert (service_type) on table public.airfnb_trucks to authenticated;
grant update (service_type) on table public.airfnb_trucks to authenticated;

-- Keep every column and ordering rule from migration 43. CREATE OR REPLACE
-- preserves the view identity and its dependencies; service_type is appended
-- so existing columns retain their names, order and types.
create or replace view public.airfnb_v_truck_card
with (security_invoker = true) as
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
  ) as category_slugs,
  t.service_type
from public.airfnb_trucks t
where t.status = 'active'::public.airfnb_truck_status;

revoke all on table public.airfnb_v_truck_card from public;
grant select on table public.airfnb_v_truck_card
  to anon, authenticated, service_role;

commit;
