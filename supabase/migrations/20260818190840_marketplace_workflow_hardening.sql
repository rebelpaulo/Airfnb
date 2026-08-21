-- Harden the marketplace workflow at the database boundary.
--
-- Authenticated clients keep the one direct write the current product needs:
-- submitting a new application. Decisions and booking creation remain behind
-- the existing SECURITY DEFINER RPCs; payment state remains service-role only.

begin;

-- ---------------------------------------------------------------------------
-- Applications: validate direct submission and remove broad UPDATE access.
-- ---------------------------------------------------------------------------

drop policy if exists airfnb_app_insert on public.airfnb_applications;
create policy airfnb_app_insert
  on public.airfnb_applications
  for insert
  to authenticated
  with check (
    status = 'submitted'::public.airfnb_application_status
    and shortlisted_at is null
    and decided_at is null
    and withdrawn_at is null
    and exists (
      select 1
        from public.airfnb_trucks t
       where t.id = airfnb_applications.truck_id
         and t.owner_id = auth.uid()
         and t.status = 'active'::public.airfnb_truck_status
    )
    and exists (
      select 1
        from public.airfnb_event_requests r
       where r.id = airfnb_applications.request_id
         and r.status = 'open'::public.airfnb_request_status
         and r.start_at > now()
         and (
           r.applications_deadline is null
           or r.applications_deadline > now()
         )
         and (
           r.visibility = 'public'
           or exists (
             select 1
               from public.airfnb_request_invitations ri
              where ri.request_id = r.id
                and ri.truck_id = airfnb_applications.truck_id
           )
         )
    )
  );

-- Application identity, commercial terms and status transitions are immutable
-- to direct authenticated-table writes. The decision RPCs below run as their
-- owner, perform their own authorization checks and therefore remain usable.
drop policy if exists airfnb_app_truck_update on public.airfnb_applications;
drop policy if exists airfnb_app_organizer_update on public.airfnb_applications;

revoke insert, update, delete on table public.airfnb_applications from anon;
revoke update, delete on table public.airfnb_applications from authenticated;
grant select, insert on table public.airfnb_applications to authenticated;
grant select, insert, update, delete on table public.airfnb_applications to service_role;

-- ---------------------------------------------------------------------------
-- Bookings: creation and every state change are trusted-server operations.
-- ---------------------------------------------------------------------------

drop policy if exists airfnb_bookings_insert on public.airfnb_bookings;
drop policy if exists airfnb_bookings_update on public.airfnb_bookings;

revoke insert, update, delete on table public.airfnb_bookings from anon, authenticated;
grant select on table public.airfnb_bookings to authenticated;
grant select, insert, update, delete on table public.airfnb_bookings to service_role;

-- ---------------------------------------------------------------------------
-- Booking/truck terms: no direct client mutation of either side of the primary
-- key or the agreed price. airfnb_accept_application creates the row atomically.
-- ---------------------------------------------------------------------------

drop policy if exists airfnb_btrucks_write on public.airfnb_booking_trucks;
drop policy if exists airfnb_btrucks_owner_update on public.airfnb_booking_trucks;

revoke insert, update, delete on table public.airfnb_booking_trucks from anon, authenticated;
grant select on table public.airfnb_booking_trucks to authenticated;
grant select, insert, update, delete on table public.airfnb_booking_trucks to service_role;

-- ---------------------------------------------------------------------------
-- Preserve and tighten the organizer decision workflow used by the application.
-- Both functions lock the application before checking state. Shortlisting is
-- limited to active request review; rejection also remains possible after an
-- award so organizers can close out the remaining candidates cleanly.
-- ---------------------------------------------------------------------------

create or replace function public.airfnb_shortlist_application(p_application uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  app public.airfnb_applications%rowtype;
  req public.airfnb_event_requests%rowtype;
begin
  select *
    into app
    from public.airfnb_applications
   where id = p_application
   for update;

  if app is null then
    raise exception 'application not found';
  end if;

  select *
    into req
    from public.airfnb_event_requests
   where id = app.request_id;

  if req is null then
    raise exception 'request not found';
  end if;

  if auth.uid() is null
     or (auth.uid() <> req.organizer_id and not public.airfnb_is_admin()) then
    raise exception 'not authorized';
  end if;

  if req.status not in (
    'open'::public.airfnb_request_status,
    'reviewing'::public.airfnb_request_status
  ) then
    raise exception 'request is not reviewing applications (status=%)', req.status;
  end if;

  if app.status <> 'submitted'::public.airfnb_application_status then
    raise exception 'application cannot be shortlisted (status=%)', app.status;
  end if;

  update public.airfnb_applications
     set status = 'shortlisted'::public.airfnb_application_status,
         shortlisted_at = now()
   where id = app.id;

  insert into public.airfnb_notifications (user_id, kind, payload)
    select t.owner_id,
           'application.shortlisted',
           jsonb_build_object(
             'application_id', app.id,
             'request_id', req.id,
             'request_title', req.title
           )
      from public.airfnb_trucks t
     where t.id = app.truck_id;
end
$function$;

create or replace function public.airfnb_reject_application(
  p_application uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  app public.airfnb_applications%rowtype;
  req public.airfnb_event_requests%rowtype;
begin
  select *
    into app
    from public.airfnb_applications
   where id = p_application
   for update;

  if app is null then
    raise exception 'application not found';
  end if;

  select *
    into req
    from public.airfnb_event_requests
   where id = app.request_id;

  if req is null then
    raise exception 'request not found';
  end if;

  if auth.uid() is null
     or (auth.uid() <> req.organizer_id and not public.airfnb_is_admin()) then
    raise exception 'not authorized';
  end if;

  if req.status not in (
    'open'::public.airfnb_request_status,
    'reviewing'::public.airfnb_request_status,
    'awarded'::public.airfnb_request_status
  ) then
    raise exception 'request cannot reject applications (status=%)', req.status;
  end if;

  if app.status not in (
    'submitted'::public.airfnb_application_status,
    'shortlisted'::public.airfnb_application_status
  ) then
    raise exception 'application cannot be rejected (status=%)', app.status;
  end if;

  update public.airfnb_applications
     set status = 'rejected'::public.airfnb_application_status,
         decided_at = now()
   where id = app.id;

  insert into public.airfnb_notifications (user_id, kind, payload)
    select t.owner_id,
           'application.rejected',
           jsonb_build_object(
             'application_id', app.id,
             'request_id', req.id,
             'reason', p_reason
           )
      from public.airfnb_trucks t
     where t.id = app.truck_id;
end
$function$;

-- Exact function ACLs: anonymous clients cannot invoke decisions; ordinary
-- organizers can, and the service role retains operational/recovery access.
revoke execute on function public.airfnb_shortlist_application(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.airfnb_shortlist_application(uuid)
  to authenticated, service_role;

revoke execute on function public.airfnb_reject_application(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.airfnb_reject_application(uuid, text)
  to authenticated, service_role;

revoke execute on function public.airfnb_accept_application(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.airfnb_accept_application(uuid)
  to authenticated, service_role;

commit;
