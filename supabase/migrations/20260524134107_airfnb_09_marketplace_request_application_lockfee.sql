-- airfnb_09_marketplace_request_application_lockfee
-- applied at 20260524134107


-- =========================================================================
-- New enums for marketplace model
-- =========================================================================
create type public.airfnb_request_status as enum
  ('draft','open','reviewing','awarded','closed','expired','cancelled');

create type public.airfnb_application_status as enum
  ('submitted','shortlisted','accepted','rejected','withdrawn','expired');

create type public.airfnb_lock_fee_status as enum
  ('pending','paid','expired','refunded','waived');

create type public.airfnb_payment_direction as enum
  ('organizer_to_platform','truck_to_platform','platform_to_truck');

create type public.airfnb_payment_kind as enum
  ('lock_fee','event_payment','payout','refund');

-- add 'pending_lock_fee' to the bookings enum (cannot reference it in this same migration)
alter type public.airfnb_booking_status add value if not exists 'pending_lock_fee' before 'confirmed';

-- =========================================================================
-- New tables
-- =========================================================================

create table public.airfnb_event_requests (
  id                    uuid primary key default gen_random_uuid(),
  organizer_id          uuid not null references public.airfnb_profiles(id) on delete cascade,
  title                 text not null,
  kind                  airfnb_event_kind,
  description           text,
  start_at              timestamptz not null,
  end_at                timestamptz,
  city                  text,
  address_id            uuid references public.airfnb_addresses(id),
  expected_pax          int  not null check (expected_pax > 0),
  slots_needed          int  default 1 check (slots_needed between 1 and 10),
  budget_min            numeric(10,2),
  budget_max            numeric(10,2),
  desired_categories    int[]                  default '{}',
  dietary_requirements  airfnb_dietary_tag[]   default '{}',
  applications_deadline timestamptz,
  power_available       boolean default false,
  water_available       boolean default false,
  notes                 text,
  status                airfnb_request_status default 'open',
  visibility            text default 'public' check (visibility in ('public','invite_only')),
  awarded_at            timestamptz,
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
);

create table public.airfnb_applications (
  id                  uuid primary key default gen_random_uuid(),
  request_id          uuid not null references public.airfnb_event_requests(id) on delete cascade,
  truck_id            uuid not null references public.airfnb_trucks(id) on delete cascade,
  proposed_price      numeric(10,2) not null check (proposed_price >= 0),
  cover_message       text,
  menu_pitch          jsonb,
  estimated_servings  int,
  available_confirmed boolean default true,
  status              airfnb_application_status default 'submitted',
  shortlisted_at      timestamptz,
  decided_at          timestamptz,
  withdrawn_at        timestamptz,
  created_at          timestamptz default now(),
  updated_at          timestamptz default now(),
  unique (request_id, truck_id)
);

create table public.airfnb_lock_fees (
  id              uuid primary key default gen_random_uuid(),
  application_id  uuid not null unique references public.airfnb_applications(id) on delete cascade,
  amount          numeric(10,2) not null check (amount >= 0),
  currency        char(3) default 'EUR',
  due_until       timestamptz not null,
  status          airfnb_lock_fee_status default 'pending',
  paid_at         timestamptz,
  provider_ref    text,
  refunded_at     timestamptz,
  created_at      timestamptz default now()
);

create table public.airfnb_request_invitations (
  request_id  uuid references public.airfnb_event_requests(id) on delete cascade,
  truck_id    uuid references public.airfnb_trucks(id)         on delete cascade,
  invited_by  uuid references public.airfnb_profiles(id),
  invited_at  timestamptz default now(),
  responded   boolean     default false,
  primary key (request_id, truck_id)
);

create table public.airfnb_truck_alert_prefs (
  truck_id        uuid primary key references public.airfnb_trucks(id) on delete cascade,
  cities          text[]  default '{}',
  category_ids    int[]   default '{}',
  min_budget      numeric(10,2),
  max_radius_km   int,
  channels        jsonb   default '{"email":true,"push":false}'::jsonb,
  updated_at      timestamptz default now()
);

-- =========================================================================
-- Modifications to existing tables
-- =========================================================================

alter table public.airfnb_bookings
  add column application_id uuid references public.airfnb_applications(id);

alter table public.airfnb_payments
  add column direction airfnb_payment_direction,
  add column kind      airfnb_payment_kind default 'event_payment';

alter table public.airfnb_conversations
  add column application_id uuid references public.airfnb_applications(id);

alter table public.airfnb_trucks
  add column lead_response_rate numeric(3,2),
  add column last_active_at     timestamptz,
  add column subscription_tier  text default 'basic';

-- =========================================================================
-- Indexes
-- =========================================================================
create index airfnb_req_status_idx        on public.airfnb_event_requests(status) where status in ('open','reviewing');
create index airfnb_req_organizer_idx     on public.airfnb_event_requests(organizer_id);
create index airfnb_req_city_start_idx    on public.airfnb_event_requests(city, start_at) where status = 'open';
create index airfnb_req_categories_gin    on public.airfnb_event_requests using gin (desired_categories);
create index airfnb_req_dietary_gin       on public.airfnb_event_requests using gin (dietary_requirements);
create index airfnb_req_deadline_idx      on public.airfnb_event_requests(applications_deadline) where status = 'open';

create index airfnb_app_request_idx       on public.airfnb_applications(request_id, status);
create index airfnb_app_truck_idx         on public.airfnb_applications(truck_id, status);
create index airfnb_app_pending_idx       on public.airfnb_applications(status) where status in ('submitted','shortlisted');

