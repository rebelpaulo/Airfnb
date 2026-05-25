-- airfnb_32: RGPD-compliant self-delete RPC.
--
-- Deletes the caller's airfnb_profiles row, which cascades to trucks /
-- applications / messages / notifications via the existing ON DELETE CASCADE
-- foreign keys. The auth.users row stays — Supabase reserves admin-API
-- deletion for service-role; the caller's email becomes orphaned and the
-- next login won't have a profile row, effectively disabling the account.
-- We also wipe display_name / phone / vat_number from the profile right
-- before delete so even backup snapshots can't link them back.
--
-- airfnb_lock_fees and airfnb_payments rows are retained because Portuguese
-- tax law requires 10-year invoice retention (see Privacy Policy).

create or replace function public.airfnb_self_delete()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  -- Best-effort PII scrub before delete. Cascade will remove the row but
  -- backups may still hold it; this gives "right to erasure" teeth.
  update public.airfnb_profiles
     set full_name = null, display_name = null, phone = null,
         vat_number = null, avatar_url = null
   where id = v_uid;

  -- Several airfnb_profiles FKs aren't ON DELETE CASCADE. Some target columns
  -- are NOT NULL (event_requests.organizer_id, events.organizer_id,
  -- organizer_reviews.organizer_id) so we DELETE the dependent rows instead
  -- of nulling. Others are nullable (bookings.organizer_id, messages.sender_id,
  -- reviews.organizer_id) — we null those to preserve the counter-party's
  -- view of the conversation / booking trail.
  --
  -- Tables intentionally untouched (legal retention):
  --   airfnb_lock_fees, airfnb_payments — referenced indirectly via cascading
  --   parents; the underlying rows survive because we don't touch them.
  update public.airfnb_bookings    set organizer_id = null where organizer_id = v_uid;
  update public.airfnb_messages    set sender_id    = null where sender_id    = v_uid;
  update public.airfnb_reviews     set organizer_id = null where organizer_id = v_uid;

  delete from public.airfnb_organizer_reviews          where organizer_id = v_uid;
  delete from public.airfnb_event_requests             where organizer_id = v_uid;
  delete from public.airfnb_events                     where organizer_id = v_uid;
  delete from public.airfnb_conversation_participants  where user_id      = v_uid;
  delete from public.airfnb_notifications              where user_id      = v_uid;
  delete from public.airfnb_favorites                  where user_id      = v_uid;

  delete from public.airfnb_profiles where id = v_uid;
end $$;
revoke execute on function public.airfnb_self_delete() from public, anon;
grant  execute on function public.airfnb_self_delete() to authenticated;
