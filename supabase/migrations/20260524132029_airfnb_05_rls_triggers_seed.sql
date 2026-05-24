-- airfnb_05_rls_triggers_seed
-- applied at 20260524132029


-- helpers ---------------------------------------------------------------
create or replace function public.airfnb_is_admin() returns boolean
  language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.airfnb_profiles where id = auth.uid() and role in ('admin','staff'))
$$;

create or replace function public.airfnb_touch_updated_at() returns trigger
  language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

create or replace function public.airfnb_recalc_truck_rating() returns trigger
  language plpgsql as $$
declare tid uuid;
begin
  tid := coalesce(new.truck_id, old.truck_id);
  update public.airfnb_trucks t set
    rating_avg   = coalesce((select round(avg(rating_overall)::numeric, 1) from public.airfnb_reviews where truck_id = tid), 0),
    rating_count = (select count(*) from public.airfnb_reviews where truck_id = tid)
  where t.id = tid;
  return coalesce(new, old);
end $$;

create or replace function public.airfnb_handle_new_user() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  insert into public.airfnb_profiles (id, full_name, locale)
  values (new.id, new.raw_user_meta_data->>'full_name', coalesce(new.raw_user_meta_data->>'locale','pt-PT'))
  on conflict (id) do nothing;
  return new;
end $$;

-- triggers --------------------------------------------------------------
create trigger airfnb_trg_profiles_touch  before update on public.airfnb_profiles  for each row execute function public.airfnb_touch_updated_at();
create trigger airfnb_trg_trucks_touch    before update on public.airfnb_trucks    for each row execute function public.airfnb_touch_updated_at();
create trigger airfnb_trg_bookings_touch  before update on public.airfnb_bookings  for each row execute function public.airfnb_touch_updated_at();
create trigger airfnb_trg_reviews_rating  after insert or update or delete on public.airfnb_reviews for each row execute function public.airfnb_recalc_truck_rating();

-- only create the auth trigger if it doesn't already exist (safe re-runs)
do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'airfnb_trg_auth_new_user') then
    create trigger airfnb_trg_auth_new_user
      after insert on auth.users
      for each row execute function public.airfnb_handle_new_user();
  end if;
end $$;

-- RLS -------------------------------------------------------------------
alter table public.airfnb_profiles                  enable row level security;
alter table public.airfnb_trucks                    enable row level security;
alter table public.airfnb_truck_images              enable row level security;
alter table public.airfnb_truck_availability        enable row level security;
alter table public.airfnb_truck_documents           enable row level security;
alter table public.airfnb_menu_items                enable row level security;
alter table public.airfnb_events                    enable row level security;
alter table public.airfnb_bookings                  enable row level security;
alter table public.airfnb_booking_trucks            enable row level security;
alter table public.airfnb_proposals                 enable row level security;
alter table public.airfnb_payments                  enable row level security;
alter table public.airfnb_invoices                  enable row level security;
alter table public.airfnb_conversations             enable row level security;
alter table public.airfnb_conversation_participants enable row level security;
alter table public.airfnb_messages                  enable row level security;
alter table public.airfnb_reviews                   enable row level security;
alter table public.airfnb_favorites                 enable row level security;
alter table public.airfnb_notifications             enable row level security;
alter table public.airfnb_blog_posts                enable row level security;

-- public reads
create policy "airfnb_trucks_public_read" on public.airfnb_trucks for select
  using (status = 'active' or owner_id = auth.uid() or public.airfnb_is_admin());
create policy "airfnb_truck_images_read"  on public.airfnb_truck_images for select using (true);
create policy "airfnb_menu_items_read"    on public.airfnb_menu_items   for select using (true);
create policy "airfnb_reviews_read"       on public.airfnb_reviews      for select using (true);
create policy "airfnb_posts_public_read"  on public.airfnb_blog_posts   for select
  using (status = 'published' or public.airfnb_is_admin());

-- owner writes
create policy "airfnb_trucks_owner_write" on public.airfnb_trucks for all
  using (owner_id = auth.uid() or public.airfnb_is_admin())
  with check (owner_id = auth.uid() or public.airfnb_is_admin());

