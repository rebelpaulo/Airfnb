-- =============================================================================
-- Air F&B — Supabase schema (PostgreSQL 15+)
-- Apply with: supabase db push   OR   paste into SQL editor
-- =============================================================================

-- Extensions ------------------------------------------------------------------
create extension if not exists "pgcrypto";       -- gen_random_uuid()
create extension if not exists "pg_trgm";        -- fuzzy text search
create extension if not exists "postgis";        -- geo / distance queries
create extension if not exists "unaccent";       -- accent-insensitive search
create extension if not exists "pg_cron";        -- scheduled reminders

-- =============================================================================
-- 1. IDENTITY & PROFILES
-- =============================================================================
create type user_role as enum ('organizer','owner','admin','staff');

create table public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  role            user_role not null default 'organizer',
  full_name       text,
  display_name    text,
  phone           text,
  avatar_url      text,
  locale          text default 'pt-PT',
  vat_number      text,                      -- NIF
  company_name    text,
  marketing_opt_in boolean default false,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);

create table public.addresses (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid references profiles(id) on delete cascade,
  label       text,                          -- "Faturação" / "Evento"
  line1       text not null,
  line2       text,
  postal_code text,
  city        text,
  region      text,
  country     text default 'PT',
  geom        geography(point, 4326),        -- for distance search
  created_at  timestamptz default now()
);

-- =============================================================================
-- 2. CATALOG — TRUCKS
-- =============================================================================
create type truck_status as enum ('draft','pending_review','active','paused','archived');

create table public.categories (
  id          serial primary key,
  slug        text unique not null,          -- "pizza","sushi","bbq"…
  name_pt     text not null,
  name_en     text,
  icon        text                           -- material symbol name
);

create table public.trucks (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references profiles(id) on delete cascade,
  slug            text unique not null,
  name            text not null,
  tagline         text,
  description     text,
  base_city       text,
  service_radius_km int default 50,
  capacity        int,                       -- pax atendíveis/hora
  min_event_pax   int default 30,
  max_event_pax   int default 500,
  base_price      numeric(10,2),             -- preço base/evento
  price_per_pax   numeric(10,2),
  setup_minutes   int default 60,
  power_required_kw numeric(4,1),
  needs_water     boolean default false,
  dimensions_m    numeric(4,1)[3],           -- {comp, larg, alt}
  status          truck_status default 'draft',
  rating_avg      numeric(2,1) default 0,    -- desnormalizado p/ ordenação
  rating_count    int default 0,
  featured        boolean default false,
  homologation_expires_at date,              -- ASAE/HACCP
  insurance_expires_at    date,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);
create index trucks_search on trucks using gin (to_tsvector('portuguese', coalesce(name,'') || ' ' || coalesce(description,'')));
create index trucks_status_idx on trucks (status) where status='active';

create table public.truck_categories (
  truck_id    uuid references trucks(id) on delete cascade,
  category_id int  references categories(id) on delete cascade,
  primary key (truck_id, category_id)
);

create table public.truck_images (
  id          uuid primary key default gen_random_uuid(),
  truck_id    uuid references trucks(id) on delete cascade,
  url         text not null,                 -- supabase storage path
  alt         text,
  sort_order  int default 0,
  is_cover    boolean default false
);

create type dietary_tag as enum ('vegan','vegetarian','gluten_free','lactose_free','nut_free','halal','kosher','spicy');

create table public.menu_items (
  id          uuid primary key default gen_random_uuid(),
  truck_id    uuid references trucks(id) on delete cascade,
  name        text not null,
  description text,
  price       numeric(8,2),
  image_url   text,
  category    text,                          -- "Entrada","Principal"…
  tags        dietary_tag[] default '{}',
  sort_order  int default 0
);

-- disponibilidade (datas bloqueadas / reservadas)
create table public.truck_availability (
  id          uuid primary key default gen_random_uuid(),
  truck_id    uuid references trucks(id) on delete cascade,
  date        date not null,
  status      text check (status in ('blocked','tentative','booked')),
  booking_id  uuid,
  unique (truck_id, date)
);

-- certificações
create table public.truck_documents (
  id          uuid primary key default gen_random_uuid(),
  truck_id    uuid references trucks(id) on delete cascade,
  kind        text,                          -- "HACCP","seguro","alvará"
  url         text,
  issued_at   date,
  expires_at  date
);

