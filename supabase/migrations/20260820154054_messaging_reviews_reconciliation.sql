-- Atomic forward reconciliation for messaging and both review directions.
-- The source database for this migration is fingerprinted and immutable; the
-- companion driver applies this file only to driver-owned disposable clones.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- Lock every relation read by a precondition or changed below. This makes the
-- data/ACL snapshot and the resulting state one bounded atomic decision.
lock table
  public.airfnb_profiles,
  public.airfnb_trucks,
  public.airfnb_bookings,
  public.airfnb_booking_trucks,
  public.airfnb_conversations,
  public.airfnb_conversation_participants,
  public.airfnb_messages,
  public.airfnb_reviews,
  public.airfnb_organizer_reviews
in access exclusive mode;

create temporary table messaging_reconciliation_service_acl (
  relation_name text not null,
  acl_item text not null,
  primary key (relation_name, acl_item)
) on commit drop;

insert into messaging_reconciliation_service_acl (relation_name, acl_item)
select c.relname, acl_item::text
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  cross join lateral unnest(coalesce(c.relacl, '{}'::aclitem[])) acl_item
 where n.nspname = 'public'
   and c.relname in (
     'airfnb_conversations',
     'airfnb_conversation_participants',
     'airfnb_messages',
     'airfnb_reviews',
     'airfnb_organizer_reviews'
   )
   and acl_item::text like 'service_role=%';

create temporary table messaging_reconciliation_accept_snapshot (
  body_hash text not null,
  function_acl text,
  function_owner oid not null
) on commit drop;

insert into messaging_reconciliation_accept_snapshot
select md5(p.prosrc), p.proacl::text, p.proowner
  from pg_catalog.pg_proc p
 where p.oid = 'public.airfnb_accept_application(uuid)'::regprocedure;

do $preflight$
declare
  v_owner oid := (select oid from pg_catalog.pg_roles where rolname = current_user);
  v_reconciled boolean := to_regprocedure('public.airfnb_mark_conversation_read(uuid)') is not null;
  v_actual text;
  v_expected text;
  v_count bigint;
  v_relation text;