create policy "airfnb_truck_images_write" on public.airfnb_truck_images for all
  using (exists (select 1 from public.airfnb_trucks t where t.id = truck_id and (t.owner_id = auth.uid() or public.airfnb_is_admin())));

create policy "airfnb_menu_items_write"   on public.airfnb_menu_items for all
  using (exists (select 1 from public.airfnb_trucks t where t.id = truck_id and (t.owner_id = auth.uid() or public.airfnb_is_admin())));

create policy "airfnb_truck_avail_write"  on public.airfnb_truck_availability for all
  using (exists (select 1 from public.airfnb_trucks t where t.id = truck_id and (t.owner_id = auth.uid() or public.airfnb_is_admin())));

create policy "airfnb_truck_docs_write"   on public.airfnb_truck_documents for all
  using (exists (select 1 from public.airfnb_trucks t where t.id = truck_id and (t.owner_id = auth.uid() or public.airfnb_is_admin())));

-- profiles
create policy "airfnb_profile_self" on public.airfnb_profiles for all
  using (id = auth.uid() or public.airfnb_is_admin())
  with check (id = auth.uid() or public.airfnb_is_admin());

-- bookings
create policy "airfnb_bookings_select" on public.airfnb_bookings for select
  using (
    organizer_id = auth.uid()
    or public.airfnb_is_admin()
    or exists (
      select 1 from public.airfnb_booking_trucks bt
      join public.airfnb_trucks t on t.id = bt.truck_id
      where bt.booking_id = airfnb_bookings.id and t.owner_id = auth.uid()
    )
  );
create policy "airfnb_bookings_insert" on public.airfnb_bookings for insert with check (organizer_id = auth.uid());
create policy "airfnb_bookings_update" on public.airfnb_bookings for update using (organizer_id = auth.uid() or public.airfnb_is_admin());

-- favorites & notifications
create policy "airfnb_fav_self"   on public.airfnb_favorites    for all  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "airfnb_notif_self" on public.airfnb_notifications for select using (user_id = auth.uid());

-- seed -----------------------------------------------------------------
insert into public.airfnb_categories (slug, name_pt, icon) values
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
on conflict (slug) do nothing;

insert into public.airfnb_blog_categories (slug, name) values
 ('inspiracao','Inspiração'),
 ('dicas','Dicas'),
 ('tendencias','Tendências'),
 ('casos-de-sucesso','Casos de Sucesso')
on conflict (slug) do nothing;

insert into public.airfnb_faqs (question, answer, topic, sort_order) values
 ('Que tipos de camiões estão disponíveis?',                'Temos food trucks de várias categorias: hambúrguer, pizza, sushi, tacos, BBQ, sobremesas, brunch e mais. Filtra no catálogo pelo estilo que procuras.', 'reservas', 1),
 ('Quanto custa alugar um camião de Comida?',               'O preço depende do tipo de truck, número de convidados, duração e localização. Pede uma proposta personalizada à nossa equipa.',                       'precos',   2),
 ('Com quanto tempo de antecedência devo reservar?',        'Recomendamos reservar com pelo menos 3 a 4 semanas de antecedência, sobretudo em épocas altas.',                                                       'reservas', 3),
 ('Cancelamento de reservas. Como funciona?',               'Cancelamentos até 14 dias antes têm reembolso total; entre 14 e 7 dias 50%; menos de 7 dias não são reembolsáveis.',                                   'reservas', 4),
 ('Restrições alimentares ou alergias.',                    'A maioria dos trucks oferece opções vegetarianas, veganas e sem glúten. Indica as restrições no formulário de reserva.',                                'menus',    5)
on conflict do nothing;

-- storage buckets ------------------------------------------------------
insert into storage.buckets (id, name, public) values
  ('airfnb-truck-images', 'airfnb-truck-images', true),
  ('airfnb-menu-images',  'airfnb-menu-images',  true),
  ('airfnb-blog-images',  'airfnb-blog-images',  true),
  ('airfnb-avatars',      'airfnb-avatars',      true),
  ('airfnb-documents',    'airfnb-documents',    false)
on conflict (id) do nothing;
;
