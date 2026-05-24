-- airfnb_07_rls_extras_indexes_realtime_views
-- applied at 20260524132719


-- ---------------------------------------------------------------------------
-- 1. Owner extras: see events, payments, invoices for bookings their truck is in
-- ---------------------------------------------------------------------------
create policy "airfnb_events_owner_read" on public.airfnb_events for select using (
  exists (
    select 1
      from public.airfnb_bookings b
      join public.airfnb_booking_trucks bt on bt.booking_id = b.id
      join public.airfnb_trucks t          on t.id          = bt.truck_id
     where b.event_id = airfnb_events.id
       and t.owner_id = auth.uid()
  )
);

create policy "airfnb_payments_owner_read" on public.airfnb_payments for select using (
  exists (
    select 1
      from public.airfnb_booking_trucks bt
      join public.airfnb_trucks t on t.id = bt.truck_id
     where bt.booking_id = airfnb_payments.booking_id
       and t.owner_id = auth.uid()
  )
);

create policy "airfnb_invoices_owner_read" on public.airfnb_invoices for select using (
  exists (
    select 1
      from public.airfnb_booking_trucks bt
      join public.airfnb_trucks t on t.id = bt.truck_id
     where bt.booking_id = airfnb_invoices.booking_id
       and t.owner_id = auth.uid()
  )
);

-- Owner can update booking_trucks rows for their truck (e.g. confirm setup)
create policy "airfnb_btrucks_owner_update" on public.airfnb_booking_trucks for update using (
  exists (select 1 from public.airfnb_trucks t where t.id = truck_id and t.owner_id = auth.uid())
);

-- Reviews: only the organizer that did the booking can insert
create policy "airfnb_reviews_insert_organizer" on public.airfnb_reviews for insert
  with check (
    organizer_id = auth.uid()
    and exists (select 1 from public.airfnb_bookings b
                where b.id = booking_id and b.organizer_id = auth.uid()
                  and b.status in ('completed','paid'))
  );
create policy "airfnb_reviews_owner_reply" on public.airfnb_reviews for update using (
  exists (select 1 from public.airfnb_trucks t where t.id = truck_id and t.owner_id = auth.uid())
);

-- ---------------------------------------------------------------------------
-- 2. Missing indexes (FK + frequent filters)
-- ---------------------------------------------------------------------------
create index airfnb_addresses_owner_idx           on public.airfnb_addresses(owner_id);
create index airfnb_trucks_owner_idx              on public.airfnb_trucks(owner_id);
create index airfnb_trucks_city_idx               on public.airfnb_trucks(base_city) where status='active';
create index airfnb_trucks_featured_idx           on public.airfnb_trucks(featured)  where status='active';
create index airfnb_truck_images_truck_idx        on public.airfnb_truck_images(truck_id);
create index airfnb_menu_items_truck_idx          on public.airfnb_menu_items(truck_id);
create index airfnb_truck_avail_truck_date_idx    on public.airfnb_truck_availability(truck_id, date);
create index airfnb_truck_docs_expiry_idx         on public.airfnb_truck_documents(expires_at);
create index airfnb_events_organizer_idx          on public.airfnb_events(organizer_id);
create index airfnb_events_start_idx              on public.airfnb_events(start_at);
create index airfnb_bookings_event_idx            on public.airfnb_bookings(event_id);
create index airfnb_bookings_status_idx           on public.airfnb_bookings(status);
create index airfnb_booking_trucks_truck_idx      on public.airfnb_booking_trucks(truck_id);
create index airfnb_proposals_booking_idx         on public.airfnb_proposals(booking_id);
create index airfnb_payments_booking_idx          on public.airfnb_payments(booking_id);
create index airfnb_payments_status_idx           on public.airfnb_payments(status);
create index airfnb_invoices_booking_idx          on public.airfnb_invoices(booking_id);
create index airfnb_messages_sender_idx           on public.airfnb_messages(sender_id);
create index airfnb_reviews_truck_idx             on public.airfnb_reviews(truck_id);
create index airfnb_notifications_user_unread_idx on public.airfnb_notifications(user_id) where read_at is null;

-- ---------------------------------------------------------------------------
-- 3. Realtime: messages, notifications, bookings status
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    execute 'alter publication supabase_realtime add table public.airfnb_messages';
    execute 'alter publication supabase_realtime add table public.airfnb_notifications';
    execute 'alter publication supabase_realtime add table public.airfnb_bookings';
  end if;
exception when others then
  -- already added or publication missing -> ignore
  null;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Convenience views
-- ---------------------------------------------------------------------------
create or replace view public.airfnb_v_truck_card with (security_invoker = true) as
select
  t.id, t.slug, t.name, t.tagline, t.base_city, t.capacity, t.base_price,
  t.rating_avg, t.rating_count, t.featured, t.status,
  (select url from public.airfnb_truck_images i where i.truck_id = t.id and i.is_cover order by sort_order limit 1) as cover_url,
  array(
    select c.slug from public.airfnb_truck_categories tc
    join public.airfnb_categories c on c.id = tc.category_id
    where tc.truck_id = t.id
  ) as category_slugs
from public.airfnb_trucks t
where t.status = 'active';

create or replace view public.airfnb_v_booking_full with (security_invoker = true) as
select
  b.id, b.status, b.starts_at, b.ends_at, b.pax_count, b.total_amount, b.currency,
  b.organizer_id,
  e.id   as event_id, e.title as event_title, e.kind as event_kind,
  array(
    select json_build_object('id', t.id, 'name', t.name, 'slug', t.slug, 'price', bt.agreed_price)
      from public.airfnb_booking_trucks bt
      join public.airfnb_trucks t on t.id = bt.truck_id
      where bt.booking_id = b.id
  ) as trucks
from public.airfnb_bookings b
left join public.airfnb_events e on e.id = b.event_id;

-- helper RPC: check if a truck is available for a date range
create or replace function public.airfnb_truck_is_available(p_truck uuid, p_from date, p_to date)
returns boolean language sql stable as $$
  select not exists (
    select 1 from public.airfnb_truck_availability a
    where a.truck_id = p_truck
      and a.date between p_from and p_to
      and a.status in ('booked','blocked')
  );
$$;
revoke execute on function public.airfnb_truck_is_available(uuid, date, date) from public;
grant  execute on function public.airfnb_truck_is_available(uuid, date, date) to anon, authenticated;
;
