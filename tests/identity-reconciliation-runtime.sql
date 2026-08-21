\set ON_ERROR_STOP on

\if :{?identity_runtime_phase}
\else
  \echo identity_runtime_phase is required
  \quit 3
\endif
\if :{?identity_runtime_database}
\else
  \echo identity_runtime_database is required
  \quit 3
\endif

select (
  current_database() = :'identity_runtime_database'
  and current_database() ~ '^fb_tailor_identity_runtime_[0-9]+_[0-9]+$'
  and :'identity_runtime_phase' in (
    'setup_drift',
    'assert_failed_atomicity_and_prepare_good',
    'assert_good',
    'role_paths'
  )
) as identity_runtime_target_is_safe
\gset
\if :identity_runtime_target_is_safe
\else
  \echo refusing identity reconciliation runtime work outside the exact driver scratch database
  \quit 3
\endif

select :'identity_runtime_phase' = 'setup_drift' as run_setup_drift
\gset
\if :run_setup_drift
  \echo === IDENTITY_RECONCILIATION_SETUP_11_OF_12_DRIFT ===

  do $initial_state$
  begin
    if exists (
      select 1 from auth.users
       where id in (
         '11111111-1111-1111-1111-111111111111'::uuid,
         '22222222-2222-2222-2222-222222222222'::uuid,
         '33333333-3333-3333-3333-333333333333'::uuid,
         '44444444-4444-4444-4444-444444444444'::uuid,
         '55555555-5555-5555-5555-555555555555'::uuid,
         '66666666-6666-6666-6666-666666666666'::uuid,
         '77777777-7777-7777-7777-777777777777'::uuid,
         '88888888-8888-8888-8888-888888888888'::uuid,
         '99999999-9999-9999-9999-999999999999'::uuid
       ) or lower(email) = lower('seed@airfnb.local')
    ) then
      raise exception 'runtime setup refused: an identity fixture already exists';
    end if;

    if to_regnamespace('identity_runtime') is not null
       or to_regclass('auth.sessions') is not null
       or to_regclass('auth.refresh_tokens') is not null
       or to_regclass('auth.identities') is not null
       or to_regclass('auth.mfa_factors') is not null then
      raise exception 'runtime setup refused: scratch fixtures already exist';
    end if;

    if (select count(*) from public.airfnb_trucks
         where owner_id is null and slug in (
           'bbq-kings', 'creperia-pt', 'divine-burguers', 'el-mexicano',
           'gypsy-kitchen', 'la-dolce-vita', 'pizza-vesuvio',
           'portuguese-tradition', 'sushi-zen', 'taco-fiesta',
           'turkish-delights', 'wok-and-roll'
         )) <> 12
       or (select count(*) from public.airfnb_blog_posts
            where author_id is null and status = 'published' and slug in (
              'casamentos-food-trucks-5-dicas',
              'como-organizar-evento-perfeito-food-trucks',
              'festivais-2025-o-que-ai-vem',
              'quanto-custa-catering-50-pessoas',
              'tendencias-gastronomicas-2025'
            )) <> 5 then
      raise exception 'runtime setup refused: source 12/5 detached baseline is absent';
    end if;

    if to_regprocedure('public.airfnb_guard_profile_role()') is null
       or not exists (
         select 1 from pg_catalog.pg_trigger
          where tgrelid = 'public.airfnb_profiles'::regclass
            and tgname = 'airfnb_profiles_guard_role'
            and not tgisinternal
       ) then
      raise exception 'runtime setup refused: predecessor profile guard is absent';
    end if;
  end
  $initial_state$;

  drop trigger airfnb_profiles_guard_role on public.airfnb_profiles;
  drop function public.airfnb_guard_profile_role();
  create schema identity_runtime;
  create table identity_runtime.baseline (key text primary key, value text not null);

  create table auth.sessions (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade
  );
  create table auth.refresh_tokens (
    id bigint generated always as identity primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    token text not null
  );
  create table auth.identities (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade
  );
  create table auth.mfa_factors (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade
  );

  grant usage on schema public, auth to authenticated;
  grant select, insert, update, delete on public.airfnb_profiles to authenticated;

  insert into auth.users (
    id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data
  ) values
    ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'seed@airfnb.local', '{}', '{"full_name":"Air F&B Seed"}'),
    ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'organizer-runtime@example.invalid', '{}', '{}'),
    ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner-runtime@example.invalid', '{}', '{}'),
    ('44444444-4444-4444-4444-444444444444', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin-runtime@example.invalid', '{}', '{}'),
    ('55555555-5555-5555-5555-555555555555', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'staff-runtime@example.invalid', '{}', '{}'),
    ('66666666-6666-6666-6666-666666666666', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin-target-runtime@example.invalid', '{}', '{}'),
    ('77777777-7777-7777-7777-777777777777', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'recreate-runtime@example.invalid', '{}', '{}'),
    ('88888888-8888-8888-8888-888888888888', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'staff-target-runtime@example.invalid', '{}', '{}'),
    ('99999999-9999-9999-9999-999999999999', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'unrelated-runtime@example.invalid', '{}', '{}');

  update public.airfnb_profiles set role = 'admin'
   where id = '11111111-1111-1111-1111-111111111111';
  update public.airfnb_profiles set role = 'owner'
   where id = '33333333-3333-3333-3333-333333333333';
  update public.airfnb_profiles set role = 'admin'
   where id = '44444444-4444-4444-4444-444444444444';
  update public.airfnb_profiles set role = 'staff'
   where id = '55555555-5555-5555-5555-555555555555';

  -- Deliberately reconstruct eleven owners. The candidate reaches guard DDL
  -- before failing its exact twelve-service precondition.
  update public.airfnb_trucks
     set owner_id = '11111111-1111-1111-1111-111111111111'
   where slug in (
     'bbq-kings', 'creperia-pt', 'divine-burguers', 'el-mexicano',
     'gypsy-kitchen', 'la-dolce-vita', 'pizza-vesuvio',
     'portuguese-tradition', 'sushi-zen', 'taco-fiesta', 'turkish-delights'
   );
  insert into public.airfnb_blog_authors(id, bio)
  values ('11111111-1111-1111-1111-111111111111', 'runtime harness seed author');
  update public.airfnb_blog_posts
     set author_id = '11111111-1111-1111-1111-111111111111'
   where slug in (
     'casamentos-food-trucks-5-dicas',
     'como-organizar-evento-perfeito-food-trucks',
     'festivais-2025-o-que-ai-vem',
     'quanto-custa-catering-50-pessoas',
     'tendencias-gastronomicas-2025'
   );

  insert into auth.sessions(id, user_id) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', '11111111-1111-1111-1111-111111111111'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', '99999999-9999-9999-9999-999999999999');
  insert into auth.refresh_tokens(user_id, token) values
    ('11111111-1111-1111-1111-111111111111', 'retired-runtime-refresh'),
    ('99999999-9999-9999-9999-999999999999', 'unrelated-runtime-refresh');
  insert into auth.identities(id, user_id) values
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', '11111111-1111-1111-1111-111111111111'),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2', '99999999-9999-9999-9999-999999999999');
  insert into auth.mfa_factors(id, user_id) values
    ('cccccccc-cccc-cccc-cccc-ccccccccccc1', '11111111-1111-1111-1111-111111111111'),
    ('cccccccc-cccc-cccc-cccc-ccccccccccc2', '99999999-9999-9999-9999-999999999999');
  insert into public.airfnb_trucks(owner_id, slug, name) values
    ('99999999-9999-9999-9999-999999999999', 'identity-runtime-unrelated-service', 'Unrelated runtime service');
  insert into public.airfnb_blog_authors(id, bio) values
    ('99999999-9999-9999-9999-999999999999', 'Unrelated runtime author');
  insert into public.airfnb_blog_posts(author_id, slug, title, status) values
    ('99999999-9999-9999-9999-999999999999', 'identity-runtime-unrelated-article', 'Unrelated runtime article', 'published');

  insert into identity_runtime.baseline(key, value)
  select 'drift_data', md5(concat_ws('|',
    (select string_agg(to_jsonb(truck)::text, E'\n' order by slug)
       from public.airfnb_trucks as truck where slug in (
         'bbq-kings', 'creperia-pt', 'divine-burguers', 'el-mexicano',
         'gypsy-kitchen', 'la-dolce-vita', 'pizza-vesuvio',
         'portuguese-tradition', 'sushi-zen', 'taco-fiesta',
         'turkish-delights', 'wok-and-roll', 'identity-runtime-unrelated-service'
       )),
    (select string_agg(to_jsonb(post)::text, E'\n' order by slug)
       from public.airfnb_blog_posts as post where slug in (
         'casamentos-food-trucks-5-dicas',
         'como-organizar-evento-perfeito-food-trucks',
         'festivais-2025-o-que-ai-vem',
         'quanto-custa-catering-50-pessoas',
         'tendencias-gastronomicas-2025', 'identity-runtime-unrelated-article'
       )),
    (select string_agg(to_jsonb(auth_user)::text, E'\n' order by id)
       from auth.users as auth_user where id in (
         '11111111-1111-1111-1111-111111111111',
         '99999999-9999-9999-9999-999999999999'
       ))
  ));
  insert into identity_runtime.baseline(key, value)
  select 'service_content', md5(string_agg(
    (to_jsonb(truck) - 'owner_id' - 'updated_at')::text, E'\n' order by slug
  )) from public.airfnb_trucks as truck where slug in (
    'bbq-kings', 'creperia-pt', 'divine-burguers', 'el-mexicano',
    'gypsy-kitchen', 'la-dolce-vita', 'pizza-vesuvio',
    'portuguese-tradition', 'sushi-zen', 'taco-fiesta',
    'turkish-delights', 'wok-and-roll'
  );
  insert into identity_runtime.baseline(key, value)
  select 'article_content', md5(string_agg(
    (to_jsonb(post) - 'author_id' - 'updated_at')::text, E'\n' order by slug
  )) from public.airfnb_blog_posts as post where slug in (
    'casamentos-food-trucks-5-dicas',
    'como-organizar-evento-perfeito-food-trucks',
    'festivais-2025-o-que-ai-vem',
    'quanto-custa-catering-50-pessoas',
    'tendencias-gastronomicas-2025'
  );

  do $setup_assertions$
  begin
    if to_regprocedure('public.airfnb_guard_profile_role()') is not null
       or exists (
         select 1 from pg_catalog.pg_trigger
          where tgrelid = 'public.airfnb_profiles'::regclass
            and tgname = 'airfnb_profiles_guard_role' and not tgisinternal
       )
       or (select count(*) from public.airfnb_trucks
            where owner_id = '11111111-1111-1111-1111-111111111111') <> 11
       or (select atttypid from pg_catalog.pg_attribute
            where attrelid = 'auth.refresh_tokens'::regclass
              and attname = 'user_id' and attnum > 0 and not attisdropped)
          <> 'uuid'::regtype then
      raise exception 'runtime setup did not establish exact guard-absent 11-of-12 UUID fixtures';
    end if;
  end
  $setup_assertions$;

  select 'IDENTITY_RECONCILIATION_DRIFT_READY' as marker,
         11 as owned_services, 5 as authored_articles;
