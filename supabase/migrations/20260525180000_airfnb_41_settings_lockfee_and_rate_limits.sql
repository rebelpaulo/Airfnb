-- Migrate hard-coded platform constants into airfnb_platform_settings so the
-- team can edit them from /admin/definicoes without a redeploy / migration.
--
-- Three groups join the existing 'leads' group:
--   - lock_fee       — split between platform and organizer
--   - rate_limit     — anti-spam DB triggers
--
-- The strategy is: keep the same numeric defaults baked in as fallbacks, so
-- behaviour is identical until an admin actually changes a row. The PL/pgSQL
-- functions read from settings on every call, NOT cached — this table is
-- tiny and the read is a single primary-key lookup.

-- =========================================================================
-- 1. SQL helper: read an integer setting, with a fallback if the row is
--    missing or the value can't be parsed. SECURITY DEFINER so it can
--    read airfnb_platform_settings despite the admin-only RLS policy.
-- =========================================================================
create or replace function public.airfnb_setting_int(p_key text, p_fallback int)
returns int
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_raw text;
  v_parsed int;
begin
  select value into v_raw
    from public.airfnb_platform_settings
   where key = p_key;
  if v_raw is null or btrim(v_raw) = '' then
    return p_fallback;
  end if;
  begin
    v_parsed := btrim(v_raw)::int;
  exception when others then
    return p_fallback;
  end;
  return v_parsed;
end $$;

revoke execute on function public.airfnb_setting_int(text, int) from public, anon;
grant  execute on function public.airfnb_setting_int(text, int) to authenticated, service_role;

-- =========================================================================
-- 2. Lock-fee calculator now reads the split from settings. Defaults match
--    the previous hard-coded 25/25 = €50 split so behaviour is preserved.
-- =========================================================================
create or replace function public.airfnb_calculate_lock_fee(p_application uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_platform_fee    numeric;
  v_organizer_share numeric;
begin
  -- Read from settings table; fall back to the historical 25/25 split.
  v_platform_fee    := public.airfnb_setting_int('lock_fee.platform_fee',    25);
  v_organizer_share := public.airfnb_setting_int('lock_fee.organizer_share', 25);

  perform 1 from public.airfnb_applications where id = p_application;
  return jsonb_build_object(
    'platform_fee',    v_platform_fee,
    'organizer_share', v_organizer_share,
    'total',           v_platform_fee + v_organizer_share
  );
end $$;
revoke execute on function public.airfnb_calculate_lock_fee(uuid) from public, anon, authenticated;
grant  execute on function public.airfnb_calculate_lock_fee(uuid) to service_role;

-- =========================================================================
-- 3. Rate-limit triggers now read max-actions from settings. Same defaults.
-- =========================================================================
create or replace function public.airfnb_event_requests_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max int;
begin
  v_max := public.airfnb_setting_int('rate_limit.event_requests_per_day', 10);
  if not public.airfnb_check_rate_limit(
       'event_request_create',
       new.organizer_id::text,
       v_max,
       86400
     ) then
    raise exception 'Rate limit exceeded: max % pedidos publicados por dia', v_max;
  end if;
  return new;
end $$;

create or replace function public.airfnb_applications_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max int;
begin
  v_max := public.airfnb_setting_int('rate_limit.applications_per_day_per_truck', 50);
  if not public.airfnb_check_rate_limit(
       'application_submit',
       new.truck_id::text,
       v_max,
       86400
     ) then
    raise exception 'Rate limit exceeded: max % candidaturas por truck por dia', v_max;
  end if;
  return new;
end $$;

-- =========================================================================
-- 4. Seed the four new keys with their current production defaults so the
--    admin UI shows them immediately. Existing rows are left untouched.
-- =========================================================================
insert into public.airfnb_platform_settings (key, "group", description, value, secret) values
  ('lock_fee.platform_fee',                'lock_fee',   'Quota da plataforma no lock-fee, em €. Default 25.',                                                       '25', false),
  ('lock_fee.organizer_share',             'lock_fee',   'Quota retida para o organizer no lock-fee, em €. Default 25. Total cobrado ao truck = soma das duas quotas.', '25', false),
  ('rate_limit.event_requests_per_day',    'rate_limit', 'Máximo de pedidos de evento que um organizer pode publicar por dia. Default 10.',                          '10', false),
  ('rate_limit.applications_per_day_per_truck', 'rate_limit', 'Máximo de candidaturas que um truck pode submeter por dia. Default 50.',                                 '50', false)
on conflict (key) do nothing;
