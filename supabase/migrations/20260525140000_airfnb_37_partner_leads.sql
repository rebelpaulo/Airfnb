-- Partner-services lead capture.
--
-- The 4 service pages (Espaços p/ Eventos, Gestão de Convidados,
-- Música & Animação, Marketing & Publicidade) are upsells: each pitches a
-- partner company / sister business and captures a lead via a form.
-- Leads land here so the team can route them out to the right partner.
--
-- Notification email destinations are still hard-coded as env vars on the
-- server action (PARTNER_EMAIL_VENUES, _GUEST_MGMT, _MUSIC, _MARKETING) —
-- TODO: move to /admin/definicoes once that page exists.

-- Postgres has no `create type if not exists`; wrap in a do block instead.
do $$ begin
  create type public.airfnb_partner_lead_kind as enum (
    'venues',       -- Espaços p/ Eventos
    'guest_mgmt',   -- Gestão de Convidados (3cket)
    'music',        -- Música & Animação
    'marketing'     -- Marketing & Publicidade
  );
exception when duplicate_object then null; end $$;

create table if not exists public.airfnb_partner_leads (
  id           uuid primary key default gen_random_uuid(),
  kind         public.airfnb_partner_lead_kind not null,
  name         text not null,
  email        text not null,
  phone        text,
  payload      jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now(),
  -- Operational audit trail
  handled_at   timestamptz,
  handled_by   uuid references public.airfnb_profiles(id) on delete set null,
  notes        text
);

create index if not exists airfnb_partner_leads_kind_created_idx
  on public.airfnb_partner_leads (kind, created_at desc);
create index if not exists airfnb_partner_leads_unhandled_idx
  on public.airfnb_partner_leads (created_at desc) where handled_at is null;

alter table public.airfnb_partner_leads enable row level security;

-- Anyone can insert (no auth needed — these are conversion forms on public pages).
-- We accept anon submissions because the user might not be logged in when they
-- discover the upsell. Spam is filtered by the (kind, email, day) rate limit
-- in the application server action, not at the policy level.
drop policy if exists airfnb_partner_leads_insert on public.airfnb_partner_leads;
create policy airfnb_partner_leads_insert on public.airfnb_partner_leads
  for insert with check (true);

-- Reads are admin/staff only.
drop policy if exists airfnb_partner_leads_admin_read on public.airfnb_partner_leads;
create policy airfnb_partner_leads_admin_read on public.airfnb_partner_leads
  for select using (public.airfnb_is_admin());

-- Updates (e.g. marking handled) admin only.
drop policy if exists airfnb_partner_leads_admin_update on public.airfnb_partner_leads;
create policy airfnb_partner_leads_admin_update on public.airfnb_partner_leads
  for update using (public.airfnb_is_admin()) with check (public.airfnb_is_admin());
