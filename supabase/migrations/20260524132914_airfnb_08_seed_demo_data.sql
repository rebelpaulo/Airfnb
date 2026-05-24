-- airfnb_08_seed_demo_data
-- applied at 20260524132914


-- create one demo seed user in auth.users (idempotent)
do $$
declare seed_id uuid := '11111111-1111-1111-1111-111111111111';
begin
  insert into auth.users (
    id, instance_id, aud, role, email,
    encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) values (
    seed_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated','authenticated',
    'seed@airfnb.local',
    extensions.crypt('changeme', extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"Air F&B Seed"}'::jsonb,
    now(), now()
  ) on conflict (id) do nothing;

  -- trigger created the profile; upgrade to admin
  update public.airfnb_profiles
     set role = 'admin', display_name = 'Air F&B Seed', company_name = 'Air F&B'
   where id = seed_id;
end $$;

-- seed trucks (all owned by seed user; real owners can later claim/replace)
with seed as (select '11111111-1111-1111-1111-111111111111'::uuid as oid)
insert into public.airfnb_trucks
  (owner_id, slug, name, tagline, description, base_city, capacity, base_price, price_per_pax, status, featured, rating_avg, rating_count)
select oid, slug, name, tagline, descr, city, cap, base, pp, 'active'::airfnb_truck_status, feat, rating, rcount
  from seed, (values
    ('divine-burguers',     'Divine Burguer''s',      'O melhor estilo americano',           'Hambúrgueres artesanais com pão de brioche e batatas trufadas.', 'Lisboa',  100, 850.00, 12.50, true,  4.8, 27),
    ('gypsy-kitchen',       'Gypsy Kitchen',          'Cozinha de Fusão',                    'Pratos de inspiração mediterrânica com toque oriental.',         'Lisboa',  100, 900.00, 13.00, true,  4.7, 18),
    ('el-mexicano',         'El Mexicano',            'Autêntica comida mexicana',           'Tacos, quesadillas e burritos como em Cidade do México.',         'Porto',   100, 780.00, 11.00, false, 4.6, 22),
    ('la-dolce-vita',       'La Dolce Vita',          'Sabores Italianos Autênticos',        'Pasta fresca, pizzas em forno a lenha e tiramisu caseiro.',       'Lisboa',  100, 950.00, 14.00, true,  4.9, 31),
    ('bbq-kings',           'BBQ Kings',              'Os Mestres do Churrasco',             'Carne fumada lentamente durante 14h, molhos da casa.',            'Algarve', 100, 1100.00, 15.00, false, 4.5, 14),
    ('sushi-zen',           'Sushi Zen',              'A excelência da cozinha Japonesa',    'Nigiri, sashimi e uramaki preparados ao momento.',                'Porto',   100, 1050.00, 16.50, true,  4.9, 19),
    ('taco-fiesta',         'Taco Fiesta',            'Sabores mexicanos autênticos',        'Tacos de pastor, cochinita e barbacoa.',                          'Lisboa',  100, 820.00, 11.50, false, 4.4, 11),
    ('turkish-delights',    'Turkish Delights',       'Autêntica Cozinha Turca',             'Doner kebab, kofta, baklava e chá turco.',                        'Lisboa',  100, 760.00, 10.50, false, 4.3, 9),
    ('portuguese-tradition','Portuguese Traditions',  'Sabores Tradicionais',                'Bifanas, francesinhas e pataniscas de bacalhau.',                 'Lisboa',  100, 880.00, 12.00, true,  4.8, 24),
    ('wok-and-roll',        'Wok & Roll',             'Cozinha Asiática',                    'Noodles, dim sum e bao buns recheados.',                          'Porto',   80,  720.00, 10.00, false, 4.5, 13),
    ('pizza-vesuvio',       'Pizza Vesúvio',          'Forno a lenha',                       'Pizzas napolitanas com massa de fermentação longa.',              'Lisboa',  120, 990.00, 13.50, true,  4.7, 28),
    ('creperia-pt',         'Crep''eria',             'Crepes franceses',                    'Crepes salgados e doces feitos à frente do cliente.',             'Cascais', 60,  580.00, 9.00,  false, 4.6, 16)
  ) as v(slug,name,tagline,descr,city,cap,base,pp,feat,rating,rcount)
on conflict (slug) do nothing;

-- link trucks to categories
insert into public.airfnb_truck_categories (truck_id, category_id)
select t.id, c.id
  from public.airfnb_trucks t
  join (values
    ('divine-burguers',     'hamburguer'),
    ('gypsy-kitchen',       'brunch'),
    ('el-mexicano',         'tacos'),
    ('la-dolce-vita',       'pizza'),
    ('bbq-kings',           'bbq'),
    ('sushi-zen',           'sushi'),
    ('taco-fiesta',         'tacos'),
    ('turkish-delights',    'kebab'),
    ('portuguese-tradition','sandwich'),
    ('wok-and-roll',        'sushi'),
    ('pizza-vesuvio',       'pizza'),
    ('creperia-pt',         'sobremesas')
  ) as m(truck_slug, cat_slug)        on m.truck_slug = t.slug
  join public.airfnb_categories c     on c.slug       = m.cat_slug
