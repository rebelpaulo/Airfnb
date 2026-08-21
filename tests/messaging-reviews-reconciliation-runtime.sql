\set ON_ERROR_STOP on

begin;
set local statement_timeout = '60s';

-- Stable synthetic identities used only inside this transaction.
insert into auth.users (id) values
  ('10000000-0000-0000-0000-000000000001'),
  ('10000000-0000-0000-0000-000000000002'),
  ('10000000-0000-0000-0000-000000000003'),
  ('10000000-0000-0000-0000-000000000004'),
  ('10000000-0000-0000-0000-000000000005');

update public.airfnb_profiles p
   set role = fixture.role::public.airfnb_user_role,
       display_name = fixture.display_name
  from (values
    ('10000000-0000-0000-0000-000000000001'::uuid, 'organizer', 'Organizer A'),
    ('10000000-0000-0000-0000-000000000002'::uuid, 'owner', 'Owner A'),
    ('10000000-0000-0000-0000-000000000003'::uuid, 'organizer', 'Outsider'),
    ('10000000-0000-0000-0000-000000000004'::uuid, 'admin', 'Admin'),
    ('10000000-0000-0000-0000-000000000005'::uuid, 'organizer', 'Organizer B')
  ) as fixture(id, role, display_name)
 where p.id = fixture.id;

insert into public.airfnb_trucks (id, owner_id, slug, name) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 'runtime-truck-a', 'Runtime Truck A'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'runtime-truck-b', 'Runtime Truck B');

insert into public.airfnb_bookings (id, organizer_id, status) values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'confirmed'),
  ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'inquiry');

insert into public.airfnb_booking_trucks (booking_id, truck_id) values
  ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001'),
  ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001');

insert into public.airfnb_conversations (id, booking_id) values
  ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001');
insert into public.airfnb_conversation_participants (conversation_id, user_id, last_read_at) values
  ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '2020-01-01 00:00:00+00'),
  ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', null);

do $catalog_assertions$
begin
  if not has_function_privilege('authenticated', 'public.airfnb_mark_conversation_read(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.airfnb_mark_conversation_read(uuid)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.airfnb_mark_conversation_read(uuid)', 'EXECUTE') then
    raise exception 'mark-read execute ACL is not authenticated-only';
  end if;
  if has_table_privilege('authenticated', 'public.airfnb_messages', 'INSERT')
     or not has_column_privilege('authenticated', 'public.airfnb_messages', 'conversation_id', 'INSERT')
     or not has_column_privilege('authenticated', 'public.airfnb_messages', 'sender_id', 'INSERT')
     or has_column_privilege('authenticated', 'public.airfnb_messages', 'id', 'INSERT')
     or has_column_privilege('authenticated', 'public.airfnb_messages', 'created_at', 'INSERT') then
    raise exception 'message column ACL is broader or narrower than expected';
  end if;
  if has_table_privilege('authenticated', 'public.airfnb_reviews', 'INSERT')
     or has_column_privilege('authenticated', 'public.airfnb_reviews', 'organizer_id', 'INSERT')
     or has_column_privilege('authenticated', 'public.airfnb_reviews', 'rating_overall', 'INSERT')
     or has_column_privilege('authenticated', 'public.airfnb_reviews', 'is_verified', 'INSERT')
     or not has_column_privilege('authenticated', 'public.airfnb_reviews', 'rating_food', 'INSERT') then
    raise exception 'truck-review input ACL is not narrow';
  end if;
  if has_table_privilege('authenticated', 'public.airfnb_organizer_reviews', 'INSERT')
     or has_column_privilege('authenticated', 'public.airfnb_organizer_reviews', 'organizer_id', 'INSERT')
     or has_column_privilege('authenticated', 'public.airfnb_organizer_reviews', 'rating_overall', 'INSERT')
     or has_column_privilege('authenticated', 'public.airfnb_organizer_reviews', 'is_verified', 'INSERT')
     or not has_column_privilege('authenticated', 'public.airfnb_organizer_reviews', 'rating_reliability', 'INSERT') then
    raise exception 'organizer-review input ACL is not narrow';
  end if;
  if (select count(*) from pg_catalog.pg_depend d
       where d.refobjid = to_regprocedure('public.airfnb_organizer_review_overall()')) <> 0
     or to_regprocedure('public.airfnb_organizer_review_overall()') is not null then
    raise exception 'orphan organizer-overall helper still exists';
  end if;
  if (select pg_get_triggerdef(t.oid, true) from pg_catalog.pg_trigger t
       where t.tgrelid = 'public.airfnb_reviews'::regclass and t.tgname = 'airfnb_trg_reviews_rating')
       not like '%UPDATE OF truck_id, rating_overall%'
     or (select pg_get_triggerdef(t.oid, true) from pg_catalog.pg_trigger t
       where t.tgrelid = 'public.airfnb_organizer_reviews'::regclass and t.tgname = 'airfnb_organizer_reviews_recompute')
       not like '%UPDATE OF organizer_id, rating_overall%' then
    raise exception 'aggregate triggers are not column-scoped';
  end if;
