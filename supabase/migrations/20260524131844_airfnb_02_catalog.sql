-- airfnb_02_catalog
-- applied at 20260524131844


create type airfnb_truck_status as enum ('draft','pending_review','active','paused','archived');
create type airfnb_dietary_tag as enum ('vegan','vegetarian','gluten_free','lactose_free','nut_free','halal','kosher','spicy');

create table public.airfnb_categories (
  id       serial primary key,
  slug     text unique not null,
  name_pt  text not null,
  name_en  text,
  icon     text
);

create table public.airfnb_trucks (
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid not null references public.airfnb_profiles(id) on delete cascade,
  slug               text unique not null,
  name               text not null,
  tagline            text,
  description        text,
  base_city          text,
  service_radius_km  int default 50,
  capacity           int,
  min_event_pax      int default 30,
  max_event_pax      int default 500,
  base_price         numeric(10,2),
  price_per_pax      numeric(10,2),
  setup_minutes      int default 60,
  power_required_kw  numeric(4,1),
  needs_water        boolean default false,
  dimensions_m       numeric(4,1)[],
  status             airfnb_truck_status default 'draft',
  rating_avg         numeric(2,1) default 0,
  rating_count       int default 0,
  featured           boolean default false,
  homologation_expires_at date,
  insurance_expires_at    date,
  created_at         timestamptz default now(),
  updated_at         timestamptz default now()
);
create index airfnb_trucks_search on public.airfnb_trucks using gin (
  to_tsvector('portuguese', coalesce(name,'') || ' ' || coalesce(description,''))
);
create index airfnb_trucks_active_idx on public.airfnb_trucks (status) where status='active';

create table public.airfnb_truck_categories (
  truck_id     uuid references public.airfnb_trucks(id) on delete cascade,
  category_id  int  references public.airfnb_categories(id) on delete cascade,
  primary key (truck_id, category_id)
);

create table public.airfnb_truck_images (
  id          uuid primary key default gen_random_uuid(),
  truck_id    uuid references public.airfnb_trucks(id) on delete cascade,
  url         text not null,
  alt         text,
  sort_order  int default 0,
  is_cover    boolean default false
);

create table public.airfnb_menu_items (
  id          uuid primary key default gen_random_uuid(),
  truck_id    uuid references public.airfnb_trucks(id) on delete cascade,
  name        text not null,
  description text,
  price       numeric(8,2),
  image_url   text,
  category    text,
  tags        airfnb_dietary_tag[] default '{}',
  sort_order  int default 0
);

create table public.airfnb_truck_availability (
  id          uuid primary key default gen_random_uuid(),
  truck_id    uuid references public.airfnb_trucks(id) on delete cascade,
  date        date not null,
  status      text check (status in ('blocked','tentative','booked')),
  booking_id  uuid,
  unique (truck_id, date)
);

create table public.airfnb_truck_documents (
  id          uuid primary key default gen_random_uuid(),
  truck_id    uuid references public.airfnb_trucks(id) on delete cascade,
  kind        text,
  url         text,
  issued_at   date,
  expires_at  date
);
;
