-- Audit fix: airfnb_self_delete was incomplete for truck-owner accounts.
--
-- Two problems with the previous version:
--   1. It didn't touch airfnb_trucks at all. Trucks owned by the deleting
--      user would CASCADE via owner_id, but for trucks with booking_trucks
--      rows (Portuguese tax retention requires those to survive 10 yrs) the
--      cascade would FAIL on the airfnb_booking_trucks → airfnb_trucks FK
--      (NO ACTION). So self-delete threw an FK violation for any owner
--      who had ever booked a job.
--   2. Several audit-trail FK columns (proposals.prepared_by,
--      contact_requests.handled_by, request_invitations.invited_by) were
--      NO ACTION and never nulled, so the profile delete also failed for
--      any user whose UUID appeared in those columns.
--
-- Fix:
--   a) Make airfnb_trucks.owner_id NULLABLE and switch its FK from CASCADE
--      to SET NULL. Cascading was wrong anyway — we want to preserve the
--      truck row when it has bookings, just orphan it.
--   b) In airfnb_self_delete: for each truck owned by the user,
--        - if it has any booking_trucks history → anonymize in place
--          (name/description/base_city blanked, status='archived',
--           owner_id set null by FK behavior after profile delete)
--        - else → delete the truck explicitly (children CASCADE)
--   c) Null out the remaining audit-trail FKs before profile delete.
--   d) lock_fees + payments still survive (no change to their schema)
--      because they reference applications → bookings, not the profile
--      directly, and we preserve bookings/booking_trucks.

-- (a) Loosen the trucks FK so SET NULL becomes possible.
alter table public.airfnb_trucks
  alter column owner_id drop not null;

alter table public.airfnb_trucks
  drop constraint if exists airfnb_trucks_owner_id_fkey;

alter table public.airfnb_trucks
  add constraint airfnb_trucks_owner_id_fkey
  foreign key (owner_id) references public.airfnb_profiles(id)
  on delete set null;

-- (b)+(c) Rewrite airfnb_self_delete.
create or replace function public.airfnb_self_delete()
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_truck record;
  v_has_bookings boolean;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  -- Anonymize the profile's PII first (so the row that remains in audit
  -- trail references is no longer personally identifiable).
  update public.airfnb_profiles set
    full_name    = null,
    display_name = null,
    phone        = null,
    vat_number   = null,
    avatar_url   = null
  where id = v_uid;

  -- Trucks the user owns: anonymize-or-delete depending on booking history.
  for v_truck in
    select id from public.airfnb_trucks where owner_id = v_uid
  loop
    select exists (
      select 1 from public.airfnb_booking_trucks bt where bt.truck_id = v_truck.id
    ) into v_has_bookings;

    if v_has_bookings then
      -- Preserve the truck row for tax retention; redact identifying fields.
      update public.airfnb_trucks set
        name        = '[Truck removido]',
        slug        = 'removed-' || id::text,
        description = null,
        base_city   = null,
        status      = 'archived'
      where id = v_truck.id;
    else
      -- No bookings → safe to delete; children CASCADE.
      delete from public.airfnb_trucks where id = v_truck.id;
    end if;
  end loop;

  -- Audit-trail columns that would otherwise block the profile delete (NO ACTION FKs).
  update public.airfnb_bookings           set organizer_id = null where organizer_id = v_uid;
  update public.airfnb_messages           set sender_id    = null where sender_id    = v_uid;
  update public.airfnb_reviews            set organizer_id = null where organizer_id = v_uid;
  update public.airfnb_proposals          set prepared_by  = null where prepared_by  = v_uid;
  update public.airfnb_contact_requests   set handled_by   = null where handled_by   = v_uid;
  update public.airfnb_request_invitations set invited_by  = null where invited_by   = v_uid;

  -- Caller-owned data that doesn't need to survive.
  delete from public.airfnb_organizer_reviews         where organizer_id = v_uid;
  delete from public.airfnb_event_requests            where organizer_id = v_uid;
  delete from public.airfnb_events                    where organizer_id = v_uid;
  delete from public.airfnb_conversation_participants where user_id      = v_uid;
  delete from public.airfnb_notifications             where user_id      = v_uid;
  delete from public.airfnb_favorites                 where user_id      = v_uid;

  -- Finally, the profile. Remaining FKs are now either SET NULL or already
  -- nulled out above. Anonymized trucks will have owner_id auto-set to null.
  delete from public.airfnb_profiles where id = v_uid;
end $function$;
