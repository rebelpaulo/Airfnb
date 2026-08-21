\set ON_ERROR_STOP on

begin;

do $guard$
begin
  if current_database() !~ '^fb_tailor_e2e_[a-z0-9_]+$' then
    raise exception 'local E2E seed refused unsafe database: %', current_database();
  end if;
  if exists (select 1 from auth.users where id::text like 'f2700000-0000-4000-8000-%') then
    raise exception 'local E2E seed actors already exist';
  end if;
end
$guard$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('f2700000-0000-4000-8000-000000000001', 'organizer-e2e@example.invalid', '{"full_name":"Organizador E2E"}'),
  ('f2700000-0000-4000-8000-000000000002', 'supplier-a-e2e@example.invalid', '{"full_name":"Fornecedor A E2E"}'),
  ('f2700000-0000-4000-8000-000000000003', 'supplier-b-e2e@example.invalid', '{"full_name":"Fornecedor B E2E"}'),
  ('f2700000-0000-4000-8000-000000000004', 'admin-e2e@example.invalid', '{"full_name":"Admin E2E"}');

update public.airfnb_profiles as profile
   set role = fixture.role::public.airfnb_user_role,
       full_name = fixture.full_name,
       display_name = fixture.display_name,
       company_name = fixture.company_name,
       onboarding_completed = true
  from (values
    ('f2700000-0000-4000-8000-000000000001'::uuid, 'organizer', 'Organizador E2E', 'Organizador E2E', 'Eventos E2E'),
    ('f2700000-0000-4000-8000-000000000002'::uuid, 'owner', 'Fornecedor A E2E', 'Fornecedor A E2E', 'Fornecedor A E2E'),
    ('f2700000-0000-4000-8000-000000000003'::uuid, 'owner', 'Fornecedor B E2E', 'Fornecedor B E2E', 'Fornecedor B E2E'),
    ('f2700000-0000-4000-8000-000000000004'::uuid, 'admin', 'Admin E2E', 'Admin E2E', 'F&B Tailor E2E')
  ) as fixture(id, role, full_name, display_name, company_name)
 where profile.id = fixture.id;

insert into public.airfnb_categories(id, slug, name_pt, name_en, icon)
values (270001, 'e2e-portuguesa', 'Portuguesa E2E', 'Portuguese E2E', 'restaurant');

insert into public.airfnb_trucks (
  id, owner_id, slug, name, tagline, description, base_city,
  capacity, min_event_pax, max_event_pax, base_price, price_per_pax,
  status, featured, cuisine_types, dietary_options, compatible_event_kinds,
  service_type, homologation_expires_at, insurance_expires_at
) values
  (
    'f2700000-0000-4000-8000-000000000010',
    'f2700000-0000-4000-8000-000000000002',
    'fornecedor-a-e2e', 'Fornecedor A E2E', 'Sabores locais E2E',
    'Serviço local usado exclusivamente pelo ensaio E2E.', 'Lisboa',
    220, 20, 500, 500, 18, 'active', true, array['portuguesa'],
    array['vegan'::public.airfnb_dietary_tag],
    array['corporate'::public.airfnb_event_kind], 'food_truck',
    current_date + 365, current_date + 365
  ),
  (
    'f2700000-0000-4000-8000-000000000011',
    'f2700000-0000-4000-8000-000000000003',
    'fornecedor-b-e2e', 'Fornecedor B E2E', 'Isolamento E2E',
    'Serviço estrangeiro à conta do fornecedor A.', 'Porto',
    80, 20, 120, 350, 14, 'active', false, array['italiana'], '{}',
    array['private'::public.airfnb_event_kind], 'catering', null, null
  ),
  (
    'f2700000-0000-4000-8000-000000000012',
    'f2700000-0000-4000-8000-000000000003',
    'fornecedor-pendente-e2e', 'Fornecedor Pendente E2E', null, null,
    'Porto', 100, 20, 150, 300, 12, 'pending_review', false, '{}', '{}',
    '{}', 'bar', null, null
  );

insert into public.airfnb_truck_categories(truck_id, category_id) values
  ('f2700000-0000-4000-8000-000000000010', 270001),
  ('f2700000-0000-4000-8000-000000000011', 270001);

insert into public.airfnb_truck_images(id, truck_id, url, alt, sort_order, is_cover, kind) values
  ('f2700000-0000-4000-8000-000000000020', 'f2700000-0000-4000-8000-000000000010', '/truck-placeholder.svg', 'Fornecedor A E2E', 0, true, 'truck'),
  ('f2700000-0000-4000-8000-000000000021', 'f2700000-0000-4000-8000-000000000011', '/truck-placeholder.svg', 'Fornecedor B E2E', 0, true, 'truck');

insert into public.airfnb_menu_items(id, truck_id, name, description, price, category, sort_order) values
  ('f2700000-0000-4000-8000-000000000030', 'f2700000-0000-4000-8000-000000000010', 'Menu E2E', 'Menu local de teste.', 18, 'Principal', 0);

insert into public.airfnb_event_requests (
  id, organizer_id, title, kind, description, start_at, end_at, city,
  expected_pax, slots_needed, budget_min, budget_max, applications_deadline,
  status, visibility, discovery_mode, accepted_deal_types, desired_cuisines,
  application_response_window_hours, contact_name, contact_email, locality
) values
  (
    'f2700000-0000-4000-8000-000000000100',
    'f2700000-0000-4000-8000-000000000001',
    'Evento Corporativo E2E', 'corporate', 'Pedido local para o percurso E2E.',
    now() + interval '30 days', now() + interval '30 days 6 hours', 'Lisboa',
    100, 1, 800, 1400, now() + interval '20 days', 'open', 'public',
    'broadcast', array['fixed','mixed'], array['portuguesa'], 48,
    'Contacto Organizador E2E', 'private-organizer-e2e@example.invalid', 'Lisboa'
  ),
  (
    'f2700000-0000-4000-8000-000000000101',
    'f2700000-0000-4000-8000-000000000004',
    'SENTINELA PRIVADA FORNECEDOR B', 'private', 'Nunca visível a fornecedor A.',
    now() + interval '40 days', now() + interval '40 days 4 hours', 'Porto',
    60, 1, 500, 900, now() + interval '25 days', 'open', 'invite_only',
    'curated', array['fixed'], array['italiana'], 48,
    'Sentinela Privada', 'private-sentinel@example.invalid', 'Porto'
  );

do $assert$
begin
  if (select count(*) from auth.users where id::text like 'f2700000-0000-4000-8000-%') <> 4
     or (select count(*) from public.airfnb_profiles where id::text like 'f2700000-0000-4000-8000-%') <> 4
     or (select count(*) from public.airfnb_trucks where id::text like 'f2700000-0000-4000-8000-%') <> 3
     or (select count(*) from public.airfnb_event_requests where id::text like 'f2700000-0000-4000-8000-%') <> 2 then
    raise exception 'local E2E seed cardinality mismatch';
  end if;
end
$assert$;

commit;