-- =============================================================================
-- 3. EVENTS, BOOKINGS, PROPOSALS
-- =============================================================================
create type event_kind as enum (
  'wedding','birthday','corporate','festival','conference','private','other'
);

create table public.events (
  id              uuid primary key default gen_random_uuid(),
  organizer_id    uuid not null references profiles(id) on delete cascade,
  title           text,
  kind            event_kind,
  start_at        timestamptz,
  end_at          timestamptz,
  expected_pax    int,
  city            text,
  address_id      uuid references addresses(id),
  budget_min      numeric(10,2),
  budget_max      numeric(10,2),
  notes           text,
  status          text default 'draft',
  created_at      timestamptz default now()
);

create type booking_status as enum (
  'inquiry','proposal_sent','accepted','confirmed','paid',
  'in_progress','completed','cancelled','refunded'
);

create table public.bookings (
  id                uuid primary key default gen_random_uuid(),
  event_id          uuid references events(id) on delete cascade,
  organizer_id      uuid references profiles(id),
  status            booking_status default 'inquiry',
  starts_at         timestamptz,
  ends_at           timestamptz,
  pax_count         int,
  total_amount      numeric(10,2),
  currency          char(3) default 'EUR',
  notes             text,
  cancellation_reason text,
  created_at        timestamptz default now(),
  updated_at        timestamptz default now()
);

create table public.booking_trucks (
  booking_id  uuid references bookings(id) on delete cascade,
  truck_id    uuid references trucks(id),
  agreed_price numeric(10,2),
  notes       text,
  primary key (booking_id, truck_id)
);

create table public.proposals (
  id            uuid primary key default gen_random_uuid(),
  booking_id    uuid references bookings(id) on delete cascade,
  prepared_by   uuid references profiles(id),    -- staff
  version       int default 1,
  body          jsonb,                           -- linhas: truck, qty, preço, addons
  total_amount  numeric(10,2),
  valid_until   date,
  pdf_url       text,
  signed_at     timestamptz,
  created_at    timestamptz default now()
);

-- =============================================================================
-- 4. PAYMENTS
-- =============================================================================
create type payment_status as enum ('pending','paid','failed','refunded');
create type payment_method as enum ('stripe','mbway','multibanco','manual');

create table public.payments (
  id              uuid primary key default gen_random_uuid(),
  booking_id      uuid references bookings(id) on delete cascade,
  amount          numeric(10,2),
  currency        char(3) default 'EUR',
  method          payment_method,
  status          payment_status default 'pending',
  provider_ref    text,                          -- stripe pi_…
  paid_at         timestamptz,
  created_at      timestamptz default now()
);

create table public.invoices (
  id              uuid primary key default gen_random_uuid(),
  booking_id      uuid references bookings(id),
  number          text unique,
  issued_at       date,
  pdf_url         text,
  vat_amount      numeric(10,2),
  total_amount    numeric(10,2)
);

-- =============================================================================
-- 5. MESSAGING
-- =============================================================================
create table public.conversations (
  id            uuid primary key default gen_random_uuid(),
  booking_id    uuid references bookings(id) on delete cascade,
  created_at    timestamptz default now()
);

create table public.conversation_participants (
  conversation_id uuid references conversations(id) on delete cascade,
  user_id         uuid references profiles(id),
  last_read_at    timestamptz,
  primary key (conversation_id, user_id)
);

create table public.messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid references conversations(id) on delete cascade,
  sender_id       uuid references profiles(id),
  body            text,
  attachments     jsonb,
  created_at      timestamptz default now()
);
create index messages_conv_idx on messages(conversation_id, created_at);

-- =============================================================================
-- 6. REVIEWS & FAVORITES
-- =============================================================================
create table public.reviews (
  id            uuid primary key default gen_random_uuid(),
  booking_id    uuid references bookings(id),
  truck_id      uuid references trucks(id) on delete cascade,
  organizer_id  uuid references profiles(id),
  rating_food   smallint check (rating_food between 1 and 5),
  rating_service smallint check (rating_service between 1 and 5),
  rating_value  smallint check (rating_value between 1 and 5),
  rating_overall numeric(2,1),
  body          text,
  reply_body    text,
  reply_at      timestamptz,
  is_verified   boolean default false,
  created_at    timestamptz default now(),
  unique (booking_id, truck_id)
);

