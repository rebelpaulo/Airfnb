-- airfnb_06_fix_rls_and_function_security
-- applied at 20260524132230


-- ------------------------------------------------------------
-- 1. Fix function search_path (mutable -> immutable)
-- ------------------------------------------------------------
alter function public.airfnb_touch_updated_at()    set search_path = public;
alter function public.airfnb_recalc_truck_rating() set search_path = public;

-- ------------------------------------------------------------
-- 2. Lock SECURITY DEFINER functions: revoke from anon + authenticated
--    Keep service_role / trigger usage intact.
-- ------------------------------------------------------------
revoke execute on function public.airfnb_is_admin()         from anon, authenticated, public;
revoke execute on function public.airfnb_handle_new_user()  from anon, authenticated, public;

-- ------------------------------------------------------------
-- 3. Enable RLS on the 11 tables that were missing it,
--    and add sensible policies.
-- ------------------------------------------------------------

-- public lookups (read-only for anyone, admin writes)
alter table public.airfnb_categories       enable row level security;
alter table public.airfnb_blog_categories  enable row level security;
alter table public.airfnb_faqs             enable row level security;
alter table public.airfnb_blog_authors     enable row level security;
alter table public.airfnb_service_providers enable row level security;

create policy "airfnb_categories_read"        on public.airfnb_categories       for select using (true);
create policy "airfnb_categories_admin_write" on public.airfnb_categories       for all   using (public.airfnb_is_admin()) with check (public.airfnb_is_admin());

create policy "airfnb_blog_cat_read"          on public.airfnb_blog_categories  for select using (true);
create policy "airfnb_blog_cat_admin_write"   on public.airfnb_blog_categories  for all   using (public.airfnb_is_admin()) with check (public.airfnb_is_admin());

create policy "airfnb_faqs_read"              on public.airfnb_faqs             for select using (true);
create policy "airfnb_faqs_admin_write"       on public.airfnb_faqs             for all   using (public.airfnb_is_admin()) with check (public.airfnb_is_admin());

create policy "airfnb_blog_authors_read"      on public.airfnb_blog_authors     for select using (true);
create policy "airfnb_blog_authors_self"      on public.airfnb_blog_authors     for all   using (id = auth.uid() or public.airfnb_is_admin()) with check (id = auth.uid() or public.airfnb_is_admin());

create policy "airfnb_providers_read"         on public.airfnb_service_providers for select using (true);
create policy "airfnb_providers_admin_write"  on public.airfnb_service_providers for all   using (public.airfnb_is_admin()) with check (public.airfnb_is_admin());

-- many-to-many table: same read rule as parent truck
alter table public.airfnb_truck_categories enable row level security;
create policy "airfnb_truck_cat_read"  on public.airfnb_truck_categories for select using (true);
create policy "airfnb_truck_cat_write" on public.airfnb_truck_categories for all
  using (exists (select 1 from public.airfnb_trucks t where t.id = truck_id and (t.owner_id = auth.uid() or public.airfnb_is_admin())));

-- addresses: only owner
alter table public.airfnb_addresses enable row level security;
create policy "airfnb_addresses_self" on public.airfnb_addresses for all
  using (owner_id = auth.uid() or public.airfnb_is_admin())
  with check (owner_id = auth.uid() or public.airfnb_is_admin());

-- newsletter: anon can subscribe (insert), only admin reads
alter table public.airfnb_newsletter_subscribers enable row level security;
create policy "airfnb_newsletter_insert_any" on public.airfnb_newsletter_subscribers for insert with check (true);
create policy "airfnb_newsletter_admin_read" on public.airfnb_newsletter_subscribers for select using (public.airfnb_is_admin());

-- contact form: anon can insert, only admin reads
alter table public.airfnb_contact_requests enable row level security;
create policy "airfnb_contact_insert_any"   on public.airfnb_contact_requests for insert with check (true);
create policy "airfnb_contact_admin_read"   on public.airfnb_contact_requests for select using (public.airfnb_is_admin());

-- audit log: admin-only
alter table public.airfnb_audit_log enable row level security;
create policy "airfnb_audit_admin_read"     on public.airfnb_audit_log for select using (public.airfnb_is_admin());