on conflict do nothing;

-- one cover image per truck (Unsplash placeholders)
insert into public.airfnb_truck_images (truck_id, url, alt, is_cover, sort_order)
select t.id, v.url, t.name, true, 0
  from public.airfnb_trucks t
  join (values
    ('divine-burguers',     'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=900'),
    ('gypsy-kitchen',       'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=900'),
    ('el-mexicano',         'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=900'),
    ('la-dolce-vita',       'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=900'),
    ('bbq-kings',           'https://images.unsplash.com/photo-1529193591184-b1d58069ecdd?w=900'),
    ('sushi-zen',           'https://images.unsplash.com/photo-1579871494447-9811cf80d66c?w=900'),
    ('taco-fiesta',         'https://images.unsplash.com/photo-1552332386-f8dd00dc2f85?w=900'),
    ('turkish-delights',    'https://images.unsplash.com/photo-1561651823-34feb02250e4?w=900'),
    ('portuguese-tradition','https://images.unsplash.com/photo-1432139509613-5c4255815697?w=900'),
    ('wok-and-roll',        'https://images.unsplash.com/photo-1526318896980-cf78c088247c?w=900'),
    ('pizza-vesuvio',       'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=900'),
    ('creperia-pt',         'https://images.unsplash.com/photo-1519676867240-f03562e64548?w=900')
  ) as v(truck_slug, url) on v.truck_slug = t.slug
on conflict do nothing;

-- one menu sample per truck
insert into public.airfnb_menu_items (truck_id, name, description, price, category)
select t.id, m.item, m.descr, m.price, 'Principais'
  from public.airfnb_trucks t
  join (values
    ('divine-burguers',     'Smashburger',           'Carne picada do dia, queijo cheddar fundido e molho da casa.', 9.50),
    ('gypsy-kitchen',       'Bowl mediterrânico',    'Quinoa, grão, abóbora assada e tahine de limão.',              10.50),
    ('el-mexicano',         'Taco al Pastor',         'Porco marinado em achiote, ananás grelhado e coentros.',       4.50),
    ('la-dolce-vita',       'Pizza Margherita',       'Tomate San Marzano, mozzarella fior di latte e manjericão.',   11.00),
    ('bbq-kings',           'Pulled Pork Bun',        'Pá de porco fumada 14h em bun de batata-doce.',                10.50),
    ('sushi-zen',           'Especial 16 peças',      'Sashimi de salmão, nigiri de atum e uramaki da casa.',         18.00),
    ('taco-fiesta',         'Burrito Carnitas',       'Tortilha de farinha, porco confitado, arroz e feijão preto.',  9.00),
    ('turkish-delights',    'Doner kebab',            'Carne de vitela, salada, hummus e iogurte de menta.',          8.50),
    ('portuguese-tradition','Bifana especial',        'Lombo de porco em vinha-d''alhos, mostarda e pão estaladiço.', 4.50),
    ('wok-and-roll',        'Bao Pork Belly',         'Bao cozido a vapor com barriga de porco glaceada.',            6.50),
    ('pizza-vesuvio',       'Pizza Diavola',          'Tomate, mozzarella, salame picante e azeite de chili.',        12.50),
    ('creperia-pt',         'Crepe Nutella & Banana', 'Crepe fino, Nutella, banana caramelizada e amêndoa.',          5.00)
  ) as m(truck_slug, item, descr, price) on m.truck_slug = t.slug
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- service providers (espaços, música, marketing)
-- ---------------------------------------------------------------------------
insert into public.airfnb_service_providers (kind, name, description, city, price_from, image_url, contact_email)
values
  ('venue',         'Quinta dos Olivais',      'Quinta com 5 hectares, capacidade até 250 pessoas.',  'Sintra',   1800.00, 'https://images.unsplash.com/photo-1464366400600-7168b8af9bc3?w=900',  'reservas@quintaolivais.example'),
  ('venue',         'Atrium Industrial',       'Espaço urbano de 600m² no centro do Porto.',          'Porto',    1200.00, 'https://images.unsplash.com/photo-1519167758481-83f550bb49b3?w=900',  'ola@atriumindustrial.example'),
  ('venue',         'Casa do Mar',             'Salão à beira-mar com terraço, até 120 pessoas.',     'Cascais',  2200.00, 'https://images.unsplash.com/photo-1465495976277-4387d4b0e4a6?w=900',  'eventos@casadomar.example'),
  ('entertainment', 'Bumba Music',             'Banda ao vivo (4 elementos) e DJ residente.',         'Lisboa',    900.00, 'https://images.unsplash.com/photo-1501386761578-eac5c94b800a?w=900',  'booking@bumba.example'),
  ('entertainment', 'DJ Solo Marina',          'DJ residente em festas privadas e casamentos.',       'Lisboa',    450.00, 'https://images.unsplash.com/photo-1493676304819-0d7a8d026dcf?w=900',  'marina@djmarina.example'),
  ('marketing',     'Curva Studio',            'Landing pages, redes e gestão de campanhas pagas.',   'Lisboa',    600.00, 'https://images.unsplash.com/photo-1432888622747-4eb9a8efeb07?w=900',  'studio@curva.example'),
  ('planning',      'PlanIt Eventos',          'Wedding planners e gestão integrada de convidados.',  'Lisboa',    750.00, 'https://images.unsplash.com/photo-1492684223066-81342ee5ff30?w=900',  'planning@planit.example'),
  ('rental',        'Aluga Tudo',              'Mesas, cadeiras, talheres, lounge, geradores.',       'Porto',     350.00, null,                                                                'aluga@alugatudo.example')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- blog posts (use seed user as author)