begin
  if v_owner is null then
    raise exception 'messaging reconciliation: current owner role is missing';
  end if;

  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'anon')
     or not exists (select 1 from pg_catalog.pg_roles where rolname = 'authenticated')
     or not exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    raise exception 'messaging reconciliation: required API roles are missing';
  end if;

  if (select count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'auth' and p.proname = 'uid') <> 1
     or not exists (
       select 1
         from pg_catalog.pg_proc p
        where p.oid = 'auth.uid()'::regprocedure
          and p.proowner = v_owner
          and p.prorettype = 'uuid'::regtype
          and p.provolatile = 's'
          and not p.prosecdef
          and md5(p.prosrc) = '67c85defb75e29433616a91191091b50'
     ) then
    raise exception 'messaging reconciliation: auth.uid identity contract differs';
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_proc p
     where p.oid = 'public.airfnb_is_admin()'::regprocedure
       and p.proowner = v_owner
       and p.prorettype = 'boolean'::regtype
       and p.provolatile = 's'
       and p.prosecdef
       and md5(p.prosrc) = 'aa950c573de3ffe4835f7851c09a0631'
  ) then
    raise exception 'messaging reconciliation: admin identity contract differs';
  end if;

  foreach v_relation in array array[
    'airfnb_profiles', 'airfnb_trucks', 'airfnb_bookings',
    'airfnb_booking_trucks', 'airfnb_conversations',
    'airfnb_conversation_participants', 'airfnb_messages',
    'airfnb_reviews', 'airfnb_organizer_reviews'
  ] loop
    if not exists (
      select 1
        from pg_catalog.pg_class c
        join pg_catalog.pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public'
         and c.relname = v_relation
         and c.relkind = 'r'
         and c.relowner = v_owner
         and c.relrowsecurity
         and not c.relforcerowsecurity
    ) then
      raise exception 'messaging reconciliation: table owner/RLS precondition differs for %', v_relation;
    end if;
  end loop;

  select string_agg(a.attname || ':' || pg_catalog.format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull, ',' order by a.attnum)
    into v_actual
    from pg_catalog.pg_attribute a
   where a.attrelid = 'public.airfnb_conversations'::regclass and a.attnum > 0 and not a.attisdropped;
  v_expected := 'id:uuid:true,booking_id:uuid:false,created_at:timestamp with time zone:false,application_id:uuid:false';
  if v_actual is distinct from v_expected then
    raise exception 'messaging reconciliation: conversations schema differs: %', v_actual;
  end if;

  select string_agg(a.attname || ':' || pg_catalog.format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull, ',' order by a.attnum)
    into v_actual
    from pg_catalog.pg_attribute a
   where a.attrelid = 'public.airfnb_conversation_participants'::regclass and a.attnum > 0 and not a.attisdropped;
  v_expected := 'conversation_id:uuid:true,user_id:uuid:true,last_read_at:timestamp with time zone:false';
  if v_actual is distinct from v_expected then
    raise exception 'messaging reconciliation: participants schema differs: %', v_actual;
  end if;

  select string_agg(a.attname || ':' || pg_catalog.format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull, ',' order by a.attnum)
    into v_actual
    from pg_catalog.pg_attribute a
   where a.attrelid = 'public.airfnb_messages'::regclass and a.attnum > 0 and not a.attisdropped;
  v_expected := 'id:uuid:true,conversation_id:uuid:false,sender_id:uuid:false,body:text:false,attachments:jsonb:false,created_at:timestamp with time zone:false';
  if v_actual is distinct from v_expected then
    raise exception 'messaging reconciliation: messages schema differs: %', v_actual;
  end if;

  select string_agg(a.attname || ':' || pg_catalog.format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull, ',' order by a.attnum)
    into v_actual
    from pg_catalog.pg_attribute a
   where a.attrelid = 'public.airfnb_reviews'::regclass and a.attnum > 0 and not a.attisdropped;
  v_expected := 'id:uuid:true,booking_id:uuid:false,truck_id:uuid:false,organizer_id:uuid:false,rating_food:smallint:false,rating_service:smallint:false,rating_value:smallint:false,rating_overall:numeric(2,1):false,body:text:false,reply_body:text:false,reply_at:timestamp with time zone:false,is_verified:boolean:false,created_at:timestamp with time zone:false';
  if v_actual is distinct from v_expected then
    raise exception 'messaging reconciliation: truck review schema differs: %', v_actual;
  end if;

  select string_agg(a.attname || ':' || pg_catalog.format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull, ',' order by a.attnum)
    into v_actual
    from pg_catalog.pg_attribute a
   where a.attrelid = 'public.airfnb_organizer_reviews'::regclass and a.attnum > 0 and not a.attisdropped;
  v_expected := 'id:uuid:true,booking_id:uuid:true,truck_id:uuid:true,organizer_id:uuid:true,rating_reliability:smallint:false,rating_communication:smallint:false,rating_payment:smallint:false,rating_overall:numeric(2,1):false,body:text:false,reply_body:text:false,reply_at:timestamp with time zone:false,is_verified:boolean:false,created_at:timestamp with time zone:false';
  if v_actual is distinct from v_expected then
    raise exception 'messaging reconciliation: organizer review schema differs: %', v_actual;
  end if;

  if (select count(*) from public.airfnb_conversations) <> 0
     or (select count(*) from public.airfnb_conversation_participants) <> 0
     or (select count(*) from public.airfnb_messages) <> 0
     or (select count(*) from public.airfnb_reviews) <> 0
     or (select count(*) from public.airfnb_organizer_reviews) <> 0 then
    raise exception 'messaging reconciliation: source messaging/review data precondition differs';
  end if;

  select md5(string_agg(
           t.id::text || ':' || coalesce(t.rating_avg::text, 'NULL') || ':' || coalesce(t.rating_count::text, 'NULL'),
           ',' order by t.id
         ))
    into v_actual
    from public.airfnb_trucks t;
  if v_actual is distinct from 'b7601dc5d1de93f854aaaf10085c33f7' then
    raise exception 'messaging reconciliation: seeded truck aggregate snapshot differs';
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_proc p
     where p.oid = 'public.airfnb_accept_application(uuid)'::regprocedure
       and p.proowner = v_owner
       and p.prosecdef
       and md5(p.prosrc) = 'b7c875f8b312e246e2f4621f5748b0a1'
       and p.prosrc like '%platform_fee%'
       and p.prosrc like '%organizer_share%'
       and p.prosrc like '%airfnb_lock_fees%'
       and p.prosrc like '%airfnb_conversation_participants%'
  ) then
    raise exception 'messaging reconciliation: payment-aware accept-application body differs';
  end if;

  if not v_reconciled then
    if to_regprocedure('public.airfnb_organizer_review_overall()') is null
       or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = 'public.airfnb_organizer_review_overall()'::regprocedure)
          <> 'a53c34aeaab68334f79ee97210cdb861' then
      raise exception 'messaging reconciliation: organizer overall helper precondition differs';
    end if;

    if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = 'public.airfnb_prepare_truck_review()'::regprocedure)
         <> 'a9df0239302007bbeaf13ab409649f51'
       or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = 'public.airfnb_prepare_organizer_review()'::regprocedure)
         <> '20c1fb6f710a6d8a23ed60ab5367a181'
       or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = 'public.airfnb_recalc_truck_rating()'::regprocedure)
         <> 'fb14827219d32ed1bfabfcc65fd44a45'
       or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = 'public.airfnb_organizer_rating_recompute()'::regprocedure)
         <> 'c0740c5b559d44c599f8c70046e45065'
       or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = 'public.airfnb_reply_to_truck_review(uuid,text)'::regprocedure)
         <> '0e1f558ec90f0589e971ffe7bdaad5af'
       or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = 'public.airfnb_reply_to_organizer_review(uuid,text)'::regprocedure)
         <> '25b9e9f5512cf0e170769b09f75f1ec1' then
      raise exception 'messaging reconciliation: predecessor review function body differs';
    end if;

    if (select array_agg(policyname order by policyname) from pg_catalog.pg_policies where schemaname = 'public' and tablename = 'airfnb_conversations')
         is distinct from array['airfnb_convs_admin_write','airfnb_convs_read']::name[]
       or (select array_agg(policyname order by policyname) from pg_catalog.pg_policies where schemaname = 'public' and tablename = 'airfnb_conversation_participants')
         is distinct from array['airfnb_cp_select_self','airfnb_cp_update_read_marker']::name[]
       or (select array_agg(policyname order by policyname) from pg_catalog.pg_policies where schemaname = 'public' and tablename = 'airfnb_messages')
         is distinct from array['airfnb_msg_read','airfnb_msg_send']::name[]
       or (select array_agg(policyname order by policyname) from pg_catalog.pg_policies where schemaname = 'public' and tablename = 'airfnb_reviews')
         is distinct from array['airfnb_reviews_participant_insert','airfnb_reviews_public_read']::name[]
       or (select array_agg(policyname order by policyname) from pg_catalog.pg_policies where schemaname = 'public' and tablename = 'airfnb_organizer_reviews')
         is distinct from array['airfnb_org_reviews_participant_insert','airfnb_org_reviews_public_read']::name[] then
      raise exception 'messaging reconciliation: predecessor policy catalog differs';
    end if;

    if has_table_privilege('authenticated', 'public.airfnb_conversations', 'SELECT,INSERT,UPDATE,DELETE')
       or has_table_privilege('authenticated', 'public.airfnb_messages', 'SELECT,INSERT,UPDATE,DELETE')
       or not has_table_privilege('authenticated', 'public.airfnb_conversation_participants', 'SELECT')
       or has_table_privilege('authenticated', 'public.airfnb_conversation_participants', 'INSERT,UPDATE,DELETE')
       or not has_column_privilege('authenticated', 'public.airfnb_conversation_participants', 'last_read_at', 'UPDATE')
       or not has_table_privilege('authenticated', 'public.airfnb_reviews', 'SELECT,INSERT')
       or not has_table_privilege('authenticated', 'public.airfnb_organizer_reviews', 'SELECT,INSERT')
       or not has_table_privilege('anon', 'public.airfnb_reviews', 'SELECT')
       or not has_table_privilege('anon', 'public.airfnb_organizer_reviews', 'SELECT') then
      raise exception 'messaging reconciliation: predecessor API ACL differs';
    end if;
  else
    if to_regprocedure('public.airfnb_organizer_review_overall()') is not null then
      raise exception 'messaging reconciliation: orphan organizer helper unexpectedly remains';
    end if;

    if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = 'public.airfnb_mark_conversation_read(uuid)'::regprocedure)
         <> 'e4b29973f81d3b8212ab06af255b0248'
       or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = 'public.airfnb_prepare_truck_review()'::regprocedure)
         <> '164aee771c6c03fcabf0efe80556460e'
       or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = 'public.airfnb_prepare_organizer_review()'::regprocedure)
         <> 'da47d5efe5cfa7e45c78f17eeac151b6'
       or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = 'public.airfnb_recalc_truck_rating()'::regprocedure)
         <> '06b8f300efdd0e8d2d418a8ae0ca48e5'
       or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = 'public.airfnb_organizer_rating_recompute()'::regprocedure)
         <> '4c5876eac73f9549ebecdee5503d8ffa'
       or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = 'public.airfnb_reply_to_truck_review(uuid,text)'::regprocedure)
         <> '3399b135f12f0aed8b33740aafc61c65'
       or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = 'public.airfnb_reply_to_organizer_review(uuid,text)'::regprocedure)
         <> '22690b5084c298a0fe20924039d8a6d1' then
      raise exception 'messaging reconciliation: reconciled function body differs';
    end if;

    if (select array_agg(policyname order by policyname) from pg_catalog.pg_policies where schemaname = 'public' and tablename = 'airfnb_conversations')
         is distinct from array['airfnb_convs_select_participant']::name[]
       or (select array_agg(policyname order by policyname) from pg_catalog.pg_policies where schemaname = 'public' and tablename = 'airfnb_conversation_participants')
         is distinct from array['airfnb_cp_select_participant']::name[]
       or (select array_agg(policyname order by policyname) from pg_catalog.pg_policies where schemaname = 'public' and tablename = 'airfnb_messages')
         is distinct from array['airfnb_msg_insert_participant','airfnb_msg_select_participant']::name[]
       or (select array_agg(policyname order by policyname) from pg_catalog.pg_policies where schemaname = 'public' and tablename = 'airfnb_reviews')
         is distinct from array['airfnb_reviews_participant_insert','airfnb_reviews_public_read']::name[]
       or (select array_agg(policyname order by policyname) from pg_catalog.pg_policies where schemaname = 'public' and tablename = 'airfnb_organizer_reviews')
         is distinct from array['airfnb_org_reviews_participant_insert','airfnb_org_reviews_public_read']::name[] then
      raise exception 'messaging reconciliation: reconciled policy catalog differs';
    end if;

    if not has_table_privilege('authenticated', 'public.airfnb_conversations', 'SELECT')
       or has_table_privilege('authenticated', 'public.airfnb_conversations', 'INSERT,UPDATE,DELETE')
       or not has_table_privilege('authenticated', 'public.airfnb_conversation_participants', 'SELECT')
       or has_table_privilege('authenticated', 'public.airfnb_conversation_participants', 'INSERT,UPDATE,DELETE')
       or has_column_privilege('authenticated', 'public.airfnb_conversation_participants', 'last_read_at', 'UPDATE')
       or not has_table_privilege('authenticated', 'public.airfnb_messages', 'SELECT')
       or has_table_privilege('authenticated', 'public.airfnb_messages', 'INSERT,UPDATE,DELETE')
       or not has_column_privilege('authenticated', 'public.airfnb_messages', 'conversation_id', 'INSERT')
       or not has_column_privilege('authenticated', 'public.airfnb_messages', 'sender_id', 'INSERT')
       or not has_column_privilege('authenticated', 'public.airfnb_messages', 'body', 'INSERT')
       or not has_column_privilege('authenticated', 'public.airfnb_messages', 'attachments', 'INSERT')
       or has_column_privilege('authenticated', 'public.airfnb_messages', 'id', 'INSERT')
       or has_column_privilege('authenticated', 'public.airfnb_messages', 'created_at', 'INSERT') then
      raise exception 'messaging reconciliation: reconciled messaging ACL differs';
    end if;
  end if;

  select count(*) into v_count
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
   where c.oid in ('public.airfnb_conversations'::regclass, 'public.airfnb_conversation_participants'::regclass, 'public.airfnb_messages'::regclass)
     and not t.tgisinternal;
  if v_count <> 0 then
    raise exception 'messaging reconciliation: unexpected messaging trigger catalog';
  end if;

  if (select array_agg(t.tgname order by t.tgname) from pg_catalog.pg_trigger t where t.tgrelid = 'public.airfnb_reviews'::regclass and not t.tgisinternal)
       is distinct from array['airfnb_prepare_truck_review','airfnb_trg_reviews_rating']::name[]
     or (select array_agg(t.tgname order by t.tgname) from pg_catalog.pg_trigger t where t.tgrelid = 'public.airfnb_organizer_reviews'::regclass and not t.tgisinternal)
       is distinct from array['airfnb_organizer_reviews_recompute','airfnb_prepare_organizer_review']::name[] then
    raise exception 'messaging reconciliation: review trigger catalog differs';
  end if;

  if exists (
    select 1
      from pg_catalog.pg_class c
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace
      cross join lateral pg_catalog.aclexplode(c.relacl) x
     where n.nspname = 'public'
       and c.relname in ('airfnb_conversations','airfnb_conversation_participants','airfnb_messages','airfnb_reviews','airfnb_organizer_reviews')
       and x.grantee not in (
         0,
         c.relowner,
         (select oid from pg_catalog.pg_roles where rolname = 'anon'),
         (select oid from pg_catalog.pg_roles where rolname = 'authenticated'),
         (select oid from pg_catalog.pg_roles where rolname = 'service_role')
       )
  ) then
    raise exception 'messaging reconciliation: unexpected table ACL grantee';
  end if;