\endif

select :'identity_runtime_phase' = 'assert_failed_atomicity_and_prepare_good'
  as run_failed_atomicity_assertion
\gset
\if :run_failed_atomicity_assertion
  \echo === IDENTITY_RECONCILIATION_ASSERT_FAILED_ATOMICITY ===

  do $failed_atomicity$
  declare
    expected_drift_fingerprint text;
    actual_drift_fingerprint text;
  begin
    if to_regclass('identity_runtime.baseline') is null then
      raise exception 'runtime atomicity assertion refused: driver baseline is absent';
    end if;
    select value into expected_drift_fingerprint
      from identity_runtime.baseline where key = 'drift_data';
    select md5(concat_ws('|',
      (select string_agg(to_jsonb(truck)::text, E'\n' order by slug)
         from public.airfnb_trucks as truck where slug in (
           'bbq-kings', 'creperia-pt', 'divine-burguers', 'el-mexicano',
           'gypsy-kitchen', 'la-dolce-vita', 'pizza-vesuvio',
           'portuguese-tradition', 'sushi-zen', 'taco-fiesta',
           'turkish-delights', 'wok-and-roll', 'identity-runtime-unrelated-service'
         )),
      (select string_agg(to_jsonb(post)::text, E'\n' order by slug)
         from public.airfnb_blog_posts as post where slug in (
           'casamentos-food-trucks-5-dicas',
           'como-organizar-evento-perfeito-food-trucks',
           'festivais-2025-o-que-ai-vem',
           'quanto-custa-catering-50-pessoas',
           'tendencias-gastronomicas-2025', 'identity-runtime-unrelated-article'
         )),
      (select string_agg(to_jsonb(auth_user)::text, E'\n' order by id)
         from auth.users as auth_user where id in (
           '11111111-1111-1111-1111-111111111111',
           '99999999-9999-9999-9999-999999999999'
         ))
    )) into actual_drift_fingerprint;

    if actual_drift_fingerprint is distinct from expected_drift_fingerprint
       or to_regprocedure('public.airfnb_guard_profile_role()') is not null
       or exists (
         select 1 from pg_catalog.pg_trigger
          where tgrelid = 'public.airfnb_profiles'::regclass
            and tgname = 'airfnb_profiles_guard_role' and not tgisinternal
       )
       or (select count(*) from auth.users
            where id = '11111111-1111-1111-1111-111111111111'
              and email = 'seed@airfnb.local') <> 1
       or (select count(*) from public.airfnb_profiles
            where id = '11111111-1111-1111-1111-111111111111') <> 1
       or (select count(*) from public.airfnb_blog_authors
            where id = '11111111-1111-1111-1111-111111111111') <> 1
       or (select count(*) from public.airfnb_trucks
            where owner_id = '11111111-1111-1111-1111-111111111111') <> 11
       or (select count(*) from public.airfnb_blog_posts
            where author_id = '11111111-1111-1111-1111-111111111111') <> 5
       or (select count(*) from auth.sessions
            where user_id = '11111111-1111-1111-1111-111111111111') <> 1
       or (select count(*) from auth.refresh_tokens
            where user_id = '11111111-1111-1111-1111-111111111111') <> 1
       or (select count(*) from auth.identities
            where user_id = '11111111-1111-1111-1111-111111111111') <> 1
       or (select count(*) from auth.mfa_factors
            where user_id = '11111111-1111-1111-1111-111111111111') <> 1 then
      raise exception 'runtime atomicity assertion found candidate-owned guard or data changes';
    end if;
  end
  $failed_atomicity$;

  update public.airfnb_trucks
     set owner_id = '11111111-1111-1111-1111-111111111111'
   where slug = 'wok-and-roll' and owner_id is null;
  do $good_state$
  begin
    if (select count(*) from public.airfnb_trucks
         where owner_id = '11111111-1111-1111-1111-111111111111') <> 12 then
      raise exception 'runtime driver failed to repair exactly the twelfth service';
    end if;
  end
  $good_state$;
  select 'IDENTITY_RECONCILIATION_FAILED_APPLY_ROLLED_BACK' as marker,
         12 as prepared_owned_services;
