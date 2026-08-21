-- Keep the public event brief queryable without exposing the organizer's
-- contact details or exact venue address through the Data API. RLS decides
-- which rows a caller may see; column privileges decide which fields leave
-- PostgreSQL.

revoke select on table public.airfnb_event_requests
  from public, anon, authenticated;
revoke select (
  contact_name,
  contact_email,
  contact_phone,
  address_line,
  address_id
) on table public.airfnb_event_requests from public, anon, authenticated;

grant select (
  id,
  organizer_id,
  title,
  kind,
  description,
  start_at,
  end_at,
  city,
  expected_pax,
  slots_needed,
  budget_min,
  budget_max,
  desired_categories,
  dietary_requirements,
  applications_deadline,
  power_available,
  water_available,
  notes,
  status,
  visibility,
  awarded_at,
  created_at,
  updated_at,
  discovery_mode,
  accepted_deal_types,
  min_fixed_fee,
  min_revenue_share_pct,
  recommended_slots,
  slot_breakdown,
  application_response_window_hours,
  locality,
  budget_estimate,
  budget_flexible,
  catering_type,
  desired_cuisines,
  setup_minutes,
  teardown_minutes,
  energy_need,
  energy_assistance,
  sanitation_level,
  extra_services,
  selection_mode,
  assistance_requested,
  water_provided,
  wc_provided
) on table public.airfnb_event_requests to anon, authenticated;

-- The service role is the only Data API role that keeps unrestricted column
-- access. It is used only by trusted server-side integrations.
grant select on table public.airfnb_event_requests to service_role;

-- Organizers still need their complete row for management and GDPR export.
-- Admin/staff callers may inspect a specific request, but a null id never
-- turns this into a bulk cross-tenant export.
create or replace function public.airfnb_private_event_requests(
  p_request_id uuid default null
)
returns setof public.airfnb_event_requests
language sql
stable
security definer
set search_path = ''
as $$
  select request_row.*
    from public.airfnb_event_requests as request_row
   where auth.uid() is not null
     and (p_request_id is null or request_row.id = p_request_id)
     and (
       request_row.organizer_id = auth.uid()
       or (
         p_request_id is not null
         and public.airfnb_is_admin()
       )
     )
$$;

revoke execute on function public.airfnb_private_event_requests(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.airfnb_private_event_requests(uuid)
  to authenticated;
