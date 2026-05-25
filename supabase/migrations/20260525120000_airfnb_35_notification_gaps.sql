-- Close the notification gaps in the marketplace loop:
--   1. Organizer was never notified when a truck applied to their request.
--   2. Truck owner was never notified when their application was shortlisted.
--
-- accept/reject already inserted notifications (kinds application.accepted /
-- application.rejected). This adds:
--   - application.received   → request organizer (truck just applied)
--   - application.shortlisted → truck owner   (organizer moved them to shortlist)

-- 1) AFTER INSERT trigger on airfnb_applications → notify the request organizer.
create or replace function public.airfnb_notify_application_received()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_organizer uuid;
  v_truck_name text;
begin
  select organizer_id into v_organizer
    from public.airfnb_event_requests
   where id = new.request_id;
  if v_organizer is null then return new; end if;

  select name into v_truck_name
    from public.airfnb_trucks
   where id = new.truck_id;

  insert into public.airfnb_notifications (user_id, kind, payload)
  values (
    v_organizer,
    'application.received',
    jsonb_build_object(
      'application_id', new.id,
      'request_id',     new.request_id,
      'truck_id',       new.truck_id,
      'truck_name',     v_truck_name,
      'proposed_price', new.proposed_price
    )
  );
  return new;
end $function$;

drop trigger if exists airfnb_applications_notify_received on public.airfnb_applications;
create trigger airfnb_applications_notify_received
  after insert on public.airfnb_applications
  for each row execute function public.airfnb_notify_application_received();

-- 2) Patch airfnb_shortlist_application to insert a notification for the
--    truck owner. Keep all the existing authorization + state-machine logic.
create or replace function public.airfnb_shortlist_application(p_application uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  app public.airfnb_applications%rowtype;
  req public.airfnb_event_requests%rowtype;
begin
  select * into app from public.airfnb_applications where id = p_application;
  if app is null then raise exception 'application not found'; end if;
  select * into req from public.airfnb_event_requests where id = app.request_id;
  if auth.uid() is null or (auth.uid() <> req.organizer_id and not public.airfnb_is_admin()) then
    raise exception 'not authorized';
  end if;

  update public.airfnb_applications
     set status = 'shortlisted', shortlisted_at = now()
   where id = p_application and status = 'submitted';

  -- Only notify if the UPDATE actually moved the row (avoid double-notify
  -- if someone calls shortlist twice).
  if found then
    insert into public.airfnb_notifications (user_id, kind, payload)
      select t.owner_id, 'application.shortlisted',
             jsonb_build_object(
               'application_id', app.id,
               'request_id',     req.id,
               'request_title',  req.title
             )
        from public.airfnb_trucks t
       where t.id = app.truck_id;
  end if;
end $function$;
