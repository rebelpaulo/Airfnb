-- Keep referral-code generation independent of the caller's search_path.
-- Supabase installs pgcrypto in the `extensions` schema; the auth trigger runs
-- with `search_path = public`, so the extension function must be qualified.
create or replace function public.airfnb_generate_referral_code()
returns text
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_code text;
  v_attempts integer := 0;
begin
  loop
    v_attempts := v_attempts + 1;

    -- Preserve the existing eight-character, uppercase normalization contract.
    v_code := upper(substr(encode(extensions.gen_random_bytes(6), 'base64'), 1, 8));
    v_code := regexp_replace(v_code, '[+/=0OIL]', 'X', 'g');

    if not exists (
      select 1
        from public.airfnb_profiles
       where referral_code = v_code
    ) then
      return v_code;
    end if;

    if v_attempts >= 10 then
      raise exception 'could not generate unique referral code after % attempts', v_attempts;
    end if;
  end loop;
end
$$;

-- The profile trigger must be able to call the private generator even when a
-- profile insert originates from a role that cannot execute it directly.
create or replace function public.airfnb_assign_referral_code()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.referral_code is null then
    new.referral_code := public.airfnb_generate_referral_code();
  end if;
  return new;
end
$$;

-- Trigger functions and the generator are internal implementation details.
-- Their owners can still execute them from the trigger chain.
revoke execute on function public.airfnb_generate_referral_code() from public, anon, authenticated;
revoke execute on function public.airfnb_assign_referral_code() from public, anon, authenticated;
revoke execute on function public.airfnb_handle_new_user() from public, anon, authenticated;
