-- airfnb_04_messaging_reviews_content
-- applied at 20260524131939


create type airfnb_service_kind as enum ('venue','entertainment','planning','marketing','rental');
create type airfnb_post_status  as enum ('draft','scheduled','published','archived');

-- Messaging --------------------------------------------------------------
create table public.airfnb_conversations (
  id          uuid primary key default gen_random_uuid(),
  booking_id  uuid references public.airfnb_bookings(id) on delete cascade,
  created_at  timestamptz default now()
);

create table public.airfnb_conversation_participants (
  conversation_id uuid references public.airfnb_conversations(id) on delete cascade,
  user_id         uuid references public.airfnb_profiles(id),
  last_read_at    timestamptz,
  primary key (conversation_id, user_id)
);

create table public.airfnb_messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid references public.airfnb_conversations(id) on delete cascade,
  sender_id       uuid references public.airfnb_profiles(id),
  body            text,
  attachments     jsonb,
  created_at      timestamptz default now()
);
create index airfnb_messages_conv_idx on public.airfnb_messages(conversation_id, created_at);

-- Reviews & favorites ----------------------------------------------------
create table public.airfnb_reviews (
  id             uuid primary key default gen_random_uuid(),
  booking_id     uuid references public.airfnb_bookings(id),
  truck_id       uuid references public.airfnb_trucks(id) on delete cascade,
  organizer_id   uuid references public.airfnb_profiles(id),
  rating_food    smallint check (rating_food between 1 and 5),
  rating_service smallint check (rating_service between 1 and 5),
  rating_value   smallint check (rating_value between 1 and 5),
  rating_overall numeric(2,1),
  body           text,
  reply_body     text,
  reply_at       timestamptz,
  is_verified    boolean default false,
  created_at     timestamptz default now(),
  unique (booking_id, truck_id)
);

create table public.airfnb_favorites (
  user_id    uuid references public.airfnb_profiles(id) on delete cascade,
  truck_id   uuid references public.airfnb_trucks(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, truck_id)
);

-- Auxiliary services -----------------------------------------------------
create table public.airfnb_service_providers (
  id            uuid primary key default gen_random_uuid(),
  kind          airfnb_service_kind,
  name          text,
  description   text,
  city          text,
  price_from    numeric(10,2),
  image_url     text,
  contact_email text,
  contact_phone text,
  created_at    timestamptz default now()
);

create table public.airfnb_booking_addons (
  id          uuid primary key default gen_random_uuid(),
  booking_id  uuid references public.airfnb_bookings(id) on delete cascade,
  provider_id uuid references public.airfnb_service_providers(id),
  description text,
  qty         int default 1,
  unit_price  numeric(10,2)
);

-- Blog -------------------------------------------------------------------
create table public.airfnb_blog_authors (
  id        uuid primary key references public.airfnb_profiles(id) on delete cascade,
  bio       text,
  twitter   text,
  instagram text
);

create table public.airfnb_blog_categories (
  id   serial primary key,
  slug text unique not null,
  name text not null
);

create table public.airfnb_blog_posts (
  id              uuid primary key default gen_random_uuid(),
  slug            text unique not null,
  author_id       uuid references public.airfnb_blog_authors(id),
  category_id     int  references public.airfnb_blog_categories(id),
  title           text not null,
  excerpt         text,
  cover_url       text,
  body_md         text,
  read_minutes    int,
  status          airfnb_post_status default 'draft',
  published_at    timestamptz,
  seo_title       text,
  seo_description text,
  created_at      timestamptz default now()
);
create index airfnb_posts_published_idx on public.airfnb_blog_posts(status, published_at desc);

-- Support / system -------------------------------------------------------
create table public.airfnb_faqs (
  id         serial primary key,
  question   text not null,
  answer     text not null,
  topic      text,
  sort_order int default 0
);

create table public.airfnb_newsletter_subscribers (
  id            uuid primary key default gen_random_uuid(),
  email         text unique not null,
  confirmed     boolean default false,
  confirm_token text,
  created_at    timestamptz default now()
);

create table public.airfnb_contact_requests (
  id          uuid primary key default gen_random_uuid(),
  name        text,
  email       text,
  phone       text,
  message     text,
  source_page text,
  handled_by  uuid references public.airfnb_profiles(id),
  created_at  timestamptz default now()
);

create table public.airfnb_notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references public.airfnb_profiles(id) on delete cascade,
  kind       text,
  payload    jsonb,
  read_at    timestamptz,
  created_at timestamptz default now()
);

create table public.airfnb_audit_log (
  id         bigserial primary key,
  actor_id   uuid,
  action     text,
  entity     text,
  entity_id  uuid,
  diff       jsonb,
  ip         inet,
  created_at timestamptz default now()
);
;
