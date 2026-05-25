-- airfnb_27: enforce rate limits at the DB level via BEFORE INSERT triggers
-- so the cap applies even if a client bypasses the wizard / server action.
-- The client-side guard stays as a UX optimisation (immediate feedback);
-- this is the actual security boundary.

create or replace function public.airfnb_event_requests_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- 10 published event_requests per organizer per day. Matches the wizard
  -- limit but enforced regardless of how the row gets inserted.
  if not public.airfnb_check_rate_limit(
       'event_request_create',
       new.organizer_id::text,
       10,
       86400
     ) then
    raise exception 'Rate limit exceeded: max 10 pedidos publicados por dia';
  end if;
  return new;
end $$;

drop trigger if exists airfnb_event_requests_rate_limit_trg on public.airfnb_event_requests;
create trigger airfnb_event_requests_rate_limit_trg
  before insert on public.airfnb_event_requests
  for each row execute function public.airfnb_event_requests_rate_limit();

create or replace function public.airfnb_applications_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- 50 applications per truck per day — same UX cap, hardened at DB.
  if not public.airfnb_check_rate_limit(
       'application_submit',
       new.truck_id::text,
       50,
       86400
     ) then
    raise exception 'Rate limit exceeded: max 50 candidaturas por truck por dia';
  end if;
  return new;
end $$;

drop trigger if exists airfnb_applications_rate_limit_trg on public.airfnb_applications;
create trigger airfnb_applications_rate_limit_trg
  before insert on public.airfnb_applications
  for each row execute function public.airfnb_applications_rate_limit();
