-- airfnb_31: per-booking ICS token + helper RPC for the calendar endpoint.
--
-- Each booking gets a random opaque token (16-char base32). The public
-- /api/calendar/[token].ics endpoint trades the token for the booking
-- payload. Anyone with the link can add the event — same security model as
-- a shared calendar invite — so the token must be long enough to brute-
-- force-resist without an account lookup.

alter table public.airfnb_bookings
  add column if not exists ics_token text;

create unique index if not exists airfnb_bookings_ics_token_uniq
  on public.airfnb_bookings (ics_token) where ics_token is not null;

-- Generator: 16-char base32 alphabet without confusables.
create or replace function public.airfnb_make_ics_token()
returns text
language plpgsql
as $$
declare v_t text;
begin
  loop
    v_t := upper(substr(encode(gen_random_bytes(12), 'base64'), 1, 16));
    v_t := regexp_replace(v_t, '[+/=0OIL]', 'X', 'g');
    exit when not exists (select 1 from public.airfnb_bookings where ics_token = v_t);
  end loop;
  return v_t;
end $$;

-- Backfill: assign tokens to existing bookings that don't have one.
update public.airfnb_bookings
   set ics_token = public.airfnb_make_ics_token()
 where ics_token is null;

-- Trigger: assign on insert.
create or replace function public.airfnb_assign_ics_token()
returns trigger
language plpgsql
as $$
begin
  if new.ics_token is null then
    new.ics_token := public.airfnb_make_ics_token();
  end if;
  return new;
end $$;
drop trigger if exists airfnb_booking_ics_token_trg on public.airfnb_bookings;
create trigger airfnb_booking_ics_token_trg
  before insert on public.airfnb_bookings
  for each row execute function public.airfnb_assign_ics_token();

-- Public-by-token fetch RPC: bypasses RLS via SECURITY DEFINER, returns
-- only the fields needed for an ICS file. Anyone with the token can read.
create or replace function public.airfnb_booking_by_ics_token(p_token text)
returns table (
  id          uuid,
  title       text,
  starts_at   timestamptz,
  ends_at     timestamptz,
  city        text,
  organizer_id uuid,
  truck_names text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    b.id,
    coalesce(e.title, 'Air F&B event'),
    b.starts_at,
    coalesce(b.ends_at, b.starts_at + interval '4 hours'),
    coalesce(er.city, null),
    b.organizer_id,
    (select string_agg(t.name, ', ' order by t.name)
       from public.airfnb_booking_trucks bt
       join public.airfnb_trucks t on t.id = bt.truck_id
      where bt.booking_id = b.id)
    from public.airfnb_bookings b
    left join public.airfnb_events e on e.id = b.event_id
    left join public.airfnb_applications a on a.id = b.application_id
    left join public.airfnb_event_requests er on er.id = a.request_id
   where b.ics_token = p_token
   limit 1;
$$;
revoke execute on function public.airfnb_booking_by_ics_token(text) from public;
grant  execute on function public.airfnb_booking_by_ics_token(text) to anon, authenticated;