end;
$preflight$;

-- The payment-aware body remains byte-identical. Only its trusted resolution
-- path is tightened; CREATE OR REPLACE is deliberately not used here.
alter function public.airfnb_accept_application(uuid)
  set search_path = pg_catalog, public;

-- -------------------------------------------------------------------------
-- Conversation isolation and a monotonic server-time read marker
-- -------------------------------------------------------------------------

drop policy if exists "airfnb_convs_admin_write" on public.airfnb_conversations;
drop policy if exists "airfnb_convs_read" on public.airfnb_conversations;
drop policy if exists "airfnb_convs_select_participant" on public.airfnb_conversations;

create policy "airfnb_convs_select_participant"
  on public.airfnb_conversations
  for select
  to authenticated
  using (
    (select public.airfnb_is_admin())
    or exists (
      select 1
        from public.airfnb_conversation_participants cp
       where cp.conversation_id = airfnb_conversations.id
         and cp.user_id = (select auth.uid())
    )
  );

drop policy if exists "airfnb_cp_select_self" on public.airfnb_conversation_participants;
drop policy if exists "airfnb_cp_update_read_marker" on public.airfnb_conversation_participants;
drop policy if exists "airfnb_cp_select_participant" on public.airfnb_conversation_participants;

create policy "airfnb_cp_select_participant"
  on public.airfnb_conversation_participants
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or (select public.airfnb_is_admin())
  );

