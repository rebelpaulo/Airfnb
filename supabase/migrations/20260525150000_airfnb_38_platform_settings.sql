-- Platform settings — key/value store the team edits from /admin/definicoes
-- instead of redeploying for things like partner email addresses, lock-fee
-- splits, rate limits, etc.
--
-- Design:
--   - One row per setting; `group` keeps them organized in the UI
--   - `value` is text — readers cast (parseInt, parseFloat) as needed
--   - `description` is shown above the input in the admin form
--   - `secret` flag hides the value behind a password reveal (e.g. tokens
--      we don't want over-the-shoulder visible)
--
-- First batch of settings (seeded below): the 4 partner-lead destination
-- emails. PARTNER_EMAIL_* env vars become a fallback only — DB wins.

create table if not exists public.airfnb_platform_settings (
  key          text primary key,
  value        text,
  "group"      text not null default 'general',
  description  text,
  secret       boolean not null default false,
  updated_at   timestamptz not null default now(),
  updated_by   uuid references public.airfnb_profiles(id) on delete set null
);

create index if not exists airfnb_platform_settings_group_idx
  on public.airfnb_platform_settings ("group", key);

alter table public.airfnb_platform_settings enable row level security;

-- Admin-only read AND write. Anonymous / authenticated users have no
-- access — the helper reads via the service role on the server.
drop policy if exists airfnb_platform_settings_admin_read on public.airfnb_platform_settings;
create policy airfnb_platform_settings_admin_read on public.airfnb_platform_settings
  for select using (public.airfnb_is_admin());

drop policy if exists airfnb_platform_settings_admin_write on public.airfnb_platform_settings;
create policy airfnb_platform_settings_admin_write on public.airfnb_platform_settings
  for all using (public.airfnb_is_admin()) with check (public.airfnb_is_admin());

-- Touch updated_at on every update.
create or replace function public.airfnb_platform_settings_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists airfnb_trg_platform_settings_touch on public.airfnb_platform_settings;
create trigger airfnb_trg_platform_settings_touch
  before update on public.airfnb_platform_settings
  for each row execute function public.airfnb_platform_settings_touch();

-- Seed the partner-lead destination emails. Empty values fall through to
-- the env-var fallback in lib/partner-leads.ts.
insert into public.airfnb_platform_settings (key, "group", description, value, secret) values
  ('partner_email_venues',     'leads', 'Email para onde enviamos leads de "Espaços para Eventos".',           '', false),
  ('partner_email_guest_mgmt', 'leads', 'Email para leads de "Gestão de Convidados" (3cket).',                  '', false),
  ('partner_email_music',      'leads', 'Email para leads de "Música & Animação".',                              '', false),
  ('partner_email_marketing',  'leads', 'Email para leads de "Marketing & Publicidade".',                        '', false)
on conflict (key) do nothing;
