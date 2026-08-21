#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf '%s\n' "usage: $0 --socket SOCKET_DIRECTORY --port PORT --source-db SOURCE_DATABASE --stripe-sha256 VERIFIED_SHA256" >&2
  exit 64
}

socket_directory=""
postgres_port=""
source_database=""
stripe_sha256=""
while (($# > 0)); do
  case "$1" in
    --socket) (($# >= 2)) || usage; socket_directory="$2"; shift 2 ;;
    --port) (($# >= 2)) || usage; postgres_port="$2"; shift 2 ;;
    --source-db) (($# >= 2)) || usage; source_database="$2"; shift 2 ;;
    --stripe-sha256) (($# >= 2)) || usage; stripe_sha256="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ "$socket_directory" == /* && "$socket_directory" != "/" ]] || usage
[[ "$postgres_port" =~ ^[0-9]+$ ]] && ((postgres_port >= 1 && postgres_port <= 65535)) || usage
[[ "$source_database" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]] || usage
[[ "$source_database" != template0 && "$source_database" != template1 ]] || usage
[[ ! "$source_database" =~ ^fb_tailor_(supplier_acl|identity_runtime)_ ]] || usage
[[ "$stripe_sha256" =~ ^[0-9a-f]{64}$ ]] || usage
[[ -S "$socket_directory/.s.PGSQL.$postgres_port" ]] || {
  printf 'explicit local PostgreSQL socket is unavailable\n' >&2
  exit 66
}

for command_name in psql pg_dump createdb dropdb shasum sed awk grep mktemp; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'required local command is unavailable: %s\n' "$command_name" >&2
    exit 69
  }
done

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
identity_file="$repository_root/supabase/migrations/20260819094823_airfnb_identity_reconciliation.sql"
identity_runtime_file="$repository_root/tests/identity-reconciliation-runtime.sql"
runtime_integrity_file="$repository_root/supabase/migrations/20260820152018_airfnb_runtime_function_integrity_reconciliation.sql"
privacy_file="$repository_root/supabase/migrations/20260820153725_public_event_request_privacy_reconciliation.sql"
messaging_file="$repository_root/supabase/migrations/20260820154054_messaging_reviews_reconciliation.sql"
storage_file="$repository_root/supabase/migrations/20260820154100_storage_abuse_reconciliation.sql"
catalog_file="$repository_root/supabase/migrations/20260820154104_catalog_service_types_reconciliation.sql"
marketplace_file="$repository_root/supabase/migrations/20260820154358_marketplace_workflow_reconciliation.sql"
stripe_file="$repository_root/supabase/migrations/20260820155322_stripe_canonical_reconciliation.sql"
migration_file="$repository_root/supabase/migrations/20260820230518_supplier_acl_caller_reconciliation.sql"
runtime_file="$repository_root/tests/supplier-acl-caller-reconciliation-runtime.sql"
source_test_file="$repository_root/tests/supplier-acl-caller-reconciliation-source.test.mjs"
driver_file="$repository_root/scripts/test-supplier-acl-caller-reconciliation.sh"
artifacts=(
  "$identity_file" "$identity_runtime_file" "$runtime_integrity_file" "$privacy_file" "$messaging_file" "$storage_file"
  "$catalog_file" "$marketplace_file" "$stripe_file" "$migration_file"
  "$runtime_file" "$source_test_file" "$driver_file"
)
for required_file in "${artifacts[@]}"; do
  [[ -f "$required_file" ]] || { printf 'missing artifact: %s\n' "$required_file" >&2; exit 66; }
done

sha256_file() { shasum -a 256 "$1" | awk '{print $1}'; }
sha256_stream() { shasum -a 256 | awk '{print $1}'; }
artifact_manifest() {
  local artifact
  for artifact in "${artifacts[@]}"; do
    printf '%s  %s\n' "$(sha256_file "$artifact")" "$artifact"
  done
}

[[ "$(sha256_file "$identity_file")" == 76b7659106d4598af471c84341e961aed2dcae88746177e1be19b7c7a60c3319
   && "$(sha256_file "$identity_runtime_file")" == ddd03863f2efe2e77fde26ead30773e1785fdff3f3c11206be1a1a4b0f03c463
   && "$(sha256_file "$runtime_integrity_file")" == f1400bd3e4ac3d1d4e2c67b6cd33a0b7a551a26bfc018633c31f9c494096b24f
   && "$(sha256_file "$privacy_file")" == bc859122de962efee0a5d11d5e56be9ba7f42bc54ce097ead672241686f89fc2
   && "$(sha256_file "$messaging_file")" == 26695c1b5567a182777f15fa81249d234857fd3e608abcc6056dbdb39a6c55b8
   && "$(sha256_file "$storage_file")" == 19b02bd08d14be47b5f2ef086700bc8248be63f5ecac9b1501e6024b436d164b
   && "$(sha256_file "$catalog_file")" == 90dbaf281ea0c9209373fe16964e1aaaa34152f0272ef067fdee80f831fdc60c
   && "$(sha256_file "$marketplace_file")" == 07e6692f05aad35a9256ab514b73a446ee49c3d7c794b909c62240256ec1147d ]] || {
  printf 'official predecessor chain hash mismatch\n' >&2
  exit 65
}
[[ "$stripe_sha256" == 5c244501a3f2e7b9d5aef6fa9d40b48a101b3efe0221401e9c6207d03f927591
   && "$(sha256_file "$stripe_file")" == "$stripe_sha256" ]] || {
  printf 'independently verified Stripe hash mismatch\n' >&2
  exit 65
}

psql_source=(psql -X --no-psqlrc --host="$socket_directory" --port="$postgres_port" --dbname="$source_database" --set=ON_ERROR_STOP=1 --quiet)
[[ "$(PGOPTIONS='-c default_transaction_read_only=on' "${psql_source[@]}" --tuples-only --no-align --command='select current_database();')" == "$source_database" ]] || {
  printf 'source database connection mismatch\n' >&2
  exit 65
}
source_fingerprint() {
  PGOPTIONS='-c default_transaction_read_only=on' pg_dump --host="$socket_directory" --port="$postgres_port" \
    --dbname="$source_database" --format=plain --schema=auth --schema=public --schema=storage --no-owner \
    | sed '/^\\restrict /d; /^\\unrestrict /d' | sha256_stream
}
source_sha256_before="$(source_fingerprint)"
[[ "$source_sha256_before" == 65559343e7ffdf3795e1267425c5c6693ea79be56ef0d45ac43c39233e8b99dd ]] || {
  printf 'source database fingerprint mismatch: %s\n' "$source_sha256_before" >&2
  exit 65
}
artifact_manifest_before="$(artifact_manifest)"

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/fb-tailor-supplier-acl.XXXXXX")"
scratch_databases=()
scratch_database=""
psql_scratch=()

is_scratch_database() {
  [[ "$1" =~ ^fb_tailor_supplier_acl_[0-9]+_[0-9]+_(tamper|good)$ \
     || "$1" =~ ^fb_tailor_identity_runtime_[0-9]+_[0-9]+$ ]]
}
database_count() {
  local database_name="$1"
  is_scratch_database "$database_name" || return 1
  PGOPTIONS='-c default_transaction_read_only=on' "${psql_source[@]}" --tuples-only --no-align \
    --command="select count(*) from pg_catalog.pg_database where datname='$database_name';"
}
cleanup() {
  local exit_status=$? database_name
  trap - EXIT INT TERM
  for database_name in "${scratch_databases[@]}"; do
    if is_scratch_database "$database_name" && [[ "$database_name" != "$source_database" ]] \
       && [[ "$(database_count "$database_name")" == 1 ]]; then
      dropdb --host="$socket_directory" --port="$postgres_port" --maintenance-db=template1 -- "$database_name" || exit_status=1
    fi
  done
  find "$temporary_directory" -type f -maxdepth 1 -delete 2>/dev/null || exit_status=1
  rmdir "$temporary_directory" 2>/dev/null || exit_status=1
  exit "$exit_status"
}
trap cleanup EXIT INT TERM

create_scratch() {
  local suffix="$1"
  local identity_database="fb_tailor_identity_runtime_${$}_${RANDOM}"
  local identity_failure="$temporary_directory/identity-${suffix}.log"
  local -a psql_identity
  scratch_database="fb_tailor_supplier_acl_${$}_${RANDOM}_${suffix}"
  is_scratch_database "$identity_database" && is_scratch_database "$scratch_database" || {
    printf 'unsafe scratch name\n' >&2
    exit 65
  }
  scratch_databases+=("$identity_database" "$scratch_database")
  createdb --host="$socket_directory" --port="$postgres_port" --maintenance-db=template1 \
    --template="$source_database" -- "$identity_database"

  # Run the independently verified identity harness under its exact guarded
  # database name, including its intentional 11-of-12 rollback proof. Once
  # verified, rename that same clone to this follower's guarded prefix.
  psql_identity=(psql -X --no-psqlrc --host="$socket_directory" --port="$postgres_port" \
    --dbname="$identity_database" --set=ON_ERROR_STOP=1 --quiet)
  "${psql_identity[@]}" \
    --set=identity_runtime_database="$identity_database" \
    --set=identity_runtime_phase=setup_drift \
    --file="$identity_runtime_file" >/dev/null
  if "${psql_identity[@]}" --file="$identity_file" >"$identity_failure" 2>&1; then
    printf 'identity 11-of-12 drift unexpectedly accepted\n' >&2
    exit 1
  fi
  grep -Fq 'identity reconciliation refused: expected exactly the 12 observed catalogue services' "$identity_failure" || {
    printf 'identity predecessor failed for an unexpected reason\n' >&2
    sed -n '1,80p' "$identity_failure" >&2
    exit 1
  }
  "${psql_identity[@]}" \
    --set=identity_runtime_database="$identity_database" \
    --set=identity_runtime_phase=assert_failed_atomicity_and_prepare_good \
    --file="$identity_runtime_file" >/dev/null
  "${psql_identity[@]}" --file="$identity_file" >/dev/null
  "${psql_identity[@]}" \
    --set=identity_runtime_database="$identity_database" \
    --set=identity_runtime_phase=assert_good \
    --file="$identity_runtime_file" >/dev/null
  # Remove only harness-owned unrelated rows before continuing the cumulative
  # schema chain. The identity migration's real guard/auth-table result and
  # the twelve/five preserved production rows remain intact.
  "${psql_identity[@]}" >/dev/null <<'SQL'
delete from public.airfnb_trucks
 where slug = 'identity-runtime-unrelated-service';
delete from public.airfnb_blog_posts
 where slug = 'identity-runtime-unrelated-article';
delete from public.airfnb_blog_authors
 where id = '99999999-9999-9999-9999-999999999999';
delete from auth.users
 where id in (
   '22222222-2222-2222-2222-222222222222',
   '33333333-3333-3333-3333-333333333333',
   '44444444-4444-4444-4444-444444444444',
   '55555555-5555-5555-5555-555555555555',
   '66666666-6666-6666-6666-666666666666',
   '77777777-7777-7777-7777-777777777777',
   '88888888-8888-8888-8888-888888888888',
   '99999999-9999-9999-9999-999999999999'
 );
drop schema identity_runtime cascade;
SQL
  "${psql_source[@]}" --command="alter database \"$identity_database\" rename to \"$scratch_database\"" >/dev/null

  psql_scratch=(psql -X --no-psqlrc --host="$socket_directory" --port="$postgres_port" \
    --dbname="$scratch_database" --set=ON_ERROR_STOP=1 --quiet)
  [[ "$("${psql_scratch[@]}" --tuples-only --no-align --command='select current_database();')" == "$scratch_database" ]] || exit 65
}

apply_predecessors() {
  local predecessor
  for predecessor in "$runtime_integrity_file" "$privacy_file" "$messaging_file" "$storage_file" "$catalog_file" "$marketplace_file" "$stripe_file"; do
    "${psql_scratch[@]}" --file="$predecessor" >/dev/null
  done
  [[ "$("${psql_scratch[@]}" --tuples-only --no-align --command="select pg_catalog.md5(prosrc) from pg_catalog.pg_proc where oid='public.airfnb_reconcile_stripe_event(text,text,timestamptz,uuid,uuid,uuid,text,bigint,text,text,bigint)'::regprocedure")" == 296b93ed41a788acf9ecb099e78695ff ]] || {
    printf 'Stripe RPC body contract mismatch after predecessor apply\n' >&2
    exit 65
  }
}

candidate_state_fingerprint() {
  "${psql_scratch[@]}" --tuples-only --no-align --field-separator='|' <<'SQL' | sha256_stream
select 'function',p.oid::regprocedure::text,p.proowner::text,p.prosecdef::text,p.provolatile::text,
       coalesce(p.proconfig::text,'')||':'||coalesce(p.proacl::text,'')||':'||pg_catalog.md5(p.prosrc)
  from pg_catalog.pg_proc p
 where p.pronamespace='public'::regnamespace
   and p.proname in (
     'airfnb_supplier_services','airfnb_public_service_detail','airfnb_invitation_candidates',
     'airfnb_invite_request_services','airfnb_booking_service_context',
     'airfnb_request_application_service_context','airfnb_supplier_export_data',
     'airfnb_reconcile_stripe_event'
   )
union all
select 'relation',c.relname,c.relowner::text,c.relrowsecurity::text,c.relforcerowsecurity::text,coalesce(c.relacl::text,'')
  from pg_catalog.pg_class c
 where c.oid in (
   'public.airfnb_trucks'::regclass,'public.airfnb_truck_images'::regclass,
   'public.airfnb_truck_categories'::regclass,'public.airfnb_categories'::regclass
 )
union all
select 'policy',policy.polname,policy.polcmd::text,policy.polpermissive::text,
       policy.polroles::text,
       pg_catalog.md5(pg_catalog.pg_get_expr(policy.polwithcheck,policy.polrelid))
  from pg_catalog.pg_policy as policy
 where policy.polrelid='public.airfnb_organizer_reviews'::regclass
   and policy.polname='airfnb_org_reviews_participant_insert'
order by 1,2,3,4,5,6;
SQL
}

prove_predecessor_review_denial() {
  "${psql_scratch[@]}" >/dev/null <<'SQL'
begin;
insert into auth.users(id,email,raw_user_meta_data) values
 ('f2640000-0000-4000-8000-000000000001','acl-predecessor-organizer@example.invalid','{}'),
 ('f2640000-0000-4000-8000-000000000002','acl-predecessor-owner@example.invalid','{}');
update public.airfnb_profiles set role=case when id='f2640000-0000-4000-8000-000000000001'
 then 'organizer'::public.airfnb_user_role else 'owner'::public.airfnb_user_role end
where id in ('f2640000-0000-4000-8000-000000000001','f2640000-0000-4000-8000-000000000002');
insert into public.airfnb_trucks(id,owner_id,slug,name,status,service_type)
values ('f2640000-0000-4000-8000-000000000010','f2640000-0000-4000-8000-000000000002','acl-predecessor-review','ACL predecessor review','active','food_truck');
insert into public.airfnb_events(id,organizer_id,title,kind,start_at,end_at,expected_pax,status)
values ('f2640000-0000-4000-8000-000000000020','f2640000-0000-4000-8000-000000000001','ACL predecessor event','corporate','2035-08-20 12:00:00+00','2035-08-20 18:00:00+00',100,'confirmed');
insert into public.airfnb_bookings(id,event_id,organizer_id,status,starts_at,ends_at,pax_count,total_amount,currency)
values ('f2640000-0000-4000-8000-000000000030','f2640000-0000-4000-8000-000000000020','f2640000-0000-4000-8000-000000000001','completed','2035-08-20 12:00:00+00','2035-08-20 18:00:00+00',100,500,'EUR');
insert into public.airfnb_booking_trucks(booking_id,truck_id,agreed_price)
values ('f2640000-0000-4000-8000-000000000030','f2640000-0000-4000-8000-000000000010',500);
select pg_catalog.set_config('request.jwt.claim.sub','f2640000-0000-4000-8000-000000000002',true);
select pg_catalog.set_config('request.jwt.claim.role','authenticated',true);
set local role authenticated;
do $expected_predecessor_failure$
begin
  begin
    insert into public.airfnb_organizer_reviews(
      booking_id,truck_id,rating_reliability,rating_communication,rating_payment,body
    ) values (
      'f2640000-0000-4000-8000-000000000030','f2640000-0000-4000-8000-000000000010',5,5,5,'Expected predecessor ACL denial'
    );
    raise exception 'predecessor organizer review unexpectedly succeeded';
  exception when sqlstate '42501' then null;
  end;
end
$expected_predecessor_failure$;
reset role;
rollback;
SQL
  printf 'PREDECESSOR_REVIEW_42501_PASS database=%s\n' "$scratch_database"
}

create_scratch tamper
apply_predecessors
prove_predecessor_review_denial
"${psql_scratch[@]}" --command="alter function public.airfnb_reconcile_stripe_event(text,text,timestamptz,uuid,uuid,uuid,text,bigint,text,text,bigint) security invoker" >/dev/null
tamper_before="$(candidate_state_fingerprint)"
failure_log="$temporary_directory/tamper-failure.log"
if "${psql_scratch[@]}" --file="$migration_file" >"$failure_log" 2>&1; then
  printf 'drifted Stripe predecessor unexpectedly accepted\n' >&2
  exit 1
fi
grep -Fq 'supplier ACL reconciliation refused: Stripe predecessor drifted' "$failure_log" || {
  printf 'tamper candidate failed for an unexpected reason\n' >&2
  sed -n '1,80p' "$failure_log" >&2
  exit 1
}
[[ "$(candidate_state_fingerprint)" == "$tamper_before" ]] || {
  printf 'failed tamper apply left partial ACL/function state\n' >&2
  exit 1
}
[[ "$("${psql_scratch[@]}" --tuples-only --no-align --command="select count(*) from pg_catalog.pg_proc where pronamespace='public'::regnamespace and proname in ('airfnb_supplier_services','airfnb_public_service_detail','airfnb_invitation_candidates','airfnb_invite_request_services','airfnb_booking_service_context','airfnb_request_application_service_context','airfnb_supplier_export_data')")" == 0 ]] || {
  printf 'tamper rollback left follower functions\n' >&2
  exit 1
}
printf 'TAMPER_ROLLBACK_PASS database=%s\n' "$scratch_database"

create_scratch good
apply_predecessors
"${psql_scratch[@]}" --file="$migration_file" >/dev/null
candidate_before_reapply="$(candidate_state_fingerprint)"
"${psql_scratch[@]}" --file="$migration_file" >/dev/null
candidate_after_reapply="$(candidate_state_fingerprint)"
[[ "$candidate_after_reapply" == "$candidate_before_reapply" ]] || {
  printf 'candidate reapply changed final state\n' >&2
  exit 1
}
"${psql_scratch[@]}" --file="$runtime_file" >/dev/null
printf 'GOOD_REAPPLY_RUNTIME_PASS database=%s state=%s\n' "$scratch_database" "$candidate_after_reapply"

"${psql_scratch[@]}" >/dev/null <<'SQL'
insert into auth.users(id,email,raw_user_meta_data) values
 ('f2680000-0000-4000-8000-000000000001','acl-race-organizer@example.invalid','{}'),
 ('f2680000-0000-4000-8000-000000000002','acl-race-supplier@example.invalid','{}');
update public.airfnb_profiles set role=case when id='f2680000-0000-4000-8000-000000000001'
 then 'organizer'::public.airfnb_user_role else 'owner'::public.airfnb_user_role end
where id in ('f2680000-0000-4000-8000-000000000001','f2680000-0000-4000-8000-000000000002');
insert into public.airfnb_trucks(id,owner_id,slug,name,status,service_type,base_city,capacity,cuisine_types)
values
 ('f2680000-0000-4000-8000-000000000010','f2680000-0000-4000-8000-000000000002','acl-race-one','ACL Race One','active','food_truck','Lisboa',200,array['portuguesa']),
 ('f2680000-0000-4000-8000-000000000011','f2680000-0000-4000-8000-000000000002','acl-race-two','ACL Race Two','active','bar','Lisboa',200,array['portuguesa']);
insert into public.airfnb_event_requests(id,organizer_id,title,start_at,end_at,expected_pax,slots_needed,status,visibility,city,desired_cuisines)
values ('f2680000-0000-4000-8000-000000000100','f2680000-0000-4000-8000-000000000001','ACL invitation race',
 '2035-08-20 12:00:00+00','2035-08-20 18:00:00+00',100,2,'open','invite_only','Lisboa',array['portuguesa']);
SQL

race_sql="begin; set local role authenticated; select pg_catalog.set_config('request.jwt.claim.sub','f2680000-0000-4000-8000-000000000001',true); select pg_catalog.set_config('request.jwt.claim.role','authenticated',true); select pg_catalog.count(*) from public.airfnb_invite_request_services('f2680000-0000-4000-8000-000000000100',array['f2680000-0000-4000-8000-000000000010','f2680000-0000-4000-8000-000000000011']::uuid[]); commit;"
race_one="$temporary_directory/race-one.log"
race_two="$temporary_directory/race-two.log"
"${psql_scratch[@]}" --tuples-only --no-align --command="$race_sql" >"$race_one" &
race_one_pid=$!
"${psql_scratch[@]}" --tuples-only --no-align --command="$race_sql" >"$race_two" &
race_two_pid=$!
wait "$race_one_pid"
wait "$race_two_pid"
race_counts="$(grep -E '^[0-9]+$' "$race_one" "$race_two" | awk -F: '{sum += $NF; seen += 1} END {print seen ":" sum}')"
[[ "$race_counts" == 2:2 ]] || {
  printf 'invitation race return counts mismatch: %s\n' "$race_counts" >&2
  exit 1
}
race_state="$("${psql_scratch[@]}" --tuples-only --no-align --field-separator=':' <<'SQL'
select
 (select count(*) from public.airfnb_request_invitations where request_id='f2680000-0000-4000-8000-000000000100'),
 (select count(*) from public.airfnb_notifications where kind='request.invited' and payload->>'request_id'='f2680000-0000-4000-8000-000000000100');
SQL
)"
[[ "$race_state" == 2:2 ]] || { printf 'invitation race side effects mismatch: %s\n' "$race_state" >&2; exit 1; }
printf 'INVITATION_CONCURRENCY_PASS return_sessions=%s state=%s\n' "$race_counts" "$race_state"

source_sha256_after="$(source_fingerprint)"
artifact_manifest_after="$(artifact_manifest)"
[[ "$source_sha256_after" == "$source_sha256_before" ]] || { printf 'source fingerprint changed\n' >&2; exit 1; }
[[ "$artifact_manifest_after" == "$artifact_manifest_before" ]] || { printf 'candidate artifacts changed during driver\n' >&2; exit 1; }

for database_name in "${scratch_databases[@]}"; do
  is_scratch_database "$database_name" || exit 65
  if [[ "$(database_count "$database_name")" == 1 ]]; then
    dropdb --host="$socket_directory" --port="$postgres_port" --maintenance-db=template1 -- "$database_name"
  fi
done
scratch_databases=()
residue="$(PGOPTIONS='-c default_transaction_read_only=on' "${psql_source[@]}" --tuples-only --no-align --command="select count(*) from pg_catalog.pg_database where datname like 'fb_tailor_supplier_acl_%' or datname like 'fb_tailor_identity_runtime_%'")"
[[ "$residue" == 0 ]] || { printf 'scratch database residue detected: %s\n' "$residue" >&2; exit 1; }
trap - EXIT INT TERM
find "$temporary_directory" -type f -maxdepth 1 -delete
rmdir "$temporary_directory"

printf 'SOURCE_FINGERPRINT_PASS before=%s after=%s\n' "$source_sha256_before" "$source_sha256_after"
printf 'ZERO_SCRATCH_RESIDUE_PASS count=%s\n' "$residue"
printf 'SUPPLIER_ACL_CALLER_RECONCILIATION_DRIVER_PASS migration_sha256=%s stripe_sha256=%s\n' \
  "$(sha256_file "$migration_file")" "$stripe_sha256"