-- ---------------------------------------------------------------------------
insert into public.airfnb_blog_authors (id, bio)
values ('11111111-1111-1111-1111-111111111111', 'Equipa editorial Air F&B.')
on conflict (id) do nothing;

insert into public.airfnb_blog_posts (slug, author_id, category_id, title, excerpt, cover_url, body_md, read_minutes, status, published_at)
select v.slug, '11111111-1111-1111-1111-111111111111'::uuid, c.id, v.title, v.excerpt, v.cover, v.body, v.minutes, 'published'::airfnb_post_status, now() - (v.days || ' days')::interval
  from (values
    ('como-organizar-evento-perfeito-food-trucks',
     'inspiracao',
     'Como organizar o evento perfeito com Food Trucks',
     'Um guia prático em 7 passos para escolher, contratar e coordenar trucks no teu próximo evento.',
     'https://images.unsplash.com/photo-1414235077428-338989a2e8c0?w=1400',
     '## Passo 1 — Define o tipo de evento\n\nCasamento, festa de empresa ou festival? O tipo de evento define o número de trucks, a variedade de menus e a logística.\n\n## Passo 2 — Estima o número de convidados\n\nUm truck serve em média 80 pessoas/hora. Em eventos com mais de 100 convidados costuma fazer sentido contratar 2 ou 3 trucks complementares.\n\n## Passo 3 — Escolhe os estilos gastronómicos\n\nMistura comida principal + sobremesa + bebida especial. Mexicano + Pizza + Gelado é uma fórmula vencedora.',
     6, 1),
    ('tendencias-gastronomicas-2025',
     'tendencias',
     'Tendências gastronómicas para 2025',
     'Brunch tudo-o-dia, fermentações, sabores asiáticos e proteína vegetal: o que vai mandar este ano.',
     'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=1400',
     '## Brunch all day\n\nA categoria mais procurada para eventos corporativos.\n\n## Sabores asiáticos\n\nBao, ramen e dim sum dominam os street food markets.\n\n## Plant-based\n\nMais de 30% dos eventos pedem opções 100% vegetais.',
     4, 7),
    ('casamentos-food-trucks-5-dicas',
     'dicas',
     'Casamentos com Food Trucks: 5 dicas',
     'Como integrar trucks numa cerimónia mais formal e impressionar os convidados.',
     'https://images.unsplash.com/photo-1519225421980-715cb0215aed?w=1400',
     '## 1. Loiça vintage\n\nApresentação faz toda a diferença.\n\n## 2. Estações temáticas\n\nUm truck por momento (cocktail, jantar, sobremesa).\n\n## 3. Menu impresso\n\nReforça a experiência sensorial.',
     5, 14),
    ('quanto-custa-catering-50-pessoas',
     'dicas',
     'Quanto custa um catering com food trucks para 50 pessoas?',
     'Calculadora e estimativas reais para te ajudar a planear o orçamento.',
     'https://images.unsplash.com/photo-1555244162-803834f70033?w=1400',
     'Em média entre 15€ e 25€ por convidado dependendo do tipo de truck.',
     3, 21),
    ('festivais-2025-o-que-ai-vem',
     'inspiracao',
     'Festivais 2025: o que aí vem',
     'A nossa selecção de festivais para experimentar este verão.',
     'https://images.unsplash.com/photo-1459749411175-04bf5292ceea?w=1400',
     'NOS Alive, Primavera Sound, MEO Sudoeste — onde vais comer melhor.',
     4, 30)
  ) as v(slug, cat_slug, title, excerpt, cover, body, minutes, days)
  join public.airfnb_blog_categories c on c.slug = v.cat_slug
on conflict (slug) do nothing;
;
