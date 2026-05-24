-- airfnb_03_bookings_payments
-- applied at 20260524131908


create type airfnb_event_kind as enum ('wedding','birthday','corporate','festival','conference','private','other');
create type airfnb_booking_status as enum ('inquiry','proposal_sent','accepted','confirmed','paid','in_progress','completed','cancelled','refunded');
create type airfnb_payment_status as enum ('pending','paid','failed','refunded');
create type airfnb_payment_method as enum ('stripe','mbway','multibanco','manual');

create table public.airfnb_events (
  id              uuid primary key default gen_random_uuid(),
  organizer_id    uuid not null references public.airfnb_profiles(id) on delete cascade,
  title           text,
  kind            airfnb_event_kind,
  start_at        timestamptz,
  end_at          timestamptz,
  expected_pax    int,
  city            text,
  address_id      uuid references public.airfnb_addresses(id),
  budget_min      numeric(10,2),
  budget_max      numeric(10,2),
  notes           text,
  status          text default 'draft',
  created_at      timestamptz default now()
);

create table public.airfnb_bookings (
  id                  uuid primary key default gen_random_uuid(),
  event_id            uuid references public.airfnb_events(id) on delete cascade,
  organizer_id        uuid references public.airfnb_profiles(id),
  status              airfnb_booking_status default 'inquiry',
  starts_at           timestamptz,
  ends_at             timestamptz,
  pax_count           int,
  total_amount        numeric(10,2),
  currency            char(3) default 'EUR',
  notes               text,
  cancellation_reason text,
  created_at          timestamptz default now(),
  updated_at          timestamptz default now()
);
create index airfnb_bookings_organizer_idx on public.airfnb_bookings(organizer_id);

create table public.airfnb_booking_trucks (
  booking_id    uuid references public.airfnb_bookings(id) on delete cascade,
  truck_id      uuid references public.airfnb_trucks(id),
  agreed_price  numeric(10,2),
  notes         text,
  primary key (booking_id, truck_id)
);

create table public.airfnb_proposals (
  id            uuid primary key default gen_random_uuid(),
  booking_id    uuid references public.airfnb_bookings(id) on delete cascade,
  prepared_by   uuid references public.airfnb_profiles(id),
  version       int default 1,
  body          jsonb,
  total_amount  numeric(10,2),
  valid_until   date,
  pdf_url       text,
  signed_at     timestamptz,
  created_at    timestamptz default now()
);

create table public.airfnb_payments (
  id           uuid primary key default gen_random_uuid(),
  booking_id   uuid references public.airfnb_bookings(id) on delete cascade,
  amount       numeric(10,2),
  currency     char(3) default 'EUR',
  method       airfnb_payment_method,
  status       airfnb_payment_status default 'pending',
  provider_ref text,
  paid_at      timestamptz,
  created_at   timestamptz default now()
);

create table public.airfnb_invoices (
  id           uuid primary key default gen_random_uuid(),
  booking_id   uuid references public.airfnb_bookings(id),
  number       text unique,
  issued_at    date,
  pdf_url      text,
  vat_amount   numeric(10,2),
  total_amount numeric(10,2)
);
;
