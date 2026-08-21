\set ON_ERROR_STOP on

begin;

grant usage on schema public, auth to anon, authenticated, service_role;

insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data)
values
  ('fa210000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'foreign-app@example.invalid', '{"role":"staff"}', '{"role":"admin","full_name":"Foreign App"}'),
  ('fa210000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner@example.invalid', '{}', '{}'),
  ('fa210000-0000-4000-8000-000000000003', '00000000-0000-0000-8000-000000000000', 'authenticated', 'authenticated', 'organizer@example.invalid', '{}', '{}'),
  ('fa210000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cross-user@example.invalid', '{}', '{}');

select (select count(*) from public.airfnb_profiles
         where id::text like 'fa210000-0000-4000-8000-%') = 0 as foreign_app_has_no_implicit_profile
\gset
\if :foreign_app_has_no_implicit_profile
\else
  \echo foreign_app isolation failed
  \quit 1
\endif

set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', 'fa210000-0000-4000-8000-000000000002', true);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
select (public.airfnb_ensure_profile('  Owner Person  ', 'pt-PT')).role is null as owner_bootstrap_null_role
\gset
select (public.airfnb_ensure_profile('Ignored Replacement', 'en')).full_name = 'Owner Person' as bootstrap_idempotent
\gset
select (public.airfnb_claim_role('owner')).role = 'owner' as owner_claimed
\gset
select (public.airfnb_claim_role('owner')).role = 'owner' as owner_claim_idempotent
\gset
reset role;

\if :owner_bootstrap_null_role
\else
  \quit 1
\endif
\if :bootstrap_idempotent
\else
  \quit 1
\endif
\if :owner_claimed
\else
  \quit 1
\endif
\if :owner_claim_idempotent
\else
  \quit 1
\endif

\set ON_ERROR_STOP off
set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', 'fa210000-0000-4000-8000-000000000002', true);
savepoint expected_owner_switch;
select public.airfnb_claim_role('organizer');
\set owner_switch_state :SQLSTATE
rollback to savepoint expected_owner_switch;
savepoint expected_admin;
select public.airfnb_claim_role('admin');
\set admin_state :SQLSTATE
rollback to savepoint expected_admin;
savepoint expected_staff;
select public.airfnb_claim_role('staff');
\set staff_state :SQLSTATE
rollback to savepoint expected_staff;
savepoint expected_short_name;
select public.airfnb_ensure_profile('x', 'pt-PT');
\set short_name_state :SQLSTATE
rollback to savepoint expected_short_name;
savepoint expected_locale;
select public.airfnb_ensure_profile(null, 'fr');
\set locale_state :SQLSTATE
rollback to savepoint expected_locale;
savepoint expected_direct_role;
update public.airfnb_profiles set role = 'admin'
 where id = 'fa210000-0000-4000-8000-000000000002';
\set direct_role_state :SQLSTATE
rollback to savepoint expected_direct_role;
savepoint expected_tombstone_read;
select count(*) from public.airfnb_membership_tombstones;
\set tombstone_read_state :SQLSTATE
rollback to savepoint expected_tombstone_read;
reset role;

set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', 'fa210000-0000-4000-8000-000000000004', true);
savepoint expected_cross_user;
select public.airfnb_claim_role('owner');
\set cross_user_state :SQLSTATE
rollback to savepoint expected_cross_user;
reset role;

set local role anon;
savepoint expected_anonymous;
select public.airfnb_ensure_profile(null, 'pt-PT');
\set anonymous_state :SQLSTATE
rollback to savepoint expected_anonymous;
reset role;

set local role service_role;
select pg_catalog.set_config('request.jwt.claim.sub', 'fa210000-0000-4000-8000-000000000004', true);
savepoint expected_service_role;
select public.airfnb_ensure_profile(null, 'pt-PT');
\set service_role_state :SQLSTATE
rollback to savepoint expected_service_role;
reset role;
\set ON_ERROR_STOP on

select (
  :'owner_switch_state' = '42501'
  and :'admin_state' = '42501'
  and :'staff_state' = '42501'
  and :'short_name_state' = '22023'
  and :'locale_state' = '22023'
  and :'direct_role_state' = '42501'
  and :'tombstone_read_state' = '42501'
  and :'cross_user_state' = 'P0002'
  and :'anonymous_state' = '42501'
  and :'service_role_state' = '42501'
) as adversarial_role_matrix_ok
\gset
\if :adversarial_role_matrix_ok
\else
  \echo adversarial matrix failed
  \quit 1
\endif

set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', 'fa210000-0000-4000-8000-000000000002', true);
update public.airfnb_profiles set full_name = 'Editable Owner'
 where id = 'fa210000-0000-4000-8000-000000000002';
select full_name = 'Editable Owner' as editable_profile_column_ok
  from public.airfnb_profiles
 where id = 'fa210000-0000-4000-8000-000000000002'
\gset
reset role;
\if :editable_profile_column_ok
\else
  \echo editable profile column ACL failed
  \quit 1
\endif

set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', 'fa210000-0000-4000-8000-000000000001', true);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
select (public.airfnb_ensure_profile(null, 'en')).role is null as metadata_does_not_claim_role
\gset
select (public.airfnb_claim_role('organizer')).role = 'organizer' as organizer_claimed
\gset
reset role;

\if :metadata_does_not_claim_role
\else
  \quit 1
\endif
\if :organizer_claimed
\else
  \quit 1
\endif

set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', 'fa210000-0000-4000-8000-000000000001', true);
select public.airfnb_self_delete();
select public.airfnb_self_delete();
select public.airfnb_self_delete_storage_prefixes() = '{}'::uuid[] as self_delete_prefixes_retryable
\gset
reset role;

\if :self_delete_prefixes_retryable
\else
  \echo self_delete Storage prefixes are not retryable
  \quit 1
\endif

select (
  exists (
    select 1 from public.airfnb_membership_tombstones
     where user_id = 'fa210000-0000-4000-8000-000000000001'
       and storage_truck_ids = '{}'::uuid[]
  )
  and not exists (
    select 1 from public.airfnb_profiles
     where id = 'fa210000-0000-4000-8000-000000000001'
  )
  and exists (
    select 1 from auth.users
     where id = 'fa210000-0000-4000-8000-000000000001'
  )
) as self_delete_tombstone_auth_preserved
\gset
\if :self_delete_tombstone_auth_preserved
\else
  \echo self_delete tombstone or shared auth preservation failed
  \quit 1
\endif

\set ON_ERROR_STOP off
set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', 'fa210000-0000-4000-8000-000000000001', true);
savepoint expected_rejoin;
select public.airfnb_ensure_profile('Rejoin Attempt', 'pt-PT');
\set rejoin_state :SQLSTATE
rollback to savepoint expected_rejoin;
savepoint expected_reclaim;
select public.airfnb_claim_role('organizer');
\set reclaim_state :SQLSTATE
rollback to savepoint expected_reclaim;
select public.airfnb_apply_referral('ABCDEF') as tombstone_referral_blocked
\gset
reset role;
\set ON_ERROR_STOP on

select (
  :'rejoin_state' = '42501'
  and :'reclaim_state' = '42501'
  and :'tombstone_referral_blocked' = 'f'
) as tombstone_rejoin_blocked
\gset
\if :tombstone_rejoin_blocked
\else
  \echo tombstone rejoin or referral block failed
  \quit 1
\endif

select (
  (select count(*) from public.airfnb_profiles where id = 'fa210000-0000-4000-8000-000000000001') = 0
  and (select count(*) from public.airfnb_profiles where id = 'fa210000-0000-4000-8000-000000000002') = 1
  and (select count(*) from public.airfnb_profiles where id = 'fa210000-0000-4000-8000-000000000003') = 0
  and (select count(*) from public.airfnb_profiles where id = 'fa210000-0000-4000-8000-000000000004') = 0
  and (select count(*) from auth.users where id::text like 'fa210000-0000-4000-8000-%') = 4
  and (select count(*) from public.airfnb_membership_tombstones where user_id::text like 'fa210000-0000-4000-8000-%') = 1
) as exact_profile_cardinality_ok
\gset
\if :exact_profile_cardinality_ok
\else
  \quit 1
\endif

rollback;
