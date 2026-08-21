#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf '%s\n' "usage: $0 --socket SOCKET_DIRECTORY --port PORT --source-db SOURCE_DATABASE" >&2
  exit 64
}

socket_directory=""
postgres_port=""
source_database=""
while (($# > 0)); do
  case "$1" in
    --socket) (($# >= 2)) || usage; socket_directory="$2"; shift 2 ;;
    --port) (($# >= 2)) || usage; postgres_port="$2"; shift 2 ;;
    --source-db) (($# >= 2)) || usage; source_database="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ "$socket_directory" == /* && "$socket_directory" != "/" ]] || usage
[[ "$postgres_port" =~ ^[0-9]+$ ]] && ((postgres_port >= 1 && postgres_port <= 65535)) || usage
[[ "$source_database" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]] || usage
[[ "$source_database" != template0 && "$source_database" != template1 ]] || usage
[[ ! "$source_database" =~ ^fb_tailor_stripe_ ]] || usage
[[ -S "$socket_directory/.s.PGSQL.$postgres_port" ]] || {
  printf 'explicit local PostgreSQL socket is unavailable\n' >&2; exit 66;
}
for command_name in psql pg_dump createdb dropdb shasum sed awk mktemp; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'required local command is unavailable: %s\n' "$command_name" >&2; exit 69;
  }
done

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
runtime_integrity_file="$repository_root/supabase/migrations/20260820152018_airfnb_runtime_function_integrity_reconciliation.sql"
privacy_file="$repository_root/supabase/migrations/20260820153725_public_event_request_privacy_reconciliation.sql"
messaging_file="$repository_root/supabase/migrations/20260820154054_messaging_reviews_reconciliation.sql"
storage_file="$repository_root/supabase/migrations/20260820154100_storage_abuse_reconciliation.sql"
catalog_file="$repository_root/supabase/migrations/20260820154104_catalog_service_types_reconciliation.sql"
marketplace_file="$repository_root/supabase/migrations/20260820154358_marketplace_workflow_reconciliation.sql"
migration_file="$repository_root/supabase/migrations/20260820155322_stripe_canonical_reconciliation.sql"
runtime_file="$repository_root/tests/stripe-canonical-reconciliation-runtime.sql"
source_test_file="$repository_root/tests/stripe-canonical-reconciliation-source.test.mjs"
driver_file="$repository_root/scripts/test-stripe-canonical-reconciliation.sh"
artifacts=(
  "$runtime_integrity_file" "$privacy_file" "$messaging_file" "$storage_file"
  "$catalog_file" "$marketplace_file" "$migration_file" "$runtime_file"
  "$source_test_file" "$driver_file"
)
for required_file in "${artifacts[@]}"; do
  [[ -f "$required_file" ]] || { printf 'missing artifact: %s\n' "$required_file" >&2; exit 66; }
done

sha256_file() { shasum -a 256 "$1" | awk '{print $1}'; }
sha256_stream() { shasum -a 256 | awk '{print $1}'; }
artifact_manifest() {
  local artifact
  for artifact in "${artifacts[@]}"; do printf '%s  %s\n' "$(sha256_file "$artifact")" "$artifact"; done
}

[[ "$(sha256_file "$runtime_integrity_file")" == f1400bd3e4ac3d1d4e2c67b6cd33a0b7a551a26bfc018633c31f9c494096b24f
   && "$(sha256_file "$privacy_file")" == bc859122de962efee0a5d11d5e56be9ba7f42bc54ce097ead672241686f89fc2
   && "$(sha256_file "$messaging_file")" == 26695c1b5567a182777f15fa81249d234857fd3e608abcc6056dbdb39a6c55b8
   && "$(sha256_file "$storage_file")" == 19b02bd08d14be47b5f2ef086700bc8248be63f5ecac9b1501e6024b436d164b
   && "$(sha256_file "$catalog_file")" == 90dbaf281ea0c9209373fe16964e1aaaa34152f0272ef067fdee80f831fdc60c
   && "$(sha256_file "$marketplace_file")" == 07e6692f05aad35a9256ab514b73a446ee49c3d7c794b909c62240256ec1147d ]] || {
  printf 'official predecessor chain hash mismatch\n' >&2; exit 65;
}

psql_source=(psql -X --no-psqlrc --host="$socket_directory" --port="$postgres_port" --dbname="$source_database" --set=ON_ERROR_STOP=1 --quiet)
[[ "$(PGOPTIONS='-c default_transaction_read_only=on' "${psql_source[@]}" --tuples-only --no-align --command='select current_database();')" == "$source_database" ]] || {
  printf 'source database connection mismatch\n' >&2; exit 65;
}
source_fingerprint() {
  PGOPTIONS='-c default_transaction_read_only=on' pg_dump --host="$socket_directory" --port="$postgres_port" \
    --dbname="$source_database" --format=plain --schema=auth --schema=public --schema=storage --no-owner \
    | sed '/^\\restrict /d; /^\\unrestrict /d' | sha256_stream
}
source_sha256_before="$(source_fingerprint)"
[[ "$source_sha256_before" == 65559343e7ffdf3795e1267425c5c6693ea79be56ef0d45ac43c39233e8b99dd ]] || {
  printf 'source database fingerprint mismatch: %s\n' "$source_sha256_before" >&2; exit 65;
}
artifact_manifest_before="$(artifact_manifest)"

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/fb-tailor-stripe.XXXXXX")"
scratch_databases=()
scratch_database=""
psql_scratch=()

is_scratch_database() { [[ "$1" =~ ^fb_tailor_stripe_[0-9]+_[0-9]+_(old|legacy)$ ]]; }
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
  scratch_database="fb_tailor_stripe_${$}_${RANDOM}_${suffix}"
  is_scratch_database "$scratch_database" || { printf 'unsafe scratch name\n' >&2; exit 65; }
  scratch_databases+=("$scratch_database")
  createdb --host="$socket_directory" --port="$postgres_port" --maintenance-db=template1 \
    --template="$source_database" -- "$scratch_database"
  psql_scratch=(psql -X --no-psqlrc --host="$socket_directory" --port="$postgres_port" \
    --dbname="$scratch_database" --set=ON_ERROR_STOP=1 --quiet)
  [[ "$("${psql_scratch[@]}" --tuples-only --no-align --command='select current_database();')" == "$scratch_database" ]] || exit 65
}

apply_predecessors() {
  local predecessor
  for predecessor in "$runtime_integrity_file" "$privacy_file" "$messaging_file" "$storage_file" "$catalog_file" "$marketplace_file"; do
    "${psql_scratch[@]}" --file="$predecessor" >/dev/null
  done
  local contract
  contract="$("${psql_scratch[@]}" --tuples-only --no-align <<'SQL'
select pg_catalog.concat_ws(':',
  pg_catalog.md5((select prosrc from pg_catalog.pg_proc where oid='public.airfnb_reconcile_stripe_event(text,text,timestamp with time zone,uuid,uuid,uuid,text,bigint,text,text,bigint)'::regprocedure)),
  pg_catalog.md5((select prosrc from pg_catalog.pg_proc where oid='public.airfnb_supplier_lock_fee(uuid)'::regprocedure)),
  (select count(*) from pg_catalog.pg_attribute where attrelid='public.airfnb_payments'::regclass and attnum>0 and not attisdropped),
  (select count(*) from pg_catalog.pg_policy where polrelid='public.airfnb_stripe_events'::regclass)
);
SQL
)"
  [[ "$contract" == "8ed2d10c58778e53fd40ce9b4628a42d:e73cb472f9bcc4eff83ced6b3357b47d:15:0" ]] || {
    printf 'exact predecessor contract mismatch: %s\n' "$contract" >&2; exit 65;
  }
}

stripe_state_fingerprint() {
  "${psql_scratch[@]}" --tuples-only --no-align --field-separator='|' <<'SQL' | sha256_stream
select 'relation',c.relname,c.relowner::text,c.relrowsecurity::text,c.relforcerowsecurity::text,coalesce(c.relacl::text,'')
  from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relname in ('airfnb_payments','airfnb_lock_fees','airfnb_stripe_events')
union all
select 'function',p.oid::regprocedure::text,p.proowner::text,p.prosecdef::text,p.provolatile::text,
       coalesce(p.proconfig::text,'')||':'||coalesce(p.proacl::text,'')||':'||pg_catalog.md5(p.prosrc)
  from pg_catalog.pg_proc p where p.oid=pg_catalog.to_regprocedure(
    'public.airfnb_reconcile_stripe_event(text,text,timestamp with time zone,uuid,uuid,uuid,text,bigint,text,text,bigint)')
union all
select 'constraint',c.relname,co.conname,co.contype::text,pg_catalog.pg_get_constraintdef(co.oid,true),''
  from pg_catalog.pg_constraint co join pg_catalog.pg_class c on c.oid=co.conrelid
 where co.conrelid in ('public.airfnb_payments'::regclass,'public.airfnb_lock_fees'::regclass,'public.airfnb_stripe_events'::regclass)
order by 1,2,3,4,5,6;
SQL
}

apply_candidate_and_reapply() {
  "${psql_scratch[@]}" --file="$migration_file" >/dev/null
  local final_before final_after
  final_before="$(stripe_state_fingerprint)"
  "${psql_scratch[@]}" --file="$migration_file" >/dev/null
  final_after="$(stripe_state_fingerprint)"
  [[ "$final_after" == "$final_before" ]] || { printf 'candidate reapply changed final state\n' >&2; exit 1; }
  "${psql_scratch[@]}" --file="$runtime_file" >/dev/null
}

run_drift_and_rollback_proof() {
  local before after failure_log="$temporary_directory/intentional-failure.log"
  before="$(stripe_state_fingerprint)"
  "${psql_scratch[@]}" >/dev/null <<'SQL'
create schema stripe_reconciliation_sabotage;
create function stripe_reconciliation_sabotage.fail_after_ddl() returns event_trigger
language plpgsql set search_path=pg_catalog as $$
begin
  if exists (
    select 1 from pg_catalog.pg_event_trigger_ddl_commands()
     where command_tag = 'CREATE FUNCTION'
       and object_identity like 'public.airfnb_reconcile_stripe_event%'
  ) then
    raise exception 'intentional stripe reconciliation rollback proof';
  end if;
end $$;
create event trigger stripe_reconciliation_sabotage_trigger on ddl_command_end
execute function stripe_reconciliation_sabotage.fail_after_ddl();
SQL
  if "${psql_scratch[@]}" --file="$migration_file" >"$failure_log" 2>&1; then
    printf 'intentional rollback migration unexpectedly succeeded\n' >&2; exit 1
  fi
  grep -Fq 'intentional stripe reconciliation rollback proof' "$failure_log" || {
    printf 'intentional rollback failed for a different reason\n' >&2; exit 1;
  }
  "${psql_scratch[@]}" --command='drop event trigger stripe_reconciliation_sabotage_trigger' \
    --command='drop schema stripe_reconciliation_sabotage cascade' >/dev/null
  after="$(stripe_state_fingerprint)"
  [[ "$after" == "$before" ]] || { printf 'failed migration left partial state\n' >&2; exit 1; }
}

downgrade_to_exact_legacy() {
  "${psql_scratch[@]}" >/dev/null <<'SQL'
begin;
drop function public.airfnb_reconcile_stripe_event(text,text,timestamptz,uuid,uuid,uuid,text,bigint,text,text,bigint);
drop table public.airfnb_stripe_events;
alter table public.airfnb_payments
  drop constraint airfnb_payments_provider_ref_key,
  drop constraint airfnb_payments_lock_fee_key,
  drop constraint airfnb_payments_refunded_amount_bounds,
  drop column application_id,
  drop column lock_fee_id,
  drop column refunded_amount,
  drop column last_provider_event_at;
alter table public.airfnb_lock_fees drop constraint airfnb_lock_fees_provider_ref_key;
create unique index airfnb_payments_provider_ref_unique on public.airfnb_payments(provider_ref) where provider_ref is not null;
create unique index airfnb_lock_fees_provider_ref_uniq on public.airfnb_lock_fees(provider_ref) where provider_ref is not null;
revoke all on table public.airfnb_payments from service_role;
drop policy if exists airfnb_payments_write on public.airfnb_payments;
create policy airfnb_payments_write on public.airfnb_payments for all
  using (public.airfnb_is_admin()) with check (public.airfnb_is_admin());
commit;
SQL
}

setup_concurrency_fixture() {
  "${psql_scratch[@]}" >/dev/null <<'SQL'
insert into auth.users(id,email,raw_user_meta_data) values
 ('f2670000-0000-4000-8000-000000000001','race-organizer@example.invalid','{}'),
 ('f2670000-0000-4000-8000-000000000002','race-supplier@example.invalid','{}');
update public.airfnb_profiles set role=case when id='f2670000-0000-4000-8000-000000000001'
 then 'organizer'::public.airfnb_user_role else 'owner'::public.airfnb_user_role end
where id in ('f2670000-0000-4000-8000-000000000001','f2670000-0000-4000-8000-000000000002');
insert into public.airfnb_trucks(id,owner_id,slug,name,status,service_type)
values ('f2670000-0000-4000-8000-000000000010','f2670000-0000-4000-8000-000000000002','stripe-race','Stripe Race','active','food_truck');
insert into public.airfnb_event_requests(id,organizer_id,title,start_at,expected_pax,slots_needed,status,visibility)
select ('f2670000-0000-4000-8000-'||pg_catalog.lpad(n::text,12,'0'))::uuid,
 'f2670000-0000-4000-8000-000000000001','Race '||n,pg_catalog.now()+interval '2 days',100,1,'awarded','public'
from pg_catalog.generate_series(100,105) n;
insert into public.airfnb_applications(id,request_id,truck_id,proposed_price,status,created_at,updated_at)
select ('f2670000-0000-4000-8000-'||pg_catalog.lpad((n+100)::text,12,'0'))::uuid,
 ('f2670000-0000-4000-8000-'||pg_catalog.lpad(n::text,12,'0'))::uuid,
 'f2670000-0000-4000-8000-000000000010',500,'accepted',pg_catalog.now()-interval '10 minutes',pg_catalog.now()
from pg_catalog.generate_series(100,105) n;
insert into public.airfnb_bookings(id,organizer_id,status,starts_at,total_amount,currency,application_id,created_at,updated_at)
select ('f2670000-0000-4000-8000-'||pg_catalog.lpad((n+200)::text,12,'0'))::uuid,
 'f2670000-0000-4000-8000-000000000001','pending_lock_fee',pg_catalog.now()+interval '2 days',500,'EUR',
 ('f2670000-0000-4000-8000-'||pg_catalog.lpad((n+100)::text,12,'0'))::uuid,
 pg_catalog.now()-interval '10 minutes',pg_catalog.now()
from pg_catalog.generate_series(100,105) n;
insert into public.airfnb_lock_fees(id,application_id,amount,currency,due_until,status,created_at,platform_fee,organizer_share)
select ('f2670000-0000-4000-8000-'||pg_catalog.lpad((n+300)::text,12,'0'))::uuid,
 ('f2670000-0000-4000-8000-'||pg_catalog.lpad((n+100)::text,12,'0'))::uuid,
 50,'EUR',case when n=104 then pg_catalog.now()-interval '1 minute' else pg_catalog.now()+interval '1 hour' end,
 'pending',pg_catalog.now()-interval '10 minutes',25,25
from pg_catalog.generate_series(100,105) n;
SQL
}

rpc_sql() {
  local event_id="$1" application_suffix="$2" fee_suffix="$3" booking_suffix="$4" provider="$5" type="$6" refunded="$7" event_offset="$8"
  printf "set role service_role; select public.airfnb_reconcile_stripe_event('%s','%s',(select created_at+interval '%s' from public.airfnb_lock_fees where id='f2670000-0000-4000-8000-%012d'),'f2670000-0000-4000-8000-%012d','f2670000-0000-4000-8000-%012d','f2670000-0000-4000-8000-%012d','%s',5000,'EUR','%s',%d);" \
    "$event_id" "$type" "$event_offset" "$fee_suffix" "$application_suffix" "$fee_suffix" "$booking_suffix" "$provider" \
    "$([[ "$type" == charge.refunded ]] && printf succeeded || printf paid)" "$refunded"
}

run_pair() {
  local label="$1" sql_a="$2" sql_b="$3"
  local log_a="$temporary_directory/${label}-a.log" log_b="$temporary_directory/${label}-b.log"
  local status_a=0 status_b=0 pid_a pid_b
  "${psql_scratch[@]}" --command="$sql_a" >"$log_a" 2>&1 &
  pid_a=$!
  "${psql_scratch[@]}" --command="$sql_b" >"$log_b" 2>&1 &
  pid_b=$!
  wait "$pid_a" || status_a=$?
  wait "$pid_b" || status_b=$?
  printf '%s:%s\n' "$status_a" "$status_b"
}

run_concurrency_matrix() {
  setup_concurrency_fixture
  local statuses
  statuses="$(run_pair duplicate \
    "$(rpc_sql evt-race-duplicate 200 400 300 pi-race-duplicate checkout.session.completed 0 '0 seconds')" \
    "$(rpc_sql evt-race-duplicate 200 400 300 pi-race-duplicate checkout.session.completed 0 '0 seconds')")"
  [[ "$statuses" == 0:0 ]] || { printf 'concurrent duplicate failed: %s\n' "$statuses" >&2; exit 1; }
  [[ "$("${psql_scratch[@]}" --tuples-only --no-align --command="select count(*) from public.airfnb_payments where provider_ref='pi-race-duplicate';")" == 1 ]] || exit 1
  printf 'CONCURRENT_DUPLICATE_VERIFIED\n'

  statuses="$(run_pair provider \
    "$(rpc_sql evt-race-provider-a 201 401 301 pi-race-shared checkout.session.completed 0 '0 seconds')" \
    "$(rpc_sql evt-race-provider-b 202 402 302 pi-race-shared checkout.session.completed 0 '0 seconds')")"
  [[ "$statuses" == 0:1 || "$statuses" == 1:0 ]] || { printf 'provider binding race unexpected: %s\n' "$statuses" >&2; exit 1; }
  [[ "$("${psql_scratch[@]}" --tuples-only --no-align --command="select count(*) from public.airfnb_payments where provider_ref='pi-race-shared';")" == 1 ]] || exit 1
  printf 'CONCURRENT_PROVIDER_BINDING_VERIFIED\n'

  # A payment timestamp inside the fee window races the stale-fee sweeper. One
  # coherent terminal path must win; no ledger/payment may be partial.
  local event_time
  event_time="$("${psql_scratch[@]}" --tuples-only --no-align --command="select (due_until-interval '1 minute')::text from public.airfnb_lock_fees where id='f2670000-0000-4000-8000-000000000404';")"
  statuses="$(run_pair sweeper \
    "set role service_role; select public.airfnb_reconcile_stripe_event('evt-race-sweeper','checkout.session.completed','$event_time','f2670000-0000-4000-8000-000000000204','f2670000-0000-4000-8000-000000000404','f2670000-0000-4000-8000-000000000304','pi-race-sweeper',5000,'EUR','paid',0);" \
    "set role service_role; select public.airfnb_expire_stale_lock_fees();")"
  [[ "$statuses" == 0:0 || "$statuses" == 0:1 || "$statuses" == 1:0 ]] || exit 1
  "${psql_scratch[@]}" --tuples-only --no-align <<'SQL' | grep -Eq '^(paid:confirmed:1:1|expired:cancelled:0:0)$'
select pg_catalog.concat_ws(':',f.status,b.status,
 (select count(*) from public.airfnb_payments where lock_fee_id=f.id),
 (select count(*) from public.airfnb_stripe_events where event_id='evt-race-sweeper'))
from public.airfnb_lock_fees f join public.airfnb_bookings b on b.application_id=f.application_id
where f.id='f2670000-0000-4000-8000-000000000404';
SQL
  printf 'PAYMENT_SWEEPER_SERIALIZATION_VERIFIED\n'

  "${psql_scratch[@]}" --command="$(rpc_sql evt-race-refund-payment 203 403 303 pi-race-refund checkout.session.completed 0 '0 seconds')" >/dev/null
  statuses="$(run_pair refund \
    "$(rpc_sql evt-race-refund-partial 203 403 303 pi-race-refund charge.refunded 2000 '1 second')" \
    "$(rpc_sql evt-race-refund-full 203 403 303 pi-race-refund charge.refunded 5000 '2 seconds')")"
  if [[ "$statuses" != 0:0 ]]; then
    printf 'refund race failed: %s\n' "$statuses" >&2
    sed -n '1,120p' "$temporary_directory/refund-a.log" >&2
    sed -n '1,120p' "$temporary_directory/refund-b.log" >&2
    exit 1
  fi
  [[ "$("${psql_scratch[@]}" --tuples-only --no-align --command="select refunded_amount::text||':'||status::text from public.airfnb_payments where provider_ref='pi-race-refund';")" == 50.00:refunded ]] || exit 1
  printf 'CONCURRENT_REFUND_VERIFIED\n'
}

create_scratch old
apply_predecessors
run_drift_and_rollback_proof
apply_candidate_and_reapply
run_concurrency_matrix
old_final_hash="$("${psql_scratch[@]}" --tuples-only --no-align --command="select pg_catalog.md5(prosrc) from pg_catalog.pg_proc where oid='public.airfnb_reconcile_stripe_event(text,text,timestamp with time zone,uuid,uuid,uuid,text,bigint,text,text,bigint)'::regprocedure;")"

create_scratch legacy
apply_predecessors
downgrade_to_exact_legacy
apply_candidate_and_reapply

source_sha256_after="$(source_fingerprint)"
[[ "$source_sha256_after" == "$source_sha256_before" ]] || { printf 'source changed\n' >&2; exit 1; }
[[ "$(artifact_manifest)" == "$artifact_manifest_before" ]] || { printf 'artifacts changed during driver\n' >&2; exit 1; }
printf 'SOURCE_SHA256_UNCHANGED=%s\n' "$source_sha256_after"
printf 'STRIPE_RPC_BODY_MD5=%s\n' "$old_final_hash"
printf 'MIGRATION_SHA256=%s\n' "$(sha256_file "$migration_file")"

# Cleanup is explicit before the residue query so a success proves nothing was
# merely deferred to EXIT handling.
for database_name in "${scratch_databases[@]}"; do
  dropdb --host="$socket_directory" --port="$postgres_port" --maintenance-db=template1 -- "$database_name"
done
residue="$(PGOPTIONS='-c default_transaction_read_only=on' "${psql_source[@]}" --tuples-only --no-align \
  --command="select count(*) from pg_catalog.pg_database where datname like 'fb_tailor_stripe_%';")"
[[ "$residue" == 0 ]] || { printf 'scratch database residue: %s\n' "$residue" >&2; exit 1; }
printf 'SCRATCH_RESIDUE=0\n'
printf 'stripe canonical reconciliation driver passed\n'
