-- When an organizer ticks "Preciso de ajuda especializada" in the wizard,
-- the request lands with assistance_requested=true. Nothing fans the
-- signal out today — admins only find out by manually inspecting the
-- requests table. Add an AFTER INSERT trigger that drops a notification
-- into every admin/staff inbox so the assist queue can light up the
-- bell in real time.
--
-- One row per admin (the airfnb_notifications inbox is per-user). Skip
-- silently if there are no admin/staff users — operational deployment
-- always has at least one, but the migration shouldn't fail on a fresh
-- local clone before paulosilva@newsheet.pt is seeded.

create or replace function public.airfnb_event_request_notify_admins()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.assistance_requested = true then
    insert into public.airfnb_notifications (user_id, kind, payload)
      select id, 'request.assistance_requested', jsonb_build_object(
        'request_id',    new.id,
        'request_title', new.title,
        'organizer_id',  new.organizer_id,
        'city',          new.city,
        'expected_pax',  new.expected_pax,
        'start_at',      new.start_at
      )
        from public.airfnb_profiles
       where role in ('admin', 'staff');
  end if;
  return new;
end $$;

drop trigger if exists airfnb_event_request_notify_admins_trg on public.airfnb_event_requests;
create trigger airfnb_event_request_notify_admins_trg
  after insert on public.airfnb_event_requests
  for each row execute function public.airfnb_event_request_notify_admins();
