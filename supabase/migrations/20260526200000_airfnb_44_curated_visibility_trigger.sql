-- pick_myself / curated requests should be PRIVATE: they aren't meant
-- for the broadcast feed every truck owner scans; only invited trucks
-- ought to see them. The wizard already sets `selection_mode='pick_myself'`
-- and `discovery_mode='curated'`, but `visibility` defaulted to 'public'
-- because the public-facing search needs broadcast requests visible.
--
-- A BEFORE INSERT / UPDATE trigger normalises visibility so the
-- discovery_mode column is the single source of truth — server / client
-- code can set discovery_mode and trust visibility follows.

create or replace function public.airfnb_event_request_visibility_sync()
returns trigger
language plpgsql
as $$
begin
  if new.discovery_mode = 'curated' then
    new.visibility := 'private';
  elsif new.discovery_mode in ('broadcast', 'auto_match') and new.visibility is null then
    new.visibility := 'public';
  end if;
  return new;
end $$;

drop trigger if exists airfnb_event_request_visibility_sync_trg on public.airfnb_event_requests;
create trigger airfnb_event_request_visibility_sync_trg
  before insert or update of discovery_mode on public.airfnb_event_requests
  for each row execute function public.airfnb_event_request_visibility_sync();

-- Retro-fix any existing curated rows that slipped through with
-- visibility='public' (created before this trigger landed).
update public.airfnb_event_requests
   set visibility = 'private'
 where discovery_mode = 'curated'
   and visibility = 'public';