create table public.favorites (
  user_id     uuid references profiles(id) on delete cascade,
  truck_id    uuid references trucks(id) on delete cascade,
  created_at  timestamptz default now(),
  primary key (user_id, truck_id)
);

-- =============================================================================
-- 7. AUXILIARY SERVICES (espaços / música / marketing)
-- =============================================================================
create type service_kind as enum ('venue','entertainment','planning','marketing','rental');

create table public.service_providers (
  id          uuid primary key default gen_random_uuid(),
  kind        service_kind,
  name        text,
  description text,
  city        text,
  price_from  numeric(10,2),
  image_url   text,
  contact_email text,
  contact_phone text,
  created_at  timestamptz default now()
);

create table public.booking_addons (
  id          uuid primary key default gen_random_uuid(),
  booking_id  uuid references bookings(id) on delete cascade,
  provider_id uuid references service_providers(id),
  description text,
  qty         int default 1,
  unit_price  numeric(10,2)
);

-- =============================================================================
-- 8. BLOG / CONTENT
-- =============================================================================
create table public.blog_authors (
  id          uuid primary key references profiles(id) on delete cascade,
  bio         text,
  twitter     text,
  instagram   text
);

create table public.blog_categories (
  id          serial primary key,
  slug        text unique not null,
  name        text not null
);

create type post_status as enum ('draft','scheduled','published','archived');

create table public.blog_posts (
  id            uuid primary key default gen_random_uuid(),
  slug          text unique not null,
  author_id     uuid references blog_authors(id),
  category_id   int references blog_categories(id),
  title         text not null,
  excerpt       text,
  cover_url     text,
  body_md       text,                        -- markdown
  read_minutes  int,
  status        post_status default 'draft',
  published_at  timestamptz,
  seo_title     text,
  seo_description text,
  created_at    timestamptz default now()
);
create index posts_published_idx on blog_posts(status, published_at desc);

-- =============================================================================
-- 9. SUPPORT (FAQ, contactos, newsletter)
-- =============================================================================
create table public.faqs (
  id          serial primary key,
  question    text not null,
  answer      text not null,
  topic       text,
  sort_order  int default 0
);

create table public.newsletter_subscribers (
  id          uuid primary key default gen_random_uuid(),
  email       text unique not null,
  confirmed   boolean default false,
  confirm_token text,
  created_at  timestamptz default now()
);

create table public.contact_requests (
  id          uuid primary key default gen_random_uuid(),
  name        text,
  email       text,
  phone       text,
  message     text,
  source_page text,
  handled_by  uuid references profiles(id),
  created_at  timestamptz default now()
);

-- =============================================================================
-- 10. NOTIFICATIONS, AUDIT, ANALYTICS
-- =============================================================================
create table public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references profiles(id) on delete cascade,
  kind        text,                          -- "booking.confirmed"…
  payload     jsonb,
  read_at     timestamptz,
  created_at  timestamptz default now()
);

create table public.audit_log (
  id          bigserial primary key,
  actor_id    uuid,
  action      text,
  entity      text,
  entity_id   uuid,
  diff        jsonb,
  ip          inet,
  created_at  timestamptz default now()
);

-- =============================================================================
-- 11. STORAGE BUCKETS
-- =============================================================================
insert into storage.buckets (id, name, public) values
  ('truck-images',  'truck-images',  true),
  ('menu-images',   'menu-images',   true),
  ('blog-images',   'blog-images',   true),
  ('avatars',       'avatars',       true),
  ('documents',     'documents',     false)
on conflict do nothing;

-- =============================================================================
-- 12. ROW-LEVEL SECURITY
-- =============================================================================
alter table profiles            enable row level security;
alter table trucks              enable row level security;
alter table truck_images        enable row level security;
alter table truck_availability  enable row level security;
alter table truck_documents     enable row level security;
alter table menu_items          enable row level security;
alter table events              enable row level security;
alter table bookings            enable row level security;
alter table booking_trucks      enable row level security;
alter table proposals           enable row level security;
alter table payments            enable row level security;
alter table invoices            enable row level security;
alter table conversations       enable row level security;
alter table conversation_participants enable row level security;
alter table messages            enable row level security;
alter table reviews             enable row level security;
alter table favorites           enable row level security;
alter table notifications       enable row level security;

