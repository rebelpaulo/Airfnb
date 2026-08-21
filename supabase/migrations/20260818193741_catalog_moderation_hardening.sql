-- Close the supplier-profile moderation bypass without moving the current
-- onboarding/editor flows behind a new API. Ordinary authenticated owners may
-- write catalog/logistics fields only; moderation, ranking, compliance and
-- ownership fields remain server-owned.

begin;

-- The legacy FOR ALL policy allowed an owner to delete a profile and to forge
-- any column, including featured/rating/subscription and active status.
drop policy if exists "airfnb_trucks_owner_write" on public.airfnb_trucks;
drop policy if exists "airfnb_trucks_owner_insert" on public.airfnb_trucks;
drop policy if exists "airfnb_trucks_owner_update" on public.airfnb_trucks;

create policy "airfnb_trucks_owner_insert"
  on public.airfnb_trucks
  for insert
  to authenticated
  with check (
    owner_id = (select auth.uid())
    or public.airfnb_is_admin()
  );

create policy "airfnb_trucks_owner_update"
  on public.airfnb_trucks
  for update
  to authenticated
  using (
    owner_id = (select auth.uid())
    or public.airfnb_is_admin()
  )
  with check (
    owner_id = (select auth.uid())
    or public.airfnb_is_admin()
  );

-- Remove table-wide mutation rights, including any rights inherited through
-- PUBLIC, before granting the exact columns used by TruckWizard and the truck
-- profile/status actions. SELECT remains unchanged.
revoke insert, update, delete on table public.airfnb_trucks
  from public, anon, authenticated;

grant insert (
  owner_id,
  slug,
  name,
  tagline,
  description,
  base_city,
  service_radius_km,
  capacity,
  min_event_pax,
  max_event_pax,
  base_price,
  price_per_pax,
  setup_minutes,
  power_required_kw,
  needs_water,
  dimensions_m,
  status,
  cuisine_types,
  dietary_options,
  teardown_minutes,
  sanitation_required,
  catering_type,
  serves,
  compatible_event_kinds
) on table public.airfnb_trucks to authenticated;

grant update (
  name,
  tagline,
  description,
  base_city,
  service_radius_km,
  capacity,
  min_event_pax,
  max_event_pax,
  base_price,
  price_per_pax,
  setup_minutes,
  power_required_kw,
  needs_water,
  dimensions_m,
  status,
  cuisine_types,
  dietary_options,
  teardown_minutes,
  sanitation_required,
  catering_type,
  serves,
  compatible_event_kinds
) on table public.airfnb_trucks to authenticated;

-- Column grants are the primary boundary. This trigger adds row-aware insert
-- invariants and the small owner status state machine. SECURITY DEFINER
-- moderation/rating functions execute as the table owner and service-role
-- maintenance remains trusted; a direct authenticated admin is still checked
-- by airfnb_is_admin(), matching the existing admin model.
create or replace function public.airfnb_guard_truck_moderation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  v_table_owner name;
  v_is_trusted boolean;
begin
  select pg_catalog.pg_get_userbyid(c.relowner)
    into v_table_owner
    from pg_catalog.pg_class c
   where c.oid = 'public.airfnb_trucks'::pg_catalog.regclass;

  v_is_trusted := current_user = v_table_owner
                  or current_user = 'service_role'
                  or public.airfnb_is_admin();

  if v_is_trusted then
    return new;
  end if;

  if (select auth.uid()) is null then
    raise exception 'authenticated supplier identity required'
      using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    if new.owner_id is distinct from (select auth.uid()) then
      raise exception 'supplier owner must match authenticated user'
        using errcode = '42501';
    end if;

    if new.status is distinct from 'draft'::public.airfnb_truck_status then
      raise exception 'new supplier profiles must start in draft'
        using errcode = '42501';
    end if;

    if new.rating_avg is distinct from 0::numeric
       or new.rating_count is distinct from 0
       or new.featured is distinct from false
       or new.subscription_tier is distinct from 'basic'
       or new.homologation_expires_at is not null
       or new.insurance_expires_at is not null
       or new.lead_response_rate is not null
       or new.last_active_at is not null then
      raise exception 'server-owned supplier fields must retain their defaults'
        using errcode = '42501';
    end if;

    return new;
  end if;

  if old.owner_id is distinct from (select auth.uid())
     or new.owner_id is distinct from old.owner_id then
    raise exception 'supplier ownership is immutable'
      using errcode = '42501';
  end if;

  if new.id is distinct from old.id
     or new.slug is distinct from old.slug
     or new.rating_avg is distinct from old.rating_avg
     or new.rating_count is distinct from old.rating_count
     or new.featured is distinct from old.featured
     or new.subscription_tier is distinct from old.subscription_tier
     or new.homologation_expires_at is distinct from old.homologation_expires_at
     or new.insurance_expires_at is distinct from old.insurance_expires_at
     or new.lead_response_rate is distinct from old.lead_response_rate
     or new.last_active_at is distinct from old.last_active_at
     or new.created_at is distinct from old.created_at then
    raise exception 'server-owned supplier fields are immutable'
      using errcode = '42501';
  end if;

  if new.status is not distinct from old.status then
    return new;
  end if;

  if (old.status = 'draft'::public.airfnb_truck_status
      and new.status = 'pending_review'::public.airfnb_truck_status)
     or (old.status = 'active'::public.airfnb_truck_status
         and new.status = 'paused'::public.airfnb_truck_status)
     or (old.status = 'paused'::public.airfnb_truck_status
         and new.status = 'active'::public.airfnb_truck_status) then
    return new;
  end if;

  raise exception 'supplier status transition is not allowed'
    using errcode = '42501';
end;
$$;

revoke execute on function public.airfnb_guard_truck_moderation()
  from public, anon, authenticated;

drop trigger if exists airfnb_trg_trucks_moderation on public.airfnb_trucks;
create trigger airfnb_trg_trucks_moderation
  before insert or update on public.airfnb_trucks
  for each row
  execute function public.airfnb_guard_truck_moderation();

-- Keep trusted entrypoints compatible while removing mutable function paths.
alter function public.airfnb_admin_approve_truck(uuid)
  set search_path = pg_catalog, public;
alter function public.airfnb_admin_reject_truck(uuid, text)
  set search_path = pg_catalog, public;
alter function public.airfnb_recalc_truck_rating()
  set search_path = pg_catalog, public;
alter function public.airfnb_touch_updated_at()
  set search_path = pg_catalog, public;

commit;
