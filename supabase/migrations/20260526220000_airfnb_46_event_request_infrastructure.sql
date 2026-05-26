-- The wizard's "Saneamento Básico" step was a single-select for the WC
-- situation (none / nearby / dedicated). Real food-truck briefs need to
-- communicate WATER access too — mains tap vs. depósito vs. truck-only
-- vs. nothing — and the WC question itself is multi-select in practice
-- (a venue often has BOTH public WCs and a dedicated staff one).
--
-- Add two text[] columns alongside the legacy sanitation_level so we
-- don't break the /catalogo filter that still queries on it. The
-- wizard will continue to derive a legacy value from the WC chips so
-- the matching code keeps working until PR 7 migrates that to the
-- new fields.
--
-- Values are intentionally text (not an enum) — we want the freedom
-- to add 'lixo_oleos', 'esgoto_proximo', etc. without a migration
-- whenever the team learns something new from real bookings.

alter table public.airfnb_event_requests
  add column if not exists water_provided text[] not null default '{}',
  add column if not exists wc_provided    text[] not null default '{}';

-- Helpful for any future filter that wants "events offering mains water"
-- or similar — cheap to add now, expensive later (rewrite the column).
create index if not exists airfnb_event_requests_water_gin_idx
  on public.airfnb_event_requests using gin (water_provided);
create index if not exists airfnb_event_requests_wc_gin_idx
  on public.airfnb_event_requests using gin (wc_provided);