-- helper
create or replace function public.is_admin() returns boolean language sql stable
  as $$ select exists(select 1 from profiles where id = auth.uid() and role in ('admin','staff')) $$;

-- public catalog read
create policy "trucks_public_read"   on trucks   for select using (status='active' or owner_id = auth.uid() or is_admin());
create policy "truck_images_read"    on truck_images for select using (true);
create policy "menu_items_read"      on menu_items   for select using (true);
create policy "reviews_read"         on reviews      for select using (true);

-- owner can manage own truck
create policy "trucks_owner_write"   on trucks   for all using (owner_id = auth.uid() or is_admin()) with check (owner_id = auth.uid() or is_admin());
create policy "truck_images_write"   on truck_images for all using (exists (select 1 from trucks t where t.id = truck_id and (t.owner_id = auth.uid() or is_admin())));
create policy "menu_items_write"     on menu_items   for all using (exists (select 1 from trucks t where t.id = truck_id and (t.owner_id = auth.uid() or is_admin())));
create policy "truck_avail_write"    on truck_availability for all using (exists (select 1 from trucks t where t.id = truck_id and (t.owner_id = auth.uid() or is_admin())));
create policy "truck_docs_write"     on truck_documents    for all using (exists (select 1 from trucks t where t.id = truck_id and (t.owner_id = auth.uid() or is_admin())));

-- profile self
create policy "profile_self"         on profiles for all using (id = auth.uid() or is_admin()) with check (id = auth.uid() or is_admin());

-- bookings: organizer sees own, owner sees the ones for his trucks
create policy "bookings_organizer"   on bookings for select using (organizer_id = auth.uid() or is_admin()
   or exists (select 1 from booking_trucks bt join trucks t on t.id = bt.truck_id where bt.booking_id = bookings.id and t.owner_id = auth.uid()));
create policy "bookings_insert_org"  on bookings for insert with check (organizer_id = auth.uid());
create policy "bookings_update"      on bookings for update using (organizer_id = auth.uid() or is_admin());

-- favorites & notifications: only owner
create policy "fav_self" on favorites for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "notif_self" on notifications for select using (user_id = auth.uid());

-- =============================================================================
-- 13. TRIGGERS / FUNCTIONS
-- =============================================================================
-- updated_at auto
create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

create trigger trg_profiles_touch before update on profiles
  for each row execute function touch_updated_at();
create trigger trg_trucks_touch   before update on trucks
  for each row execute function touch_updated_at();
create trigger trg_bookings_touch before update on bookings
  for each row execute function touch_updated_at();

-- recalcular rating_avg do truck quando review insere/atualiza
create or replace function public.recalc_truck_rating() returns trigger language plpgsql as $$
begin
  update trucks t set
    rating_avg = coalesce((select round(avg(rating_overall)::numeric, 1) from reviews where truck_id = t.id), 0),
    rating_count = (select count(*) from reviews where truck_id = t.id)
  where t.id = new.truck_id;
  return new;
end $$;

create trigger trg_reviews_rating after insert or update or delete on reviews
  for each row execute function recalc_truck_rating();

-- profile criado automaticamente quando user se regista
create or replace function public.handle_new_user() returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, full_name, locale)
  values (new.id, new.raw_user_meta_data->>'full_name', coalesce(new.raw_user_meta_data->>'locale','pt-PT'));
  return new;
end $$;

create trigger trg_auth_new_user after insert on auth.users
  for each row execute function handle_new_user();

-- seed mínimo de categorias
insert into categories (slug, name_pt, icon) values
 ('pizza','Pizza','local_pizza'),
 ('kebab','Kebab','restaurant'),
 ('hamburguer','Hambúrguer','lunch_dining'),
 ('poke','Poke','set_meal'),
 ('sobremesas','Sobremesas','icecream'),
 ('pequeno-almoco','Pequeno Almoço','free_breakfast'),
 ('brunch','Brunch','coffee'),
 ('tacos','Tacos','tapas'),
 ('sushi','Sushi','rice_bowl'),
 ('bbq','BBQ','outdoor_grill'),
 ('sandwich','Sandwich','bakery_dining')
on conflict do nothing;