-- booking addons: linked to a booking; same rule as bookings
alter table public.airfnb_booking_addons enable row level security;
create policy "airfnb_addons_read"  on public.airfnb_booking_addons for select using (
  exists (
    select 1 from public.airfnb_bookings b
    where b.id = booking_id
      and (b.organizer_id = auth.uid() or public.airfnb_is_admin())
  )
);
create policy "airfnb_addons_write" on public.airfnb_booking_addons for all using (
  exists (
    select 1 from public.airfnb_bookings b
    where b.id = booking_id
      and (b.organizer_id = auth.uid() or public.airfnb_is_admin())
  )
);

-- ------------------------------------------------------------
-- 4. Add missing policies on the 8 tables with RLS but no policies
-- ------------------------------------------------------------

-- events: own organizer / admin
create policy "airfnb_events_self"   on public.airfnb_events   for all using (organizer_id = auth.uid() or public.airfnb_is_admin()) with check (organizer_id = auth.uid() or public.airfnb_is_admin());

-- booking_trucks: organizer of the booking OR owner of the truck OR admin
create policy "airfnb_btrucks_read" on public.airfnb_booking_trucks for select using (
  exists (select 1 from public.airfnb_bookings b where b.id = booking_id and b.organizer_id = auth.uid())
  or exists (select 1 from public.airfnb_trucks   t where t.id = truck_id   and t.owner_id    = auth.uid())
  or public.airfnb_is_admin()
);
create policy "airfnb_btrucks_write" on public.airfnb_booking_trucks for all using (
  public.airfnb_is_admin()
  or exists (select 1 from public.airfnb_bookings b where b.id = booking_id and b.organizer_id = auth.uid())
);

-- proposals: organizer of the booking OR admin/staff who prepared
create policy "airfnb_proposals_read" on public.airfnb_proposals for select using (
  public.airfnb_is_admin()
  or exists (select 1 from public.airfnb_bookings b where b.id = booking_id and b.organizer_id = auth.uid())
);
create policy "airfnb_proposals_write" on public.airfnb_proposals for all using (public.airfnb_is_admin()) with check (public.airfnb_is_admin());

-- payments: organizer of booking can read; admin manages
create policy "airfnb_payments_read"  on public.airfnb_payments  for select using (
  public.airfnb_is_admin()
  or exists (select 1 from public.airfnb_bookings b where b.id = booking_id and b.organizer_id = auth.uid())
);
create policy "airfnb_payments_write" on public.airfnb_payments  for all using (public.airfnb_is_admin()) with check (public.airfnb_is_admin());

-- invoices: same as payments
create policy "airfnb_invoices_read"  on public.airfnb_invoices  for select using (
  public.airfnb_is_admin()
  or exists (select 1 from public.airfnb_bookings b where b.id = booking_id and b.organizer_id = auth.uid())
);
create policy "airfnb_invoices_write" on public.airfnb_invoices  for all using (public.airfnb_is_admin()) with check (public.airfnb_is_admin());

-- conversations: any participant can read
create policy "airfnb_convs_read" on public.airfnb_conversations for select using (
  public.airfnb_is_admin()
  or exists (select 1 from public.airfnb_conversation_participants cp
             where cp.conversation_id = id and cp.user_id = auth.uid())
);
create policy "airfnb_convs_admin_write" on public.airfnb_conversations for all using (public.airfnb_is_admin()) with check (public.airfnb_is_admin());

-- conversation_participants: only the participants can see
create policy "airfnb_cp_self" on public.airfnb_conversation_participants for all using (
  user_id = auth.uid() or public.airfnb_is_admin()
) with check (user_id = auth.uid() or public.airfnb_is_admin());

-- messages: participants of the conversation
create policy "airfnb_msg_read"  on public.airfnb_messages for select using (
  exists (select 1 from public.airfnb_conversation_participants cp
          where cp.conversation_id = conversation_id and cp.user_id = auth.uid())
  or public.airfnb_is_admin()
);
create policy "airfnb_msg_send"  on public.airfnb_messages for insert with check (
  sender_id = auth.uid() and exists (
    select 1 from public.airfnb_conversation_participants cp
    where cp.conversation_id = conversation_id and cp.user_id = auth.uid()
  )
);
;
