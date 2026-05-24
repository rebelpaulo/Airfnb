-- airfnb_25: bidirectional reviews — trucks rate organizers.
--
-- The existing airfnb_reviews captures the organizer→truck direction only
-- (rating_food / rating_service / rating_value). This adds the reciprocal
-- direction with a separate table because the rating dimensions differ —
-- a truck cares about reliability, communication and payment timeliness
-- rather than food quality.
--
-- One review per (booking, truck) — a multi-truck event lets each truck
-- post its own assessment of the organizer.

create table if not exists public.airfnb_organizer_reviews (
  id                    uuid primary key default gen_random_uuid(),
  booking_id            uuid not null references public.airfnb_bookings(id) on delete cascade,
  truck_id              uuid not null references public.airfnb_trucks(id)   on delete cascade,
  organizer_id          uuid not null references public.airfnb_profiles(id) on delete cascade,
  rating_reliability    smallint check (rating_reliability    between 1 and 5),
  rating_communication  smallint check (rating_communication  between 1 and 5),
  rating_payment        smallint check (rating_payment        between 1 and 5),
  rating_overall        numeric(2,1),
  body                  text,
  reply_body            text,
  reply_at              timestamptz,
  is_verified           boolean default false,
  created_at            timestamptz default now(),
  unique (booking_id, truck_id)
);

create index if not exists airfnb_organizer_reviews_org_idx
  on public.airfnb_organizer_reviews (organizer_id);

-- Aggregate columns on the profile so the organizer dashboard / catalog
-- can render the score without scanning the reviews table each time.
alter table public.airfnb_profiles
  add column if not exists organizer_rating_avg   numeric(2,1) default 0,
  add column if not exists organizer_rating_count int          default 0;

-- Recompute trigger — mirrors airfnb_truck_rating_recompute from migration 05.
create or replace function public.airfnb_organizer_rating_recompute()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare oid uuid := coalesce(new.organizer_id, old.organizer_id);
begin
  update public.airfnb_profiles p set
    organizer_rating_avg   = coalesce(
      (select round(avg(rating_overall)::numeric, 1)
         from public.airfnb_organizer_reviews where organizer_id = oid), 0),
    organizer_rating_count = (
      select count(*) from public.airfnb_organizer_reviews where organizer_id = oid)
  where p.id = oid;
  return coalesce(new, old);
end $$;

drop trigger if exists airfnb_organizer_reviews_recompute on public.airfnb_organizer_reviews;
create trigger airfnb_organizer_reviews_recompute
  after insert or update or delete on public.airfnb_organizer_reviews
  for each row execute function public.airfnb_organizer_rating_recompute();

-- Compute rating_overall as the average of the three dimension scores on
-- insert/update so callers don't have to. Keeps the field in sync without
-- an extra round-trip.
create or replace function public.airfnb_organizer_review_overall()
returns trigger
language plpgsql
as $$
begin
  new.rating_overall := round((
    coalesce(new.rating_reliability, 0)
    + coalesce(new.rating_communication, 0)
    + coalesce(new.rating_payment, 0)
  )::numeric / nullif(
    (case when new.rating_reliability   is not null then 1 else 0 end)
    + (case when new.rating_communication is not null then 1 else 0 end)
    + (case when new.rating_payment      is not null then 1 else 0 end), 0
  ), 1);
  return new;
end $$;

drop trigger if exists airfnb_organizer_reviews_overall on public.airfnb_organizer_reviews;
create trigger airfnb_organizer_reviews_overall
  before insert or update on public.airfnb_organizer_reviews
  for each row execute function public.airfnb_organizer_review_overall();

-- ---- RLS -------------------------------------------------------------
alter table public.airfnb_organizer_reviews enable row level security;

-- Anyone can SELECT (organizer ratings are public, same as truck ratings).
do $$ begin
  create policy "airfnb_org_reviews_public_read"
    on public.airfnb_organizer_reviews for select using (true);
exception when duplicate_object then null; end $$;

-- INSERT: only the owner of a truck that actually participated in the
-- booking can write the review.
do $$ begin
  create policy "airfnb_org_reviews_truck_owner_insert"
    on public.airfnb_organizer_reviews for insert to authenticated
    with check (
      exists (
        select 1
          from public.airfnb_booking_trucks bt
          join public.airfnb_trucks   t on t.id = bt.truck_id
          join public.airfnb_bookings b on b.id = bt.booking_id
         where bt.booking_id = airfnb_organizer_reviews.booking_id
           and bt.truck_id   = airfnb_organizer_reviews.truck_id
           and t.owner_id    = auth.uid()
           -- bind organizer_id to the booking's organizer so a truck owner
           -- can't crash a different organizer's score by spoofing the field
           and b.organizer_id = airfnb_organizer_reviews.organizer_id
      )
    );
exception when duplicate_object then null; end $$;

-- UPDATE: the truck owner can edit their own review body; the organizer can
-- post a reply (separate column to keep the audit clean).
do $$ begin
  create policy "airfnb_org_reviews_truck_owner_update"
    on public.airfnb_organizer_reviews for update to authenticated
    using (
      exists (select 1 from public.airfnb_trucks t
               where t.id = airfnb_organizer_reviews.truck_id
                 and t.owner_id = auth.uid())
    )
    with check (
      exists (select 1 from public.airfnb_trucks t
               where t.id = airfnb_organizer_reviews.truck_id
                 and t.owner_id = auth.uid())
    );
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "airfnb_org_reviews_organizer_reply"
    on public.airfnb_organizer_reviews for update to authenticated
    using (organizer_id = auth.uid())
    with check (organizer_id = auth.uid());
exception when duplicate_object then null; end $$;