\endif

select :'identity_runtime_phase' = 'assert_good' as run_good_assertion
\gset
\if :run_good_assertion
  \echo === IDENTITY_RECONCILIATION_ASSERT_GOOD_APPLY ===

  do $good_assertions$
  declare
    expected_service_fingerprint text;
    expected_article_fingerprint text;
    actual_service_fingerprint text;
    actual_article_fingerprint text;
    uuid_column record;
    matches bigint;
  begin
    if to_regclass('identity_runtime.baseline') is null then
      raise exception 'runtime good assertion refused: driver baseline is absent';
    end if;
    select value into expected_service_fingerprint
      from identity_runtime.baseline where key = 'service_content';
    select value into expected_article_fingerprint
      from identity_runtime.baseline where key = 'article_content';
    select md5(string_agg(
      (to_jsonb(truck) - 'owner_id' - 'updated_at')::text,
      E'\n' order by slug
    ))
      into actual_service_fingerprint
      from public.airfnb_trucks as truck where slug in (
        'bbq-kings', 'creperia-pt', 'divine-burguers', 'el-mexicano',
        'gypsy-kitchen', 'la-dolce-vita', 'pizza-vesuvio',
        'portuguese-tradition', 'sushi-zen', 'taco-fiesta',
        'turkish-delights', 'wok-and-roll'
      );
    select md5(string_agg(
      (to_jsonb(post) - 'author_id' - 'updated_at')::text,
      E'\n' order by slug
    ))
      into actual_article_fingerprint
      from public.airfnb_blog_posts as post where slug in (
        'casamentos-food-trucks-5-dicas',
        'como-organizar-evento-perfeito-food-trucks',
        'festivais-2025-o-que-ai-vem',
        'quanto-custa-catering-50-pessoas',
        'tendencias-gastronomicas-2025'
      );

    if exists (
      select 1 from auth.users
       where id = '11111111-1111-1111-1111-111111111111'
          or lower(email) = lower('seed@airfnb.local')
    ) or exists (
      select 1 from public.airfnb_profiles
       where id = '11111111-1111-1111-1111-111111111111'
    ) or exists (
      select 1 from public.airfnb_blog_authors
       where id = '11111111-1111-1111-1111-111111111111'
    ) then
      raise exception 'runtime good assertion found retired identity/profile/author';
    end if;
    if exists (select 1 from auth.sessions where user_id = '11111111-1111-1111-1111-111111111111')
       or exists (select 1 from auth.refresh_tokens where user_id = '11111111-1111-1111-1111-111111111111')
       or exists (select 1 from auth.identities where user_id = '11111111-1111-1111-1111-111111111111')
       or exists (select 1 from auth.mfa_factors where user_id = '11111111-1111-1111-1111-111111111111') then
      raise exception 'runtime good assertion found retired auth dependencies';
    end if;
    if (select count(*) from public.airfnb_trucks
         where owner_id is null and slug in (
           'bbq-kings', 'creperia-pt', 'divine-burguers', 'el-mexicano',
           'gypsy-kitchen', 'la-dolce-vita', 'pizza-vesuvio',
           'portuguese-tradition', 'sushi-zen', 'taco-fiesta',
           'turkish-delights', 'wok-and-roll'
         )) <> 12
       or actual_service_fingerprint is distinct from expected_service_fingerprint
       or (select count(*) from public.airfnb_blog_posts
            where author_id is null and status = 'published' and slug in (
              'casamentos-food-trucks-5-dicas',
              'como-organizar-evento-perfeito-food-trucks',
              'festivais-2025-o-que-ai-vem',
              'quanto-custa-catering-50-pessoas',
              'tendencias-gastronomicas-2025'
            )) <> 5
       or actual_article_fingerprint is distinct from expected_article_fingerprint then
      raise exception 'runtime good assertion failed exact 12/5 preservation';
    end if;

    for uuid_column in
      select namespace.nspname as schema_name,
             relation.relname as table_name,
             attribute.attname as column_name
        from pg_catalog.pg_attribute as attribute
        join pg_catalog.pg_class as relation on relation.oid = attribute.attrelid
        join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
       where namespace.nspname = 'public'
         and relation.relkind in ('r', 'p')
         and attribute.attnum > 0 and not attribute.attisdropped
         and attribute.atttypid = 'uuid'::regtype
    loop
      execute format(
        'select count(*) from %I.%I where %I = $1',
        uuid_column.schema_name, uuid_column.table_name, uuid_column.column_name
      ) into matches using '11111111-1111-1111-1111-111111111111'::uuid;
      if matches <> 0 then
        raise exception 'runtime good assertion found retired UUID in %.%.%',
          uuid_column.schema_name, uuid_column.table_name, uuid_column.column_name;
      end if;
    end loop;

    if not exists (
      select 1 from auth.users
       where id = '99999999-9999-9999-9999-999999999999'
         and email = 'unrelated-runtime@example.invalid'
    ) or not exists (
      select 1 from public.airfnb_profiles
       where id = '99999999-9999-9999-9999-999999999999'
    ) or not exists (
      select 1 from auth.sessions where user_id = '99999999-9999-9999-9999-999999999999'
    ) or not exists (
      select 1 from auth.refresh_tokens
       where user_id = '99999999-9999-9999-9999-999999999999'
         and token = 'unrelated-runtime-refresh'
    ) or not exists (
      select 1 from auth.identities where user_id = '99999999-9999-9999-9999-999999999999'
    ) or not exists (
      select 1 from auth.mfa_factors where user_id = '99999999-9999-9999-9999-999999999999'
    ) or not exists (
      select 1 from public.airfnb_trucks
       where owner_id = '99999999-9999-9999-9999-999999999999'
         and slug = 'identity-runtime-unrelated-service'
         and name = 'Unrelated runtime service'
    ) or not exists (
      select 1 from public.airfnb_blog_authors
       where id = '99999999-9999-9999-9999-999999999999'
         and bio = 'Unrelated runtime author'
    ) or not exists (
      select 1 from public.airfnb_blog_posts
       where author_id = '99999999-9999-9999-9999-999999999999'
         and slug = 'identity-runtime-unrelated-article'
         and title = 'Unrelated runtime article' and status = 'published'
    ) then
      raise exception 'runtime good assertion found unrelated fixture drift';
    end if;
    if to_regprocedure('public.airfnb_guard_profile_role()') is null
       or not exists (
         select 1 from pg_catalog.pg_trigger
          where tgrelid = 'public.airfnb_profiles'::regclass
            and tgname = 'airfnb_profiles_guard_role'
            and not tgisinternal and tgenabled <> 'D'
       )
       or has_function_privilege('anon', 'public.airfnb_guard_profile_role()', 'EXECUTE')
       or has_function_privilege('authenticated', 'public.airfnb_guard_profile_role()', 'EXECUTE') then
      raise exception 'runtime good assertion found guard or privilege drift';
    end if;
  end
  $good_assertions$;

  select 'IDENTITY_RECONCILIATION_GOOD_APPLY_PASS' as marker,
         12 as detached_services, 5 as detached_articles;