end;
$catalog_assertions$;

-- Participant A can see the conversation and send a message with only the
-- four granted input columns.
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;

do $participant_visibility$
begin
  if (select count(*) from public.airfnb_conversations where id = '40000000-0000-0000-0000-000000000001') <> 1 then
    raise exception 'participant cannot read conversation';
  end if;
  if (select count(*) from public.airfnb_conversation_participants where conversation_id = '40000000-0000-0000-0000-000000000001') <> 1 then
    raise exception 'participant may read more than its own participant row';
  end if;
end;
$participant_visibility$;

insert into public.airfnb_messages (conversation_id, sender_id, body, attachments)
values (
  '40000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  'legitimate runtime message',
  '[]'::jsonb
);

do $message_adversarial$
begin
  begin
    insert into public.airfnb_messages (conversation_id, sender_id, body)
    values ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 'forged sender');
    raise exception 'forged sender unexpectedly succeeded';
  exception when sqlstate '42501' then null;
  end;
  begin
    insert into public.airfnb_messages (id, conversation_id, sender_id, body)
    values ('50000000-0000-0000-0000-000000000099', '40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'forged key');
    raise exception 'forged message key unexpectedly succeeded';
  exception when sqlstate '42501' then null;
  end;
  begin
    update public.airfnb_conversation_participants
       set last_read_at = '2999-01-01 00:00:00+00'
     where conversation_id = '40000000-0000-0000-0000-000000000001';
    raise exception 'future read marker unexpectedly succeeded';
  exception when sqlstate '42501' then null;
  end;
end;
$message_adversarial$;

select public.airfnb_mark_conversation_read('40000000-0000-0000-0000-000000000001');

do $marker_assertion$
declare
  v_marker timestamptz;
begin
  select last_read_at into v_marker
    from public.airfnb_conversation_participants
   where conversation_id = '40000000-0000-0000-0000-000000000001'
     and user_id = '10000000-0000-0000-0000-000000000001';
  if v_marker <= '2020-01-01 00:00:00+00' or v_marker > clock_timestamp() then
    raise exception 'read marker is not a monotonic database timestamp: %', v_marker;
  end if;
end;
$marker_assertion$;

-- Organizer A creates a truck review using only input columns. The trigger
-- derives actor, verification, aggregate and timestamps.
insert into public.airfnb_reviews (
  booking_id, truck_id, rating_food, rating_service, rating_value, body
) values (
  '30000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  5, 4, 3, 'A legitimate truck review body.'
);

do $truck_review_assertion$
begin
  if not exists (
    select 1 from public.airfnb_reviews
     where booking_id = '30000000-0000-0000-0000-000000000001'
       and truck_id = '20000000-0000-0000-0000-000000000001'
       and organizer_id = '10000000-0000-0000-0000-000000000001'
       and rating_overall = 4.0
       and is_verified is true
       and created_at <= clock_timestamp()
       and reply_body is null and reply_at is null
  ) then
    raise exception 'truck review controlled fields were not derived';
  end if;
  begin
    insert into public.airfnb_reviews (booking_id, truck_id, rating_food, rating_service, rating_value, body)
    values ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', 6, 4, 3, 'bad rating');
    raise exception 'out-of-range truck review unexpectedly succeeded';
  exception when sqlstate '23514' then null;
  end;
  begin
    insert into public.airfnb_reviews (booking_id, truck_id, rating_food, rating_service, rating_value, body)
    values ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', 5, 4, 3, 'nonparticipant');
    raise exception 'nonparticipating truck review unexpectedly succeeded';
  exception when sqlstate '23514' then null;
  end;
  begin
    insert into public.airfnb_reviews (booking_id, truck_id, rating_food, rating_service, rating_value, body)
    values ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 5, 4, 3, 'wrong status');
    raise exception 'pending-booking truck review unexpectedly succeeded';
  exception when sqlstate '23514' then null;
  end;
  begin
    insert into public.airfnb_reviews (booking_id, truck_id, rating_food, rating_service, rating_value, body)
    values ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 5, 4, 3, 'duplicate');
    raise exception 'duplicate truck review unexpectedly succeeded';
  exception when sqlstate '23505' then null;
  end;
  begin
    update public.airfnb_reviews set body = 'mutated content';
    raise exception 'direct truck review update unexpectedly succeeded';
  exception when sqlstate '42501' then null;
  end;
  begin
    delete from public.airfnb_reviews;
    raise exception 'direct truck review delete unexpectedly succeeded';
  exception when sqlstate '42501' then null;
  end;
