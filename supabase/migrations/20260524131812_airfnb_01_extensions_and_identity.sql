-- airfnb_01_extensions_and_identity
-- applied at 20260524131812


create extension if not exists "pg_trgm";
create extension if not exists "unaccent";
create extension if not exists "postgis";

create type airfnb_user_role as enum ('organizer','owner','admin','staff');

create table public.airfnb_profiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  role             airfnb_user_role not null default 'organizer',
  full_name        text,
  display_name     text,
  phone            text,
  avatar_url       text,
  locale           text default 'pt-PT',
  vat_number       text,
  company_name     text,
  marketing_opt_in boolean default false,
  created_at       timestamptz default now(),
  updated_at       timestamptz default now()
);

create table public.airfnb_addresses (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid references public.airfnb_profiles(id) on delete cascade,
  label       text,
  line1       text not null,
  line2       text,
  postal_code text,
  city        text,
  region      text,
  country     text default 'PT',
  geom        geography(point, 4326),
  created_at  timestamptz default now()
);
create index airfnb_addresses_geom_idx on public.airfnb_addresses using gist (geom);
;
