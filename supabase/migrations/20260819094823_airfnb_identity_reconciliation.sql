-- Forward-only reconciliation for the retired public demo identity.
--
-- This migration deliberately carries its production observations as
-- fail-closed preconditions. It is safe to run a second time only when the
-- exact identity is still absent and the known catalogue/editorial rows are
-- still present and detached.

begin;
set local statement_timeout = '30s';
set local lock_timeout = '5s';

do $schema_preconditions$
declare
  v_required_relations constant text[] := array[
    'auth.identities',
    'auth.mfa_factors',
    'auth.refresh_tokens',
    'auth.sessions',
    'auth.users',
    'public.airfnb_addresses',
    'public.airfnb_blog_authors',
    'public.airfnb_blog_posts',
    'public.airfnb_bookings',
    'public.airfnb_contact_requests',
    'public.airfnb_conversation_participants',
    'public.airfnb_event_requests',
    'public.airfnb_events',
    'public.airfnb_favorites',
    'public.airfnb_messages',
    'public.airfnb_notifications',
    'public.airfnb_organizer_reviews',
    'public.airfnb_partner_leads',
    'public.airfnb_platform_settings',
    'public.airfnb_profiles',
    'public.airfnb_proposals',
    'public.airfnb_request_invitations',
    'public.airfnb_reviews',
    'public.airfnb_trucks'
  ];
  v_missing_relations text[];
  v_column_drift text[];
  v_fk_drift text[];
begin
  select array_agg(required_relation order by required_relation)
    into v_missing_relations
    from unnest(v_required_relations) as required(required_relation)
   where not coalesce((
     select relation.relkind in ('r', 'p')
       from pg_catalog.pg_class as relation
      where relation.oid = pg_catalog.to_regclass(required_relation)
   ), false);

  if v_missing_relations is not null then
    raise exception 'identity reconciliation refused: required relations missing or not tables: %',
      array_to_string(v_missing_relations, ', ');
  end if;

  -- These columns are the preservation boundary plus the six nullable
  -- audit/history references established by the captured production check.
  select array_agg(
           format('%s.%s', expected.table_name, expected.column_name)
           order by expected.table_name, expected.column_name
         )
    into v_column_drift
    from (values
      ('airfnb_blog_authors', 'id',           'uuid', true),
      ('airfnb_blog_posts',   'author_id',    'uuid', false),
      ('airfnb_bookings',     'organizer_id', 'uuid', false),
      ('airfnb_contact_requests', 'handled_by', 'uuid', false),
      ('airfnb_conversation_participants', 'user_id', 'uuid', true),
      ('airfnb_messages',     'sender_id',    'uuid', false),
      ('airfnb_profiles',     'id',           'uuid', true),
      ('airfnb_proposals',    'prepared_by',  'uuid', false),
      ('airfnb_request_invitations', 'invited_by', 'uuid', false),
      ('airfnb_reviews',      'organizer_id', 'uuid', false),
      ('airfnb_trucks',       'owner_id',     'uuid', false)
    ) as expected(table_name, column_name, type_name, not_null)
   where not exists (
     select 1
       from pg_catalog.pg_attribute as attribute
       join pg_catalog.pg_class as relation
         on relation.oid = attribute.attrelid
       join pg_catalog.pg_namespace as namespace
         on namespace.oid = relation.relnamespace
      where namespace.nspname = 'public'
        and relation.relname = expected.table_name
        and relation.relkind in ('r', 'p')
        and attribute.attname = expected.column_name
        and attribute.attnum > 0
        and not attribute.attisdropped
        and attribute.atttypid = pg_catalog.to_regtype(expected.type_name)
        and attribute.attnotnull = expected.not_null
   );

  if v_column_drift is not null then
    raise exception 'identity reconciliation refused: expected column type/nullability drift: %',
      array_to_string(v_column_drift, ', ');
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_attribute as attribute
      join pg_catalog.pg_class as relation
        on relation.oid = attribute.attrelid
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = relation.relnamespace
     where namespace.nspname = 'auth'
       and relation.relname = 'users'
       and attribute.attname = 'id'
       and attribute.attnum > 0
       and not attribute.attisdropped
       and attribute.atttypid = 'uuid'::pg_catalog.regtype
       and attribute.attnotnull
  ) or not exists (
    select 1
      from pg_catalog.pg_attribute as attribute
      join pg_catalog.pg_class as relation
        on relation.oid = attribute.attrelid
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = relation.relnamespace
     where namespace.nspname = 'auth'
       and relation.relname = 'users'
       and attribute.attname = 'email'
       and attribute.attnum > 0
       and not attribute.attisdropped
  ) then
    raise exception 'identity reconciliation refused: auth.users id/email schema drift';
  end if;

  if exists (
    select 1
      from (values
        ('identities'),
        ('mfa_factors'),
        ('refresh_tokens'),
        ('sessions')
      ) as expected(table_name)
     where not exists (
       select 1
         from pg_catalog.pg_attribute as attribute
         join pg_catalog.pg_class as relation
           on relation.oid = attribute.attrelid
         join pg_catalog.pg_namespace as namespace
           on namespace.oid = relation.relnamespace
        where namespace.nspname = 'auth'
          and relation.relname = expected.table_name
          and attribute.attname = 'user_id'
          and attribute.attnum > 0
          and not attribute.attisdropped
     )
  ) then
    raise exception 'identity reconciliation refused: auth dependent user_id schema drift';
  end if;

  -- Fail if a new direct profile reference has appeared or a known one was
  -- removed. That prevents silently leaving a newly introduced privilege or
  -- ownership edge attached to the retired UUID.
  with expected(table_name, column_name) as (values
    ('airfnb_addresses', 'owner_id'),
    ('airfnb_blog_authors', 'id'),
    ('airfnb_bookings', 'organizer_id'),
    ('airfnb_contact_requests', 'handled_by'),
    ('airfnb_conversation_participants', 'user_id'),
    ('airfnb_event_requests', 'organizer_id'),
    ('airfnb_events', 'organizer_id'),
    ('airfnb_favorites', 'user_id'),
    ('airfnb_messages', 'sender_id'),
    ('airfnb_notifications', 'user_id'),
    ('airfnb_organizer_reviews', 'organizer_id'),
    ('airfnb_partner_leads', 'handled_by'),
    ('airfnb_platform_settings', 'updated_by'),
    ('airfnb_profiles', 'referred_by'),
    ('airfnb_proposals', 'prepared_by'),
    ('airfnb_request_invitations', 'invited_by'),
    ('airfnb_reviews', 'organizer_id'),
    ('airfnb_trucks', 'owner_id')
  ),
  actual as (
    select relation.relname as table_name,
           attribute.attname as column_name
      from pg_catalog.pg_constraint as constraint_row
      join pg_catalog.pg_class as relation
        on relation.oid = constraint_row.conrelid
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = relation.relnamespace
      join lateral unnest(constraint_row.conkey) as key_column(attnum)
        on true
      join pg_catalog.pg_attribute as attribute
        on attribute.attrelid = relation.oid
       and attribute.attnum = key_column.attnum
     where constraint_row.contype = 'f'
       and constraint_row.confrelid = 'public.airfnb_profiles'::pg_catalog.regclass
       and namespace.nspname = 'public'
  ),
  drift as (
    select 'missing:' || expected.table_name || '.' || expected.column_name as item
      from expected
      left join actual using (table_name, column_name)
     where actual.table_name is null
    union all
    select 'unexpected:' || actual.table_name || '.' || actual.column_name
      from actual
      left join expected using (table_name, column_name)
     where expected.table_name is null
  )
  select array_agg(item order by item)
    into v_fk_drift
    from drift;

  if v_fk_drift is not null then
    raise exception 'identity reconciliation refused: direct profile reference drift: %',
      array_to_string(v_fk_drift, ', ');
  end if;
