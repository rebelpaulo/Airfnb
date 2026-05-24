-- airfnb_19: fields required by the organizer 5-step /publicar wizard.
--
-- The original /organizeEvent flow captures more than what the marketplace
-- table currently models — personal contact info, a single budget estimate
-- (with a "flexible" flag), the catering type, cuisine/dietary preferences,
-- venue logistics (setup/teardown hours, energy needs, sanitation), an
-- adjacent-services pick list, and the final selection mode.
--
-- We add nullable columns so existing rows stay valid. RLS already covers
-- airfnb_event_requests via the organizer_id link; no policy changes needed.

-- ---- enums --------------------------------------------------------------

do $$ begin
  create type airfnb_catering_type as enum ('food','drinks','food_and_drinks');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type airfnb_energy_need as enum ('nao_preciso','ate_3kw','3_a_10kw','mais_10kw');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type airfnb_sanitation_level as enum ('nao_necessario','wc_proximo','wc_dedicado');
exception when duplicate_object then null;
end $$;

-- 'open_to_offers' mirrors broadcast (anyone matching can apply);
-- 'pick_myself'   mirrors curated (organizer hand-picks from catalog);
-- 'assisted'      → human help from the Air F&B team (lands as broadcast
--                   server-side and flags `assistance_requested=true`).
do $$ begin
  create type airfnb_selection_mode as enum ('open_to_offers','pick_myself','assisted');
exception when duplicate_object then null;
end $$;

-- ---- airfnb_event_requests additions -----------------------------------

alter table public.airfnb_event_requests
  add column if not exists contact_name        text,
  add column if not exists contact_email       text,
  add column if not exists contact_phone       text,
  add column if not exists address_line        text,
  add column if not exists locality            text,
  add column if not exists budget_estimate     numeric(10,2),
  add column if not exists budget_flexible     boolean              default false,
  add column if not exists catering_type       airfnb_catering_type default 'food_and_drinks',
  add column if not exists desired_cuisines    text[]               default '{}',
  add column if not exists setup_minutes       int,
  add column if not exists teardown_minutes    int,
  add column if not exists energy_need         airfnb_energy_need,
  add column if not exists energy_assistance   boolean              default false,
  add column if not exists sanitation_level    airfnb_sanitation_level,
  add column if not exists extra_services      text[]               default '{}',
  add column if not exists selection_mode      airfnb_selection_mode default 'open_to_offers',
  add column if not exists assistance_requested boolean             default false;

-- For wizard-completion partial sorting in the future, keep a status+date idx.
create index if not exists airfnb_event_requests_status_start_idx
  on public.airfnb_event_requests (status, start_at);