drop policy if exists "airfnb_msg_read" on public.airfnb_messages;
drop policy if exists "airfnb_msg_send" on public.airfnb_messages;
drop policy if exists "airfnb_msg_select_participant" on public.airfnb_messages;
drop policy if exists "airfnb_msg_insert_participant" on public.airfnb_messages;

create policy "airfnb_msg_select_participant"
  on public.airfnb_messages
  for select
  to authenticated
  using (
    (select public.airfnb_is_admin())
    or exists (
      select 1
        from public.airfnb_conversation_participants cp
       where cp.conversation_id = airfnb_messages.conversation_id
         and cp.user_id = (select auth.uid())
    )
  );

create policy "airfnb_msg_insert_participant"
  on public.airfnb_messages
  for insert
  to authenticated
  with check (
    sender_id = (select auth.uid())
    and exists (
      select 1
        from public.airfnb_conversation_participants cp
       where cp.conversation_id = airfnb_messages.conversation_id
         and cp.user_id = (select auth.uid())
    )
  );

revoke all on table public.airfnb_conversations from public, anon, authenticated;
revoke all on table public.airfnb_conversation_participants from public, anon, authenticated;
revoke all on table public.airfnb_messages from public, anon, authenticated;

grant select on table public.airfnb_conversations to authenticated;
grant select on table public.airfnb_conversation_participants to authenticated;
grant select on table public.airfnb_messages to authenticated;
grant insert (conversation_id, sender_id, body, attachments)
  on table public.airfnb_messages to authenticated;