end
$schema_preconditions$;

create or replace function public.airfnb_guard_profile_role()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_actor uuid := auth.uid();
  v_actor_is_privileged boolean := false;
  v_retired_seed constant uuid := '11111111-1111-1111-1111-111111111111';
begin
  if new.id = v_retired_seed then
    raise exception using
      errcode = '42501',
      message = 'retired demo identity cannot create or update a profile';
  end if;

  if tg_op = 'UPDATE' and new.role is not distinct from old.role then
    return new;
  end if;

  if new.role not in (
    'admin'::public.airfnb_user_role,
    'staff'::public.airfnb_user_role
  ) then
    return new;
  end if;

  -- Database-internal work has no JWT subject. An end-user subject must
  -- already have a trusted database-backed role; user metadata is never used.
  if v_actor is null then
    return new;
  end if;

  select exists (
    select 1
      from public.airfnb_profiles as profile
     where profile.id = v_actor
       and profile.role in (
         'admin'::public.airfnb_user_role,
         'staff'::public.airfnb_user_role
       )
  ) into v_actor_is_privileged;

  if not v_actor_is_privileged then
    raise exception using
      errcode = '42501',
      message = 'only an existing admin or staff member can assign a privileged role';
  end if;

  return new;
end
$function$;

revoke all on function public.airfnb_guard_profile_role()
  from public, anon, authenticated;

drop trigger if exists airfnb_profiles_guard_role on public.airfnb_profiles;
create trigger airfnb_profiles_guard_role
  before insert or update on public.airfnb_profiles
  for each row execute function public.airfnb_guard_profile_role();