create index airfnb_lockfee_status_idx    on public.airfnb_lock_fees(status, due_until) where status = 'pending';

create index airfnb_invites_truck_idx     on public.airfnb_request_invitations(truck_id, responded);

create index airfnb_bookings_app_idx      on public.airfnb_bookings(application_id);
create index airfnb_payments_kind_idx     on public.airfnb_payments(kind, status);

-- =========================================================================
-- RLS — enable
-- =========================================================================
alter table public.airfnb_event_requests       enable row level security;
alter table public.airfnb_applications         enable row level security;
alter table public.airfnb_lock_fees            enable row level security;
alter table public.airfnb_request_invitations  enable row level security;
alter table public.airfnb_truck_alert_prefs    enable row level security;

-- ----- event_requests --------------------------------------------------
create policy "airfnb_req_public_read" on public.airfnb_event_requests for select using (
  (visibility = 'public' and status in ('open','reviewing','awarded'))
  or organizer_id = auth.uid()
  or public.airfnb_is_admin()
  or exists (
    select 1 from public.airfnb_request_invitations ri
    join public.airfnb_trucks t on t.id = ri.truck_id
    where ri.request_id = airfnb_event_requests.id and t.owner_id = auth.uid()
  )
);
create policy "airfnb_req_insert" on public.airfnb_event_requests for insert
  with check (organizer_id = auth.uid());
create policy "airfnb_req_update" on public.airfnb_event_requests for update
  using (organizer_id = auth.uid() or public.airfnb_is_admin());
create policy "airfnb_req_delete" on public.airfnb_event_requests for delete
  using (organizer_id = auth.uid() or public.airfnb_is_admin());

-- ----- applications ----------------------------------------------------
create policy "airfnb_app_read" on public.airfnb_applications for select using (
  public.airfnb_is_admin()
  or exists (select 1 from public.airfnb_trucks t          where t.id = truck_id   and t.owner_id = auth.uid())
  or exists (select 1 from public.airfnb_event_requests r  where r.id = request_id and r.organizer_id = auth.uid())
);
create policy "airfnb_app_insert" on public.airfnb_applications for insert with check (
  exists (select 1 from public.airfnb_trucks t where t.id = truck_id and t.owner_id = auth.uid())
  and exists (select 1 from public.airfnb_event_requests r where r.id = request_id and r.status = 'open'
              and (r.applications_deadline is null or r.applications_deadline > now()))
);
create policy "airfnb_app_truck_update" on public.airfnb_applications for update using (
  -- truck can withdraw
  exists (select 1 from public.airfnb_trucks t where t.id = truck_id and t.owner_id = auth.uid())
);
create policy "airfnb_app_organizer_update" on public.airfnb_applications for update using (
  -- organizer can shortlist/accept/reject
  exists (select 1 from public.airfnb_event_requests r where r.id = request_id and r.organizer_id = auth.uid())
);

-- ----- lock_fees -------------------------------------------------------
create policy "airfnb_lockfee_read" on public.airfnb_lock_fees for select using (
  public.airfnb_is_admin()
  or exists (
    select 1 from public.airfnb_applications a
    join public.airfnb_trucks t on t.id = a.truck_id
    where a.id = application_id and t.owner_id = auth.uid()
  )
  or exists (
    select 1 from public.airfnb_applications a
    join public.airfnb_event_requests r on r.id = a.request_id
    where a.id = application_id and r.organizer_id = auth.uid()
  )
);
-- writes only via service_role (no policies for anon/authenticated insert/update)

-- ----- request_invitations --------------------------------------------
create policy "airfnb_inv_read" on public.airfnb_request_invitations for select using (
  public.airfnb_is_admin()
  or exists (select 1 from public.airfnb_trucks t          where t.id = truck_id   and t.owner_id = auth.uid())
  or exists (select 1 from public.airfnb_event_requests r  where r.id = request_id and r.organizer_id = auth.uid())
);
create policy "airfnb_inv_insert" on public.airfnb_request_invitations for insert with check (
  exists (select 1 from public.airfnb_event_requests r where r.id = request_id and r.organizer_id = auth.uid())
);
create policy "airfnb_inv_update" on public.airfnb_request_invitations for update using (
  exists (select 1 from public.airfnb_trucks t where t.id = truck_id and t.owner_id = auth.uid())
);

-- ----- truck_alert_prefs ----------------------------------------------
create policy "airfnb_alerts_self" on public.airfnb_truck_alert_prefs for all using (
  exists (select 1 from public.airfnb_trucks t where t.id = truck_id and t.owner_id = auth.uid())
  or public.airfnb_is_admin()
) with check (
  exists (select 1 from public.airfnb_trucks t where t.id = truck_id and t.owner_id = auth.uid())
  or public.airfnb_is_admin()
);

-- =========================================================================
-- Touch triggers (updated_at)
-- =========================================================================
create trigger airfnb_trg_req_touch before update on public.airfnb_event_requests
  for each row execute function public.airfnb_touch_updated_at();
create trigger airfnb_trg_app_touch before update on public.airfnb_applications
  for each row execute function public.airfnb_touch_updated_at();

-- =========================================================================
-- Realtime: trucks need live updates on requests + their applications
-- =========================================================================
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin execute 'alter publication supabase_realtime add table public.airfnb_event_requests'; exception when others then null; end;
    begin execute 'alter publication supabase_realtime add table public.airfnb_applications';   exception when others then null; end;
    begin execute 'alter publication supabase_realtime add table public.airfnb_lock_fees';      exception when others then null; end;
  end if;
end $$;
;