\endif

select :'identity_runtime_phase' = 'role_paths' as run_role_paths
\gset
\if :run_role_paths
  \echo === IDENTITY_RECONCILIATION_ROLE_PATHS ===

  create function pg_temp.expect_42501(p_sql text, p_message_fragment text)
  returns text language plpgsql as $expectation$
  declare
    error_message text;
  begin
    begin
      execute p_sql;
    exception when sqlstate '42501' then
      get stacked diagnostics error_message = message_text;
      if position(p_message_fragment in error_message) = 0 then
        raise exception 'runtime role probe received an unexpected 42501: %', error_message;
      end if;
      return '42501:' || error_message;
    end;
    raise exception 'runtime role attack unexpectedly succeeded: %', p_sql;
  end
  $expectation$;

  set role authenticated;
  select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
  update public.airfnb_profiles set full_name = 'ordinary organizer edit'
   where id = '22222222-2222-2222-2222-222222222222';
  select pg_temp.expect_42501(
    $attack$update public.airfnb_profiles set role = 'admin'
             where id = '22222222-2222-2222-2222-222222222222'$attack$,
    'only an existing admin or staff member'
  ) as organizer_admin_blocked;
  update public.airfnb_profiles set role = 'owner'
   where id = '22222222-2222-2222-2222-222222222222';
  select pg_temp.expect_42501(
    $attack$update public.airfnb_profiles set role = 'staff'
             where id = '22222222-2222-2222-2222-222222222222'$attack$,
    'only an existing admin or staff member'
  ) as owner_staff_blocked;
  update public.airfnb_profiles set role = 'organizer'
   where id = '22222222-2222-2222-2222-222222222222';

  select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
  update public.airfnb_profiles set display_name = 'ordinary owner edit', role = 'organizer'
   where id = '33333333-3333-3333-3333-333333333333';
  update public.airfnb_profiles set role = 'owner'
   where id = '33333333-3333-3333-3333-333333333333';
  select pg_temp.expect_42501(
    $attack$update public.airfnb_profiles set role = 'admin'
             where id = '33333333-3333-3333-3333-333333333333'$attack$,
    'only an existing admin or staff member'
  ) as owner_admin_blocked;

  select set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-777777777777', false);
  delete from public.airfnb_profiles
   where id = '77777777-7777-7777-7777-777777777777';
  select pg_temp.expect_42501(
    $attack$insert into public.airfnb_profiles(id, role)
             values ('77777777-7777-7777-7777-777777777777', 'admin')$attack$,
    'only an existing admin or staff member'
  ) as recreated_admin_blocked;
  insert into public.airfnb_profiles(id, role, full_name) values
    ('77777777-7777-7777-7777-777777777777', 'owner', 'legitimate recreated owner');

  select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
  select pg_temp.expect_42501(
    $attack$insert into public.airfnb_profiles(id, role)
             values ('11111111-1111-1111-1111-111111111111', 'organizer')$attack$,
    'retired demo identity'
  ) as retired_profile_recreation_blocked;
  select set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', false);
  update public.airfnb_profiles set role = 'admin', full_name = 'admin-managed target'
   where id = '66666666-6666-6666-6666-666666666666';
  select set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-555555555555', false);
  update public.airfnb_profiles set role = 'staff', full_name = 'staff-managed target'
   where id = '88888888-8888-8888-8888-888888888888';
  reset role;

  do $role_assertions$
  begin
    if (select role from public.airfnb_profiles
         where id = '22222222-2222-2222-2222-222222222222') <> 'organizer'
       or (select full_name from public.airfnb_profiles
            where id = '22222222-2222-2222-2222-222222222222')
          is distinct from 'ordinary organizer edit'
       or (select role from public.airfnb_profiles
            where id = '33333333-3333-3333-3333-333333333333') <> 'owner'
       or (select display_name from public.airfnb_profiles
            where id = '33333333-3333-3333-3333-333333333333')
          is distinct from 'ordinary owner edit'
       or (select role from public.airfnb_profiles
            where id = '77777777-7777-7777-7777-777777777777') <> 'owner'
       or (select role from public.airfnb_profiles
            where id = '66666666-6666-6666-6666-666666666666') <> 'admin'
       or (select role from public.airfnb_profiles
            where id = '88888888-8888-8888-8888-888888888888') <> 'staff'
       or has_function_privilege('anon', 'public.airfnb_guard_profile_role()', 'EXECUTE')
       or has_function_privilege('authenticated', 'public.airfnb_guard_profile_role()', 'EXECUTE') then
      raise exception 'runtime role-path assertion failed';
    end if;
  end
  $role_assertions$;
  select 'IDENTITY_RECONCILIATION_ROLE_PATHS_PASS' as marker,
         'admin' as admin_managed_role, 'staff' as staff_managed_role;
\endif