do $identity_reconciliation$
declare
  v_seed_id constant uuid := '11111111-1111-1111-1111-111111111111';
  v_seed_email constant text := 'seed@airfnb.local';
  v_expected_service_slugs constant text[] := array[
    'bbq-kings',
    'creperia-pt',
    'divine-burguers',
    'el-mexicano',
    'gypsy-kitchen',
    'la-dolce-vita',
    'pizza-vesuvio',
    'portuguese-tradition',
    'sushi-zen',
    'taco-fiesta',
    'turkish-delights',
    'wok-and-roll'
  ];
  v_expected_post_slugs constant text[] := array[
    'casamentos-food-trucks-5-dicas',
    'como-organizar-evento-perfeito-food-trucks',
    'festivais-2025-o-que-ai-vem',
    'quanto-custa-catering-50-pessoas',
    'tendencias-gastronomicas-2025'
  ];
  v_observed_slugs text[];
  v_uuid_matches integer;
  v_email_matches integer;
  v_exact_matches integer;
  v_reference record;
  v_reference_count bigint;
  v_first_run boolean;
begin
  -- Serialize both representations before deciding whether this is the first
  -- application or a permitted second run.
  lock table auth.users in share row exclusive mode;

  perform 1
    from auth.users as auth_user
   where auth_user.id = v_seed_id
      or lower(auth_user.email) = lower(v_seed_email)
   for update;

  select count(*) filter (where id = v_seed_id),
         count(*) filter (where lower(email) = lower(v_seed_email)),
         count(*) filter (where id = v_seed_id and email = v_seed_email)
    into v_uuid_matches, v_email_matches, v_exact_matches
    from auth.users
   where id = v_seed_id
      or lower(email) = lower(v_seed_email);

  if v_exact_matches = 1 and v_uuid_matches = 1 and v_email_matches = 1 then
    v_first_run := true;
  elsif v_exact_matches = 0 and v_uuid_matches = 0 and v_email_matches = 0 then
    v_first_run := false;
  else
    raise exception 'identity reconciliation refused: retired UUID/email pairing drifted';
  end if;

  if v_first_run then
    perform 1
      from public.airfnb_profiles
     where id = v_seed_id
     for update;

    if (select count(*) from public.airfnb_profiles where id = v_seed_id) <> 1 then
      raise exception 'identity reconciliation refused: expected exactly one retired profile';
    end if;

    if (select count(*) from public.airfnb_blog_authors where id = v_seed_id) <> 1 then
      raise exception 'identity reconciliation refused: expected exactly one retired blog author';
    end if;

    select array_agg(slug order by slug)
      into v_observed_slugs
      from public.airfnb_trucks
     where owner_id = v_seed_id;

    if v_observed_slugs is distinct from v_expected_service_slugs then
      raise exception 'identity reconciliation refused: expected exactly the 12 observed catalogue services';
    end if;

    select array_agg(slug order by slug)
      into v_observed_slugs
      from public.airfnb_blog_posts
     where author_id = v_seed_id
       and status = 'published'::public.airfnb_post_status;

    if v_observed_slugs is distinct from v_expected_post_slugs
       or (select count(*) from public.airfnb_blog_posts where author_id = v_seed_id) <> 5 then
      raise exception 'identity reconciliation refused: expected exactly the 5 observed published articles';
    end if;

    -- Detach retained public content and every nullable audit, referral, and
    -- operator reference. Non-retained caller-owned rows with CASCADE FKs are
    -- removed by the profile deletion; no unrelated identity is touched.
    update public.airfnb_trucks
       set owner_id = null
     where owner_id = v_seed_id;

    update public.airfnb_blog_posts
       set author_id = null
     where author_id = v_seed_id;

    update public.airfnb_bookings
       set organizer_id = null
     where organizer_id = v_seed_id;
    update public.airfnb_messages
       set sender_id = null
     where sender_id = v_seed_id;
    update public.airfnb_reviews
       set organizer_id = null
     where organizer_id = v_seed_id;
    update public.airfnb_proposals
       set prepared_by = null
     where prepared_by = v_seed_id;
    update public.airfnb_contact_requests
       set handled_by = null
     where handled_by = v_seed_id;
    update public.airfnb_request_invitations
       set invited_by = null
     where invited_by = v_seed_id;
    update public.airfnb_partner_leads
       set handled_by = null
     where handled_by = v_seed_id;
    update public.airfnb_platform_settings
       set updated_by = null
     where updated_by = v_seed_id;
    update public.airfnb_profiles
       set referred_by = null
     where referred_by = v_seed_id;
    delete from public.airfnb_conversation_participants
     where user_id = v_seed_id;

    delete from auth.users
     where id = v_seed_id
       and email = v_seed_email;

    if not found then
      raise exception 'identity reconciliation refused: exact retired identity disappeared during cleanup';
    end if;
  end if;

  -- First-run and second-run postconditions are identical. The known public
  -- rows must survive, while every authorization/ownership edge is absent.
  if exists (
    select 1
      from auth.users
     where id = v_seed_id
        or lower(email) = lower(v_seed_email)
  ) then
    raise exception 'identity reconciliation failed: retired auth identity remains';
  end if;

  if (select array_agg(slug order by slug)
        from public.airfnb_trucks
       where slug = any(v_expected_service_slugs)
         and owner_id is null) is distinct from v_expected_service_slugs then
    raise exception 'identity reconciliation failed: the 12 catalogue services were not preserved and detached';
  end if;

  if (select array_agg(slug order by slug)
        from public.airfnb_blog_posts
       where slug = any(v_expected_post_slugs)
         and author_id is null
         and status = 'published'::public.airfnb_post_status)
       is distinct from v_expected_post_slugs then
    raise exception 'identity reconciliation failed: the 5 published articles were not preserved and detached';
  end if;

  if exists (select 1 from public.airfnb_blog_authors where id = v_seed_id) then
    raise exception 'identity reconciliation failed: retired blog author remains';
  end if;

  for v_reference in
    select * from (values
      ('airfnb_addresses', 'owner_id'),
      ('airfnb_blog_authors', 'id'),
      ('airfnb_bookings', 'organizer_id'),
      ('airfnb_contact_requests', 'handled_by'),
      ('airfnb_conversation_participants', 'user_id'),
      ('airfnb_event_requests', 'organizer_id'),
      ('airfnb_events', 'organizer_id'),
      ('airfnb_favorites', 'user_id'),
      ('airfnb_messages', 'sender_id'),
      ('airfnb_notifications', 'user_id'),
      ('airfnb_organizer_reviews', 'organizer_id'),
      ('airfnb_partner_leads', 'handled_by'),
      ('airfnb_platform_settings', 'updated_by'),
      ('airfnb_profiles', 'id'),
      ('airfnb_profiles', 'referred_by'),
      ('airfnb_proposals', 'prepared_by'),
      ('airfnb_request_invitations', 'invited_by'),
      ('airfnb_reviews', 'organizer_id'),
      ('airfnb_trucks', 'owner_id')
    ) as reference(table_name, column_name)
  loop
    execute format(
      'select count(*) from public.%I where %I = $1',
      v_reference.table_name,
      v_reference.column_name
    ) into v_reference_count using v_seed_id;

    if v_reference_count <> 0 then
      raise exception 'identity reconciliation failed: retired UUID remains in public.%.%',
        v_reference.table_name, v_reference.column_name;
    end if;
  end loop;

  if exists (select 1 from public.airfnb_blog_posts where author_id = v_seed_id) then
    raise exception 'identity reconciliation failed: retired UUID remains in blog authorship';
  end if;

  -- Catch non-FK audit columns and any future UUID column that the exact FK
  -- inventory cannot see. Identifiers come from pg_catalog and are still
  -- qualified/escaped with %I before execution.
  for v_reference in
    select namespace.nspname as schema_name,
           relation.relname as table_name,
           attribute.attname as column_name
      from pg_catalog.pg_attribute as attribute
      join pg_catalog.pg_class as relation
        on relation.oid = attribute.attrelid
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = relation.relnamespace
     where namespace.nspname = 'public'
       and relation.relkind in ('r', 'p')
       and attribute.attnum > 0
       and not attribute.attisdropped
       and attribute.atttypid = 'uuid'::pg_catalog.regtype
     order by relation.relname, attribute.attnum
  loop
    execute format(
      'select count(*) from %I.%I where %I = $1',
      v_reference.schema_name,
      v_reference.table_name,
      v_reference.column_name
    ) into v_reference_count using v_seed_id;

    if v_reference_count <> 0 then
      raise exception 'identity reconciliation failed: retired UUID remains in %.%.%',
        v_reference.schema_name,
        v_reference.table_name,
        v_reference.column_name;
    end if;
  end loop;

  for v_reference in
    select * from (values
      ('identities'),
      ('mfa_factors'),
      ('refresh_tokens'),
      ('sessions')
    ) as reference(table_name)
  loop
    execute format(
      'select count(*) from auth.%I where user_id::text = $1',
      v_reference.table_name
    ) into v_reference_count using v_seed_id::text;

    if v_reference_count <> 0 then
      raise exception 'identity reconciliation failed: retired auth dependency remains in auth.%',
        v_reference.table_name;
    end if;
  end loop;
end
$identity_reconciliation$;

commit;
