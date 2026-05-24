-- airfnb_15_with_check_clauses_and_function_revokes_and_notif_update
-- applied at 20260524163000

-- 1. Recreate three write policies that previously lacked WITH CHECK. Without
--    it, INSERTs aren't validated by the policy expression and a client could
--    write rows it wouldn't be allowed to read back.
drop policy if exists "airfnb_truck_cat_write"  on public.airfnb_truck_categories;
create policy "airfnb_truck_cat_write" on public.airfnb_truck_categories for all
  using (exists (select 1 from public.airfnb_trucks t where t.id = truck_id and (t.owner_id = auth.uid() or public.airfnb_is_admin())))
  with check (exists (select 1 from public.airfnb_trucks t where t.id = truck_id and (t.owner_id = auth.uid() or public.airfnb_is_admin())));

drop policy if exists "airfnb_addons_write"  on public.airfnb_booking_addons;
create policy "airfnb_addons_write" on public.airfnb_booking_addons for all
  using (exists (select 1 from public.airfnb_bookings b where b.id = booking_id and (b.organizer_id = auth.uid() or public.airfnb_is_admin())))
  with check (exists (select 1 from public.airfnb_bookings b where b.id = booking_id and (b.organizer_id = auth.uid() or public.airfnb_is_admin())));

drop policy if exists "airfnb_btrucks_write"  on public.airfnb_booking_trucks;
create policy "airfnb_btrucks_write" on public.airfnb_booking_trucks for all
  using (public.airfnb_is_admin() or exists (select 1 from public.airfnb_bookings b where b.id = booking_id and b.organizer_id = auth.uid()))
  with check (public.airfnb_is_admin() or exists (select 1 from public.airfnb_bookings b where b.id = booking_id and b.organizer_id = auth.uid()));

-- 2. Revoke default public execute on security-definer expiration functions.
--    They mutate state and must only be callable by service_role and the cron
--    job that runs as superuser.
revoke execute on function public.airfnb_expire_stale_lock_fees() from public, anon, authenticated;
revoke execute on function public.airfnb_expire_stale_requests()  from public, anon, authenticated;
grant  execute on function public.airfnb_expire_stale_lock_fees() to service_role;
grant  execute on function public.airfnb_expire_stale_requests()  to service_role;

-- 3. UPDATE policy on airfnb_notifications: users may mark their OWN
--    notifications as read (the original migration only defined SELECT).
create policy "airfnb_notif_self_update" on public.airfnb_notifications for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
