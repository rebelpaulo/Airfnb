-- Harden conversation membership and both review directions.
--
-- Membership is created only by trusted marketplace RPCs. End users may read
-- their own membership row and advance its read marker, but cannot enroll
-- themselves in another conversation or rewrite either key.
--
-- Reviews remain public to read and authenticated participants may create one
-- after a confirmed/completed booking. Identity, relationship, verification,
-- timestamps and aggregate rating are established by the database. Published
-- reviews are immutable to API roles; the reviewed party can only add a reply
-- through the narrow SECURITY DEFINER functions at the end of this migration.

begin;

-- Review inserts are made by organizers, who cannot update a truck row. The
-- legacy aggregate trigger therefore has to perform its narrowly scoped
-- rating update as the function owner. Trigger invocation does not require
-- API roles to have EXECUTE on the trigger function.
create or replace function public.airfnb_recalc_truck_rating()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_truck_id uuid;
begin
  if tg_op = 'DELETE' then
    v_truck_id := old.truck_id;
  else
    v_truck_id := new.truck_id;
  end if;

  update public.airfnb_trucks t
     set rating_avg = coalesce(
           (
             select round(avg(r.rating_overall)::numeric, 1)
               from public.airfnb_reviews r
              where r.truck_id = v_truck_id
           ),
           0
         ),
         rating_count = (
           select count(*)
             from public.airfnb_reviews r
            where r.truck_id = v_truck_id
         )
   where t.id = v_truck_id;

  -- A trusted update that rebinds a historical row must also clear the old
  -- truck's aggregate. Direct API review updates remain revoked below.
  if tg_op = 'UPDATE' and old.truck_id is distinct from new.truck_id then
    v_truck_id := old.truck_id;
    update public.airfnb_trucks t
       set rating_avg = coalesce(
             (
               select round(avg(r.rating_overall)::numeric, 1)
                 from public.airfnb_reviews r
                where r.truck_id = v_truck_id
             ),
             0
           ),
           rating_count = (
             select count(*)
               from public.airfnb_reviews r
              where r.truck_id = v_truck_id
           )
     where t.id = v_truck_id;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke execute on function public.airfnb_recalc_truck_rating()
  from public, anon, authenticated;

-- -------------------------------------------------------------------------
-- Conversation participants: self-read + last_read_at only
-- -------------------------------------------------------------------------

drop policy if exists "airfnb_cp_self" on public.airfnb_conversation_participants;
drop policy if exists "airfnb_cp_select_self" on public.airfnb_conversation_participants;
drop policy if exists "airfnb_cp_update_read_marker" on public.airfnb_conversation_participants;

create policy "airfnb_cp_select_self"
  on public.airfnb_conversation_participants
  for select
  to authenticated
  using (user_id = (select auth.uid()));

create policy "airfnb_cp_update_read_marker"
  on public.airfnb_conversation_participants
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

revoke all on table public.airfnb_conversation_participants from public, anon, authenticated;
grant select on table public.airfnb_conversation_participants to authenticated;
grant update (last_read_at) on table public.airfnb_conversation_participants to authenticated;

-- -------------------------------------------------------------------------
-- Organizer -> truck reviews
-- -------------------------------------------------------------------------

create or replace function public.airfnb_prepare_truck_review()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := auth.uid();
  v_organizer uuid;
begin
  if v_actor is null then
    raise exception using errcode = '28000', message = 'authentication required';
  end if;

  if new.rating_food is null
     or new.rating_service is null
     or new.rating_value is null then
    raise exception using errcode = '23514', message = 'all truck review ratings are required';
  end if;

  select b.organizer_id
    into v_organizer
    from public.airfnb_bookings b
    join public.airfnb_booking_trucks bt
      on bt.booking_id = b.id
     and bt.truck_id = new.truck_id
   where b.id = new.booking_id
     and b.status in ('confirmed', 'completed');

  if not found then
    raise exception using errcode = '23514', message = 'truck did not participate in a reviewable booking';
  end if;

  if v_organizer is distinct from v_actor then
    raise exception using errcode = '42501', message = 'only the booking organizer may review this truck';
  end if;

  new.organizer_id := v_organizer;
  new.rating_overall := round(
    (new.rating_food + new.rating_service + new.rating_value)::numeric / 3,
    1
  );
  new.is_verified := true;
  new.reply_body := null;
  new.reply_at := null;
  new.created_at := statement_timestamp();
  return new;
end;
$$;

revoke execute on function public.airfnb_prepare_truck_review() from public, anon, authenticated;

drop trigger if exists airfnb_prepare_truck_review on public.airfnb_reviews;
create trigger airfnb_prepare_truck_review
  before insert on public.airfnb_reviews
  for each row execute function public.airfnb_prepare_truck_review();

drop policy if exists "airfnb_reviews_read" on public.airfnb_reviews;
drop policy if exists "airfnb_reviews_insert_organizer" on public.airfnb_reviews;
drop policy if exists "airfnb_reviews_owner_reply" on public.airfnb_reviews;
drop policy if exists "airfnb_reviews_public_read" on public.airfnb_reviews;
drop policy if exists "airfnb_reviews_participant_insert" on public.airfnb_reviews;

create policy "airfnb_reviews_public_read"
  on public.airfnb_reviews
  for select
  to anon, authenticated
  using (true);

create policy "airfnb_reviews_participant_insert"
  on public.airfnb_reviews
  for insert
  to authenticated
  with check (
    organizer_id = (select auth.uid())
    and is_verified is true
    and rating_food is not null
    and rating_service is not null
    and rating_value is not null
    and rating_overall = round(
      (rating_food + rating_service + rating_value)::numeric / 3,
      1
    )
    and reply_body is null
    and reply_at is null
  );

