-- airfnb_26: anti-spam scaffolding — rate limits + multi-truck-per-company
-- de-duplication.
--
-- The marketplace is plausibly exploitable: an owner spamming applications
-- across requests floods organizers; an organizer publishing many duplicate
-- briefs floods trucks; a single company registering many trucks dilutes
-- the catalog. This adds:
--
-- 1. airfnb_rate_limits — a counter table keyed on (action, bucket) with
--    a TTL window. Generic; used by future actions too.
-- 2. airfnb_check_rate_limit(action, bucket, limit_per_window, window_seconds)
--    RPC: increment + check in one round-trip, returns false when over limit.
-- 3. Unique index on airfnb_profiles.vat_number (when not null) so the same
--    company can't open multiple OWNER profiles. Trucks can still be
--    multi-per-owner — the constraint is at the legal-entity level.

create table if not exists public.airfnb_rate_limits (
  action     text        not null,
  bucket     text        not null,
  count      int         not null default 0,
  window_at  timestamptz not null default now(),
  primary key (action, bucket)
);

create or replace function public.airfnb_check_rate_limit(
  p_action          text,
  p_bucket          text,
  p_limit_per_window int,
  p_window_seconds   int
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
  v_window_at timestamptz;
begin
  -- Upsert + atomic increment in a single round-trip. The window resets
  -- when the bucket is older than p_window_seconds — keeps the table from
  -- growing unbounded and avoids a separate sweep job.
  insert into public.airfnb_rate_limits (action, bucket, count, window_at)
  values (p_action, p_bucket, 1, now())
  on conflict (action, bucket) do update
    set count     = case
                      when public.airfnb_rate_limits.window_at < now() - (p_window_seconds || ' seconds')::interval
                      then 1
                      else public.airfnb_rate_limits.count + 1
                    end,
        window_at = case
                      when public.airfnb_rate_limits.window_at < now() - (p_window_seconds || ' seconds')::interval
                      then now()
                      else public.airfnb_rate_limits.window_at
                    end
  returning count, window_at into v_count, v_window_at;

  return v_count <= p_limit_per_window;
end $$;

revoke execute on function public.airfnb_check_rate_limit(text, text, int, int) from public, anon;
grant  execute on function public.airfnb_check_rate_limit(text, text, int, int) to authenticated;

-- One owner profile per legal entity (VAT). Existing rows with null vat
-- keep working (partial unique idx).
create unique index if not exists airfnb_profiles_vat_uniq
  on public.airfnb_profiles (vat_number)
  where vat_number is not null;
