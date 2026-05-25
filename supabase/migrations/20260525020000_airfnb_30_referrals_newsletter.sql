-- airfnb_30: referral programme + newsletter capture.
--
-- Referrals: every profile gets a permanent short code (auto-generated on
-- first need). Visiting /signup?ref=CODE marks the new user's referred_by.
-- Newsletter: capture-only table; sending is out of scope here.

-- ---- profile additions ----
alter table public.airfnb_profiles
  add column if not exists referral_code     text,
  add column if not exists referred_by       uuid references public.airfnb_profiles(id) on delete set null,
  add column if not exists referrals_count   int default 0;

-- Generator: 8-char base32 (no ambiguous chars). Idempotent — only sets the
-- column if it's still null.
create or replace function public.airfnb_generate_referral_code()
returns text
language plpgsql
as $$
declare
  v_code text;
  v_attempts int := 0;
begin
  loop
    v_attempts := v_attempts + 1;
    -- Base32 alphabet without 0/O/I/L
    v_code := upper(substr(encode(gen_random_bytes(6), 'base64'), 1, 8));
    v_code := regexp_replace(v_code, '[+/=0OIL]', 'X', 'g');
    exit when not exists (select 1 from public.airfnb_profiles where referral_code = v_code);
    if v_attempts > 10 then raise exception 'could not generate unique referral code'; end if;
  end loop;
  return v_code;
end $$;

-- Trigger: assign referral_code on profile insert if missing.
create or replace function public.airfnb_assign_referral_code()
returns trigger
language plpgsql
as $$
begin
  if new.referral_code is null then
    new.referral_code := public.airfnb_generate_referral_code();
  end if;
  return new;
end $$;
drop trigger if exists airfnb_profile_referral_code on public.airfnb_profiles;
create trigger airfnb_profile_referral_code
  before insert on public.airfnb_profiles
  for each row execute function public.airfnb_assign_referral_code();

-- Backfill: existing profiles without a code get one.
update public.airfnb_profiles
   set referral_code = public.airfnb_generate_referral_code()
 where referral_code is null;

create unique index if not exists airfnb_profiles_referral_code_uniq
  on public.airfnb_profiles (referral_code) where referral_code is not null;

-- ---- referred-by attribution RPC ----
-- Called from /signup when ?ref=CODE is present. SECURITY DEFINER so the
-- signing-up user (whose profile may not exist yet at trigger time) can set
-- the link from their own profile row. Refuses self-referral and re-attribution.
create or replace function public.airfnb_apply_referral(p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_referrer uuid;
  v_updated int;
begin
  if v_uid is null or p_code is null or length(p_code) < 6 then return false; end if;
  select id into v_referrer
    from public.airfnb_profiles
   where referral_code = upper(p_code) and id <> v_uid;
  if v_referrer is null then return false; end if;

  -- Only credit the referrer when the attribution UPDATE actually changed
  -- a row. Without this, repeat calls / users with referred_by already set
  -- would let the caller inflate someone's count by replaying the RPC.
  update public.airfnb_profiles
     set referred_by = v_referrer
   where id = v_uid and referred_by is null;
  get diagnostics v_updated = row_count;
  if v_updated = 0 then return false; end if;

  update public.airfnb_profiles
     set referrals_count = referrals_count + 1
   where id = v_referrer;

  return true;
end $$;
revoke execute on function public.airfnb_apply_referral(text) from public, anon;
grant  execute on function public.airfnb_apply_referral(text) to authenticated;

-- ---- newsletter subscriptions ----
create table if not exists public.airfnb_newsletter_subs (
  id             uuid primary key default gen_random_uuid(),
  email          text unique not null,
  source         text,
  confirmed_at   timestamptz,
  unsubscribed_at timestamptz,
  created_at     timestamptz default now()
);
alter table public.airfnb_newsletter_subs enable row level security;

-- Anyone can subscribe; only admins can read the list (no SELECT for public).
do $$ begin
  create policy "airfnb_newsletter_anyone_insert"
    on public.airfnb_newsletter_subs for insert with check (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "airfnb_newsletter_admin_read"
    on public.airfnb_newsletter_subs for select using (public.airfnb_is_admin());
exception when duplicate_object then null; end $$;