revoke all on table public.airfnb_reviews from public, anon, authenticated;
grant select on table public.airfnb_reviews to anon, authenticated;
grant insert on table public.airfnb_reviews to authenticated;

-- -------------------------------------------------------------------------
-- Truck -> organizer reviews
-- -------------------------------------------------------------------------

create or replace function public.airfnb_prepare_organizer_review()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := auth.uid();
  v_organizer uuid;
begin
  if v_actor is null then
    raise exception using errcode = '28000', message = 'authentication required';
  end if;

  if new.rating_reliability is null
     or new.rating_communication is null
     or new.rating_payment is null then
    raise exception using errcode = '23514', message = 'all organizer review ratings are required';
  end if;

  select b.organizer_id
    into v_organizer
    from public.airfnb_bookings b
    join public.airfnb_booking_trucks bt
      on bt.booking_id = b.id
     and bt.truck_id = new.truck_id
    join public.airfnb_trucks t
      on t.id = bt.truck_id
   where b.id = new.booking_id
     and b.status in ('confirmed', 'completed')
     and t.owner_id = v_actor;

  if not found then
    raise exception using errcode = '42501', message = 'only a participating truck owner may review this organizer';
  end if;

  new.organizer_id := v_organizer;
  new.rating_overall := round(
    (
      new.rating_reliability
      + new.rating_communication
      + new.rating_payment
    )::numeric / 3,
    1
  );
  new.is_verified := true;
  new.reply_body := null;
  new.reply_at := null;
  new.created_at := statement_timestamp();
  return new;
end;
$$;

revoke execute on function public.airfnb_prepare_organizer_review() from public, anon, authenticated;

drop trigger if exists airfnb_organizer_reviews_overall on public.airfnb_organizer_reviews;
drop trigger if exists airfnb_prepare_organizer_review on public.airfnb_organizer_reviews;
create trigger airfnb_prepare_organizer_review
  before insert on public.airfnb_organizer_reviews
  for each row execute function public.airfnb_prepare_organizer_review();

drop policy if exists "airfnb_org_reviews_public_read" on public.airfnb_organizer_reviews;
drop policy if exists "airfnb_org_reviews_truck_owner_insert" on public.airfnb_organizer_reviews;
drop policy if exists "airfnb_org_reviews_truck_owner_update" on public.airfnb_organizer_reviews;
drop policy if exists "airfnb_org_reviews_organizer_reply" on public.airfnb_organizer_reviews;
drop policy if exists "airfnb_org_reviews_participant_insert" on public.airfnb_organizer_reviews;

create policy "airfnb_org_reviews_public_read"
  on public.airfnb_organizer_reviews
  for select
  to anon, authenticated
  using (true);

create policy "airfnb_org_reviews_participant_insert"
  on public.airfnb_organizer_reviews
  for insert
  to authenticated
  with check (
    is_verified is true
    and rating_reliability is not null
    and rating_communication is not null
    and rating_payment is not null
    and rating_overall = round(
      (
        rating_reliability
        + rating_communication
        + rating_payment
      )::numeric / 3,
      1
    )
    and reply_body is null
    and reply_at is null
    and exists (
      select 1
        from public.airfnb_trucks t
       where t.id = airfnb_organizer_reviews.truck_id
         and t.owner_id = (select auth.uid())
    )
  );

revoke all on table public.airfnb_organizer_reviews from public, anon, authenticated;
grant select on table public.airfnb_organizer_reviews to anon, authenticated;
grant insert on table public.airfnb_organizer_reviews to authenticated;

-- -------------------------------------------------------------------------
-- Narrow, authenticated reply RPCs. Direct UPDATE/DELETE stays unavailable.
-- -------------------------------------------------------------------------

create or replace function public.airfnb_reply_to_truck_review(
  p_review uuid,
  p_reply text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := auth.uid();
  v_reply text := nullif(btrim(p_reply), '');
begin
  if v_actor is null then
    raise exception using errcode = '28000', message = 'authentication required';
  end if;
  if v_reply is null or char_length(v_reply) > 2000 then
    raise exception using errcode = '22023', message = 'reply must contain between 1 and 2000 characters';
  end if;

  update public.airfnb_reviews r
     set reply_body = v_reply,
         reply_at = statement_timestamp()
   where r.id = p_review
     and exists (
       select 1
         from public.airfnb_trucks t
        where t.id = r.truck_id
          and t.owner_id = v_actor
     );

  if not found then
    raise exception using errcode = '42501', message = 'only the reviewed truck owner may reply';
  end if;
end;
$$;

create or replace function public.airfnb_reply_to_organizer_review(
  p_review uuid,
  p_reply text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := auth.uid();
  v_reply text := nullif(btrim(p_reply), '');
begin
  if v_actor is null then
    raise exception using errcode = '28000', message = 'authentication required';
  end if;
  if v_reply is null or char_length(v_reply) > 2000 then
    raise exception using errcode = '22023', message = 'reply must contain between 1 and 2000 characters';
  end if;

  update public.airfnb_organizer_reviews r
     set reply_body = v_reply,
         reply_at = statement_timestamp()
   where r.id = p_review
     and r.organizer_id = v_actor;

  if not found then
    raise exception using errcode = '42501', message = 'only the reviewed organizer may reply';
  end if;
end;
$$;

revoke execute on function public.airfnb_reply_to_truck_review(uuid, text) from public, anon;
revoke execute on function public.airfnb_reply_to_organizer_review(uuid, text) from public, anon;
grant execute on function public.airfnb_reply_to_truck_review(uuid, text) to authenticated;
grant execute on function public.airfnb_reply_to_organizer_review(uuid, text) to authenticated;

commit;