end;
$truck_review_assertion$;

-- Outsiders can neither see conversation state nor forge reviews/read markers.
reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
set local role authenticated;
do $outsider_assertions$
begin
  if (select count(*) from public.airfnb_conversations where id = '40000000-0000-0000-0000-000000000001') <> 0
     or (select count(*) from public.airfnb_messages where conversation_id = '40000000-0000-0000-0000-000000000001') <> 0 then
    raise exception 'outsider can read conversation data';
  end if;
  begin
    perform public.airfnb_mark_conversation_read('40000000-0000-0000-0000-000000000001');
    raise exception 'outsider mark-read unexpectedly succeeded';
  exception when sqlstate '42501' then null;
  end;
  begin
    insert into public.airfnb_messages (conversation_id, sender_id, body)
    values ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003', 'outsider message');
    raise exception 'outsider message unexpectedly succeeded';
  exception when sqlstate '42501' then null;
  end;
  begin
    insert into public.airfnb_reviews (booking_id, truck_id, rating_food, rating_service, rating_value, body)
    values ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 5, 5, 5, 'wrong actor');
    raise exception 'wrong-actor truck review unexpectedly succeeded';
  exception when sqlstate '42501' then null;
  end;
end;
$outsider_assertions$;

-- The participating truck owner creates the reverse review.
reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
set local role authenticated;
insert into public.airfnb_organizer_reviews (
  booking_id, truck_id, rating_reliability, rating_communication, rating_payment, body
) values (
  '30000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  5, 4, 3, 'A legitimate organizer review body.'
);

do $organizer_review_assertion$
begin
  if not exists (
    select 1 from public.airfnb_organizer_reviews
     where booking_id = '30000000-0000-0000-0000-000000000001'
       and truck_id = '20000000-0000-0000-0000-000000000001'
       and organizer_id = '10000000-0000-0000-0000-000000000001'
       and rating_overall = 4.0
       and is_verified is true
       and created_at <= clock_timestamp()
  ) then
    raise exception 'organizer review controlled fields were not derived';
  end if;
  begin
    insert into public.airfnb_organizer_reviews (booking_id, truck_id, rating_reliability, rating_communication, rating_payment, body)
    values ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 5, 4, 3, 'wrong status');
    raise exception 'pending-booking organizer review unexpectedly succeeded';
  exception when sqlstate '23514' then null;
  end;
  begin
    update public.airfnb_organizer_reviews set rating_payment = 1;
    raise exception 'direct organizer review update unexpectedly succeeded';
  exception when sqlstate '42501' then null;
  end;
  begin
    delete from public.airfnb_organizer_reviews;
    raise exception 'direct organizer review delete unexpectedly succeeded';
  exception when sqlstate '42501' then null;
  end;
end;
$organizer_review_assertion$;

-- Reply is trim-normalized, replaceable, owner-checked and aggregate-neutral.
reset role;
update public.airfnb_trucks
   set rating_avg = 3.3, rating_count = 77
 where id = '20000000-0000-0000-0000-000000000001';
update public.airfnb_profiles
   set organizer_rating_avg = 3.2, organizer_rating_count = 66
 where id = '10000000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select public.airfnb_reply_to_truck_review(
  (select id from public.airfnb_reviews where booking_id = '30000000-0000-0000-0000-000000000001'),
  '  first supplier reply  '
);
select public.airfnb_reply_to_truck_review(
  (select id from public.airfnb_reviews where booking_id = '30000000-0000-0000-0000-000000000001'),
  'replacement supplier reply'
);
do $supplier_reply_assertions$
begin
  if not exists (select 1 from public.airfnb_reviews where reply_body = 'replacement supplier reply' and reply_at is not null)
     or not exists (select 1 from public.airfnb_trucks where id = '20000000-0000-0000-0000-000000000001' and rating_avg = 3.3 and rating_count = 77) then
    raise exception 'supplier reply was not replaceable/trimmed or recomputed aggregate';
  end if;
  begin
    perform public.airfnb_reply_to_truck_review((select id from public.airfnb_reviews limit 1), '   ');
    raise exception 'blank supplier reply unexpectedly succeeded';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.airfnb_reply_to_truck_review('50000000-0000-0000-0000-000000000099', 'missing');
    raise exception 'missing supplier review reply unexpectedly succeeded';
  exception when sqlstate '42501' then null;
  end;