create or replace function public.airfnb_mark_conversation_read(p_conversation uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'conversation access denied';
  end if;

  update public.airfnb_conversation_participants cp
     set last_read_at = greatest(
       coalesce(cp.last_read_at, '-infinity'::timestamptz),
       statement_timestamp()
     )
   where cp.conversation_id = p_conversation
     and cp.user_id = v_actor;

  if not found then
    raise exception using errcode = '42501', message = 'conversation access denied';
  end if;
end;
$function$;

revoke all on function public.airfnb_mark_conversation_read(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.airfnb_mark_conversation_read(uuid)
  to authenticated;

-- -------------------------------------------------------------------------
-- Review inserts: expose input columns only and derive every trusted field.
-- -------------------------------------------------------------------------

create or replace function public.airfnb_prepare_truck_review()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_actor uuid := auth.uid();
  v_organizer uuid;
  v_status public.airfnb_booking_status;
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;
  if new.rating_food is null
     or new.rating_service is null
     or new.rating_value is null
     or new.rating_food not between 1 and 5
     or new.rating_service not between 1 and 5
     or new.rating_value not between 1 and 5 then
    raise exception using errcode = '23514', message = 'truck review ratings must be between 1 and 5';
  end if;

  select b.organizer_id, b.status
    into v_organizer, v_status
    from public.airfnb_bookings b
   where b.id = new.booking_id;
  if not found or v_status not in ('confirmed', 'completed') then
    raise exception using errcode = '23514', message = 'booking is not reviewable';
  end if;
  if v_organizer is distinct from v_actor then
    raise exception using errcode = '42501', message = 'only the booking organizer may review this truck';
  end if;
  if not exists (
    select 1
      from public.airfnb_booking_trucks bt
     where bt.booking_id = new.booking_id
       and bt.truck_id = new.truck_id
  ) then
    raise exception using errcode = '23514', message = 'truck did not participate in this booking';
  end if;

  new.organizer_id := v_organizer;
  new.rating_overall := round((new.rating_food + new.rating_service + new.rating_value)::numeric / 3, 1);
  new.is_verified := true;
  new.reply_body := null;
  new.reply_at := null;
  new.created_at := statement_timestamp();
  return new;
end;
$function$;

create or replace function public.airfnb_prepare_organizer_review()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_actor uuid := auth.uid();
  v_organizer uuid;
  v_status public.airfnb_booking_status;
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;
  if new.rating_reliability is null
     or new.rating_communication is null
     or new.rating_payment is null
     or new.rating_reliability not between 1 and 5
     or new.rating_communication not between 1 and 5
     or new.rating_payment not between 1 and 5 then
    raise exception using errcode = '23514', message = 'organizer review ratings must be between 1 and 5';
  end if;

  select b.organizer_id, b.status
    into v_organizer, v_status
    from public.airfnb_bookings b
   where b.id = new.booking_id;
  if not found or v_status not in ('confirmed', 'completed') then
    raise exception using errcode = '23514', message = 'booking is not reviewable';
  end if;
  if not exists (
    select 1
      from public.airfnb_booking_trucks bt
      join public.airfnb_trucks t on t.id = bt.truck_id
     where bt.booking_id = new.booking_id
       and bt.truck_id = new.truck_id
       and t.owner_id = v_actor
  ) then
    raise exception using errcode = '42501', message = 'only a participating truck owner may review this organizer';
  end if;

  new.organizer_id := v_organizer;
  new.rating_overall := round((new.rating_reliability + new.rating_communication + new.rating_payment)::numeric / 3, 1);
  new.is_verified := true;
  new.reply_body := null;
  new.reply_at := null;
  new.created_at := statement_timestamp();
  return new;
end;
$function$;

revoke all on function public.airfnb_prepare_truck_review()
  from public, anon, authenticated, service_role;
revoke all on function public.airfnb_prepare_organizer_review()
  from public, anon, authenticated, service_role;

drop trigger if exists airfnb_prepare_truck_review on public.airfnb_reviews;
create trigger airfnb_prepare_truck_review
  before insert on public.airfnb_reviews
  for each row execute function public.airfnb_prepare_truck_review();

drop trigger if exists airfnb_prepare_organizer_review on public.airfnb_organizer_reviews;
create trigger airfnb_prepare_organizer_review
  before insert on public.airfnb_organizer_reviews
  for each row execute function public.airfnb_prepare_organizer_review();

drop policy if exists "airfnb_reviews_participant_insert" on public.airfnb_reviews;
drop policy if exists "airfnb_reviews_public_read" on public.airfnb_reviews;

create policy "airfnb_reviews_public_read"
  on public.airfnb_reviews
  for select
  to anon, authenticated
  using (true);

create policy "airfnb_reviews_participant_insert"
  on public.airfnb_reviews
  for insert
  to authenticated
  with check (
    organizer_id = (select auth.uid())
    and is_verified is true
    and rating_food between 1 and 5
    and rating_service between 1 and 5
    and rating_value between 1 and 5
    and rating_overall = round((rating_food + rating_service + rating_value)::numeric / 3, 1)
    and reply_body is null
    and reply_at is null
  );

drop policy if exists "airfnb_org_reviews_participant_insert" on public.airfnb_organizer_reviews;
drop policy if exists "airfnb_org_reviews_public_read" on public.airfnb_organizer_reviews;

create policy "airfnb_org_reviews_public_read"
  on public.airfnb_organizer_reviews
  for select
  to anon, authenticated
  using (true);

create policy "airfnb_org_reviews_participant_insert"
  on public.airfnb_organizer_reviews
  for insert
  to authenticated
  with check (
    is_verified is true
    and rating_reliability between 1 and 5
    and rating_communication between 1 and 5
    and rating_payment between 1 and 5
    and rating_overall = round((rating_reliability + rating_communication + rating_payment)::numeric / 3, 1)
    and reply_body is null
    and reply_at is null
    and exists (
      select 1
        from public.airfnb_trucks t
       where t.id = airfnb_organizer_reviews.truck_id
         and t.owner_id = (select auth.uid())
    )
  );

revoke all on table public.airfnb_reviews from public, anon, authenticated;
revoke all on table public.airfnb_organizer_reviews from public, anon, authenticated;
grant select on table public.airfnb_reviews to anon, authenticated;
grant select on table public.airfnb_organizer_reviews to anon, authenticated;
grant insert (booking_id, truck_id, rating_food, rating_service, rating_value, body)
  on table public.airfnb_reviews to authenticated;
grant insert (booking_id, truck_id, rating_reliability, rating_communication, rating_payment, body)
  on table public.airfnb_organizer_reviews to authenticated;

-- -------------------------------------------------------------------------
-- Aggregate maintenance: reply-only updates never fire; trusted rebinds
-- recompute both the old and new aggregate owners.
-- -------------------------------------------------------------------------

create or replace function public.airfnb_recalc_truck_rating()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_truck_id uuid;
begin
  for v_truck_id in
    select distinct candidate
      from unnest(array[
        case when tg_op <> 'INSERT' then old.truck_id else null end,
        case when tg_op <> 'DELETE' then new.truck_id else null end
      ]) candidate
     where candidate is not null
     order by candidate
  loop
    update public.airfnb_trucks t
       set rating_avg = coalesce((
             select round(avg(r.rating_overall)::numeric, 1)
               from public.airfnb_reviews r
              where r.truck_id = v_truck_id
           ), 0),
           rating_count = (
             select count(*)
               from public.airfnb_reviews r
              where r.truck_id = v_truck_id
           )
     where t.id = v_truck_id;
  end loop;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

create or replace function public.airfnb_organizer_rating_recompute()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_organizer_id uuid;
begin
  for v_organizer_id in
    select distinct candidate
      from unnest(array[
        case when tg_op <> 'INSERT' then old.organizer_id else null end,
        case when tg_op <> 'DELETE' then new.organizer_id else null end
      ]) candidate
     where candidate is not null
     order by candidate
  loop
    update public.airfnb_profiles p
       set organizer_rating_avg = coalesce((
             select round(avg(r.rating_overall)::numeric, 1)
               from public.airfnb_organizer_reviews r
              where r.organizer_id = v_organizer_id
           ), 0),
           organizer_rating_count = (
             select count(*)
               from public.airfnb_organizer_reviews r
              where r.organizer_id = v_organizer_id
           )
     where p.id = v_organizer_id;
  end loop;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

revoke all on function public.airfnb_recalc_truck_rating()
  from public, anon, authenticated, service_role;
revoke all on function public.airfnb_organizer_rating_recompute()
  from public, anon, authenticated, service_role;

drop trigger if exists airfnb_trg_reviews_rating on public.airfnb_reviews;
create trigger airfnb_trg_reviews_rating
  after insert or delete or update of truck_id, rating_overall
  on public.airfnb_reviews
  for each row execute function public.airfnb_recalc_truck_rating();

drop trigger if exists airfnb_organizer_reviews_recompute on public.airfnb_organizer_reviews;
create trigger airfnb_organizer_reviews_recompute
  after insert or delete or update of organizer_id, rating_overall
  on public.airfnb_organizer_reviews
  for each row execute function public.airfnb_organizer_rating_recompute();

do $dependency_proof$
declare
  v_oid oid := to_regprocedure('public.airfnb_organizer_review_overall()');
begin
  if v_oid is not null and exists (
    select 1
      from pg_catalog.pg_depend d
     where d.refobjid = v_oid
       and d.deptype not in ('i', 'e')
  ) then
    raise exception 'messaging reconciliation: organizer overall helper is not orphaned';
  end if;
end;
$dependency_proof$;

drop function if exists public.airfnb_organizer_review_overall();

-- -------------------------------------------------------------------------
-- Replaceable, owner-checked reply RPCs. Direct table UPDATE/DELETE remains
-- unavailable to API roles and the aggregate triggers ignore these updates.
-- -------------------------------------------------------------------------

create or replace function public.airfnb_reply_to_truck_review(p_review uuid, p_reply text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_actor uuid := auth.uid();
  v_reply text := nullif(btrim(p_reply), '');
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;
  if v_reply is null or char_length(v_reply) > 2000 then
    raise exception using errcode = '22023', message = 'reply must contain between 1 and 2000 characters';
  end if;

  update public.airfnb_reviews r
     set reply_body = v_reply,
         reply_at = statement_timestamp()
   where r.id = p_review
     and exists (
       select 1
         from public.airfnb_trucks t
        where t.id = r.truck_id
          and t.owner_id = v_actor
     );
  if not found then
    raise exception using errcode = '42501', message = 'only the reviewed truck owner may reply';
  end if;
end;
$function$;

create or replace function public.airfnb_reply_to_organizer_review(p_review uuid, p_reply text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_actor uuid := auth.uid();
  v_reply text := nullif(btrim(p_reply), '');
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;
  if v_reply is null or char_length(v_reply) > 2000 then
    raise exception using errcode = '22023', message = 'reply must contain between 1 and 2000 characters';
  end if;

  update public.airfnb_organizer_reviews r
     set reply_body = v_reply,
         reply_at = statement_timestamp()
   where r.id = p_review
     and r.organizer_id = v_actor;
  if not found then
    raise exception using errcode = '42501', message = 'only the reviewed organizer may reply';
  end if;
end;
$function$;

revoke all on function public.airfnb_reply_to_truck_review(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.airfnb_reply_to_organizer_review(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.airfnb_reply_to_truck_review(uuid, text)
  to authenticated;
grant execute on function public.airfnb_reply_to_organizer_review(uuid, text)
  to authenticated;

do $postconditions$
declare
  v_accept_snapshot messaging_reconciliation_accept_snapshot%rowtype;
begin
  select * into strict v_accept_snapshot from messaging_reconciliation_accept_snapshot;
  if not exists (
    select 1
      from pg_catalog.pg_proc p
     where p.oid = 'public.airfnb_accept_application(uuid)'::regprocedure
       and md5(p.prosrc) = v_accept_snapshot.body_hash
       and p.proacl::text is not distinct from v_accept_snapshot.function_acl
       and p.proowner = v_accept_snapshot.function_owner
       and p.proconfig = array['search_path=pg_catalog, public']
  ) then
    raise exception 'messaging reconciliation: accept-application body/ACL/owner changed';
  end if;

  if exists (
    (select relation_name, acl_item from messaging_reconciliation_service_acl)
    except
    (select c.relname, acl_item::text
       from pg_catalog.pg_class c
       join pg_catalog.pg_namespace n on n.oid = c.relnamespace
       cross join lateral unnest(coalesce(c.relacl, '{}'::aclitem[])) acl_item
      where n.nspname = 'public'
        and c.relname in ('airfnb_conversations','airfnb_conversation_participants','airfnb_messages','airfnb_reviews','airfnb_organizer_reviews')
        and acl_item::text like 'service_role=%')
  ) or exists (
    (select c.relname, acl_item::text
       from pg_catalog.pg_class c
       join pg_catalog.pg_namespace n on n.oid = c.relnamespace
       cross join lateral unnest(coalesce(c.relacl, '{}'::aclitem[])) acl_item
      where n.nspname = 'public'
        and c.relname in ('airfnb_conversations','airfnb_conversation_participants','airfnb_messages','airfnb_reviews','airfnb_organizer_reviews')
        and acl_item::text like 'service_role=%')
    except
    (select relation_name, acl_item from messaging_reconciliation_service_acl)
  ) then
    raise exception 'messaging reconciliation: explicit service_role table ACL changed';
  end if;

  if has_table_privilege('authenticated', 'public.airfnb_reviews', 'INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated', 'public.airfnb_organizer_reviews', 'INSERT,UPDATE,DELETE')
     or not has_column_privilege('authenticated', 'public.airfnb_reviews', 'booking_id', 'INSERT')
     or not has_column_privilege('authenticated', 'public.airfnb_reviews', 'truck_id', 'INSERT')
     or not has_column_privilege('authenticated', 'public.airfnb_reviews', 'rating_food', 'INSERT')
     or has_column_privilege('authenticated', 'public.airfnb_reviews', 'organizer_id', 'INSERT')
     or has_column_privilege('authenticated', 'public.airfnb_reviews', 'rating_overall', 'INSERT')
     or has_column_privilege('authenticated', 'public.airfnb_reviews', 'is_verified', 'INSERT')
     or not has_column_privilege('authenticated', 'public.airfnb_organizer_reviews', 'booking_id', 'INSERT')
     or not has_column_privilege('authenticated', 'public.airfnb_organizer_reviews', 'truck_id', 'INSERT')
     or not has_column_privilege('authenticated', 'public.airfnb_organizer_reviews', 'rating_reliability', 'INSERT')
     or has_column_privilege('authenticated', 'public.airfnb_organizer_reviews', 'organizer_id', 'INSERT')
     or has_column_privilege('authenticated', 'public.airfnb_organizer_reviews', 'rating_overall', 'INSERT')
     or has_column_privilege('authenticated', 'public.airfnb_organizer_reviews', 'is_verified', 'INSERT') then
    raise exception 'messaging reconciliation: review column ACL postcondition failed';
  end if;

end;
$postconditions$;

-- Verify trusted-function ownership without hard-coding a deployment role.
do $owner_postcondition$
declare
  v_table_owner oid := (select relowner from pg_catalog.pg_class where oid = 'public.airfnb_conversation_participants'::regclass);
begin
  if exists (
    select 1
      from unnest(array[
        'public.airfnb_mark_conversation_read(uuid)'::regprocedure,
        'public.airfnb_prepare_truck_review()'::regprocedure,
        'public.airfnb_prepare_organizer_review()'::regprocedure,
        'public.airfnb_recalc_truck_rating()'::regprocedure,
        'public.airfnb_organizer_rating_recompute()'::regprocedure,
        'public.airfnb_reply_to_truck_review(uuid,text)'::regprocedure,
        'public.airfnb_reply_to_organizer_review(uuid,text)'::regprocedure
      ]) as f(function_oid)
      join pg_catalog.pg_proc p on p.oid = f.function_oid
     where p.proowner <> v_table_owner
       or not p.prosecdef
       or p.proconfig <> array['search_path=pg_catalog, public']
  ) then
    raise exception 'messaging reconciliation: trusted function owner/config postcondition failed';
  end if;
end;
$owner_postcondition$;

commit;