end;
$supplier_reply_assertions$;

reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.airfnb_reply_to_organizer_review(
  (select id from public.airfnb_organizer_reviews where booking_id = '30000000-0000-0000-0000-000000000001'),
  '  first organizer reply  '
);
select public.airfnb_reply_to_organizer_review(
  (select id from public.airfnb_organizer_reviews where booking_id = '30000000-0000-0000-0000-000000000001'),
  'replacement organizer reply'
);
do $organizer_reply_assertions$
begin
  if not exists (select 1 from public.airfnb_organizer_reviews where reply_body = 'replacement organizer reply' and reply_at is not null) then
    raise exception 'organizer reply was not replaceable/trimmed';
  end if;
  begin
    perform public.airfnb_reply_to_organizer_review((select id from public.airfnb_organizer_reviews limit 1), repeat('x', 2001));
    raise exception 'oversized organizer reply unexpectedly succeeded';
  exception when sqlstate '22023' then null;
  end;
end;
$organizer_reply_assertions$;

-- Wrong parties fail closed for each reply direction.
reset role;
do $organizer_reply_aggregate_assertion$
begin
  if not exists (
    select 1 from public.airfnb_profiles
     where id = '10000000-0000-0000-0000-000000000001'
       and organizer_rating_avg = 3.2
       and organizer_rating_count = 66
  ) then
    raise exception 'reply-only update recomputed organizer aggregate';
  end if;
end;
$organizer_reply_aggregate_assertion$;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
set local role authenticated;
do $wrong_reply_actor$
begin
  begin
    perform public.airfnb_reply_to_truck_review((select id from public.airfnb_reviews limit 1), 'wrong actor');
    raise exception 'wrong truck reply actor unexpectedly succeeded';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform public.airfnb_reply_to_organizer_review((select id from public.airfnb_organizer_reviews limit 1), 'wrong actor');
    raise exception 'wrong organizer reply actor unexpectedly succeeded';
  exception when sqlstate '42501' then null;
  end;
end;
$wrong_reply_actor$;

-- Admin isolation exception remains read-only through authenticated ACLs.
reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000004', true);
set local role authenticated;
do $admin_read_assertions$
begin
  if (select count(*) from public.airfnb_conversations where id = '40000000-0000-0000-0000-000000000001') <> 1
     or (select count(*) from public.airfnb_messages where conversation_id = '40000000-0000-0000-0000-000000000001') <> 1
     or (select count(*) from public.airfnb_conversation_participants where conversation_id = '40000000-0000-0000-0000-000000000001') <> 2 then
    raise exception 'admin cannot read isolated conversation state';
  end if;
end;
$admin_read_assertions$;

-- Trusted recovery rebinds prove both old and new aggregate owners recompute.
reset role;
update public.airfnb_reviews
   set truck_id = '20000000-0000-0000-0000-000000000002', rating_overall = 5.0
 where booking_id = '30000000-0000-0000-0000-000000000001';
update public.airfnb_organizer_reviews
   set organizer_id = '10000000-0000-0000-0000-000000000005', rating_overall = 5.0
 where booking_id = '30000000-0000-0000-0000-000000000001';

do $rebind_assertions$
begin
  if not exists (select 1 from public.airfnb_trucks where id = '20000000-0000-0000-0000-000000000001' and rating_avg = 0 and rating_count = 0)
     or not exists (select 1 from public.airfnb_trucks where id = '20000000-0000-0000-0000-000000000002' and rating_avg = 5.0 and rating_count = 1) then
    raise exception 'truck old/new aggregate rebind failed';
  end if;
  if not exists (select 1 from public.airfnb_profiles where id = '10000000-0000-0000-0000-000000000001' and organizer_rating_avg = 0 and organizer_rating_count = 0)
     or not exists (select 1 from public.airfnb_profiles where id = '10000000-0000-0000-0000-000000000005' and organizer_rating_avg = 5.0 and organizer_rating_count = 1) then
    raise exception 'organizer old/new aggregate rebind failed';
  end if;
end;
$rebind_assertions$;

rollback;
\echo 'messaging-reviews runtime: PASS'
