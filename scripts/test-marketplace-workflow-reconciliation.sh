#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf '%s\n' \
    "usage: $0 --socket SOCKET_DIRECTORY --port PORT --source-db SOURCE_DATABASE" >&2
  exit 64
}

socket_directory=""
postgres_port=""
source_database=""

while (($# > 0)); do
  case "$1" in
    --socket)
      (($# >= 2)) || usage
      socket_directory="$2"
      shift 2
      ;;
    --port)
      (($# >= 2)) || usage
      postgres_port="$2"
      shift 2
      ;;
    --source-db)
      (($# >= 2)) || usage
      source_database="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done

[[ -n "$socket_directory" && -n "$postgres_port" && -n "$source_database" ]] || usage
[[ "$socket_directory" == /* && "$socket_directory" != "/" ]] || {
  printf 'refusing unsafe PostgreSQL socket directory: %s\n' "$socket_directory" >&2
  exit 64
}
[[ "$postgres_port" =~ ^[0-9]+$ ]] \
  && ((postgres_port >= 1 && postgres_port <= 65535)) || {
    printf 'refusing invalid PostgreSQL port: %s\n' "$postgres_port" >&2
    exit 64
  }
[[ "$source_database" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]] || {
  printf 'refusing unsafe source database: %s\n' "$source_database" >&2
  exit 64
}
[[ "$source_database" != template0 && "$source_database" != template1 ]] || {
  printf 'refusing PostgreSQL template as source\n' >&2
  exit 64
}
[[ ! "$source_database" =~ ^fb_tailor_catalog_ ]] || {
  printf 'refusing marketplace scratch database as source\n' >&2
  exit 64
}
[[ -S "$socket_directory/.s.PGSQL.$postgres_port" ]] || {
  printf 'explicit local PostgreSQL socket is unavailable\n' >&2
  exit 66
}

for command_name in psql pg_dump createdb dropdb shasum sed awk grep mktemp sleep; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'required local command is unavailable: %s\n' "$command_name" >&2
    exit 69
  }
done

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
runtime_integrity_file="$repository_root/supabase/migrations/20260820152018_airfnb_runtime_function_integrity_reconciliation.sql"
privacy_file="$repository_root/supabase/migrations/20260820153725_public_event_request_privacy_reconciliation.sql"
messaging_file="$repository_root/supabase/migrations/20260820154054_messaging_reviews_reconciliation.sql"
storage_file="$repository_root/supabase/migrations/20260820154100_storage_abuse_reconciliation.sql"
catalog_file="$repository_root/supabase/migrations/20260820154104_catalog_service_types_reconciliation.sql"
migration_file="$repository_root/supabase/migrations/20260820154358_marketplace_workflow_reconciliation.sql"
runtime_file="$repository_root/tests/marketplace-workflow-reconciliation-runtime.sql"
source_test_file="$repository_root/tests/marketplace-workflow-reconciliation-source.test.mjs"
driver_file="$repository_root/scripts/test-marketplace-workflow-reconciliation.sh"

artifacts=(
  "$runtime_integrity_file" "$privacy_file" "$messaging_file" "$storage_file"
  "$catalog_file" "$migration_file" "$runtime_file" "$source_test_file"
  "$driver_file"
)
for required_file in "${artifacts[@]}"; do
  [[ -f "$required_file" ]] || {
    printf 'marketplace reconciliation artifact is missing: %s\n' "$required_file" >&2
    exit 66
  }
done

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

sha256_stream() {
  shasum -a 256 | awk '{print $1}'
}

artifact_manifest() {
  local artifact
  for artifact in "${artifacts[@]}"; do
    printf '%s  %s\n' "$(sha256_file "$artifact")" "$artifact"
  done
}

psql_source=(
  psql -X --no-psqlrc --host="$socket_directory" --port="$postgres_port"
  --dbname="$source_database" --set=ON_ERROR_STOP=1 --tuples-only --no-align --quiet
)

actual_source_database="$(PGOPTIONS='-c default_transaction_read_only=on' \
  "${psql_source[@]}" --command='select current_database();')"
[[ "$actual_source_database" == "$source_database" ]] || {
  printf 'source database connection mismatch\n' >&2
  exit 65
}

source_fingerprint() {
  PGOPTIONS='-c default_transaction_read_only=on' pg_dump \
    --host="$socket_directory" --port="$postgres_port" --dbname="$source_database" \
    --format=plain --schema=auth --schema=public --schema=storage --no-owner \
    | sed '/^\\restrict /d; /^\\unrestrict /d' \
    | sha256_stream
}

database_count() {
  local database_name="$1"
  [[ "$database_name" =~ ^fb_tailor_catalog_[0-9]+_[0-9]+_old$ ]] || return 1
  PGOPTIONS='-c default_transaction_read_only=on' "${psql_source[@]}" \
    --set=database_name="$database_name" <<'SQL'
select pg_catalog.count(*)
  from pg_catalog.pg_database
 where datname = :'database_name';
SQL
}

source_contract="$(PGOPTIONS='-c default_transaction_read_only=on' "${psql_source[@]}" <<'SQL'
begin transaction read only;
select pg_catalog.concat_ws(
  ':',
  current_setting('transaction_read_only'),
  (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc
    where oid = 'public.airfnb_guard_truck_moderation()'::regprocedure),
  (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc
    where oid = 'public.airfnb_recalc_truck_rating()'::regprocedure),
  (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc
    where oid = 'public.airfnb_can_read_truck_child(text)'::regprocedure),
  pg_catalog.md5(pg_catalog.pg_get_viewdef('public.airfnb_v_truck_card'::regclass, true)),
  (select pg_catalog.md5(pg_catalog.string_agg(
     pg_catalog.format('%s:%s:%s', id, rating_avg, rating_count), ',' order by id
   )) from public.airfnb_trucks),
  (select pg_catalog.count(*) from pg_catalog.pg_database
    where datname like 'fb_tailor_catalog_%')
);
rollback;
SQL
)"
[[ "$source_contract" == "on:9580d50b368d29269983025249704dda:fb14827219d32ed1bfabfcc65fd44a45:3d9d41a7dc6e3f52091dddeba50a1884:d252ca591e49263980a5072107ff8fc0:b7601dc5d1de93f854aaaf10085c33f7:0" ]] || {
  printf 'source database does not match verified immutable fixture: %s\n' "$source_contract" >&2
  exit 65
}

source_fixture_count_before="$(PGOPTIONS='-c default_transaction_read_only=on' \
  "${psql_source[@]}" <<'SQL'
begin transaction read only;
select
  (select pg_catalog.count(*) from auth.users
    where id::text like any (array['f2620000-0000-4000-8000-%','f2630000-0000-4000-8000-%','f2640000-0000-4000-8000-%']))
  + (select pg_catalog.count(*) from public.airfnb_event_requests
    where id::text like any (array['f2620000-0000-4000-8000-%','f2630000-0000-4000-8000-%','f2640000-0000-4000-8000-%']))
  + (select pg_catalog.count(*) from public.airfnb_applications
    where id::text like any (array['f2620000-0000-4000-8000-%','f2630000-0000-4000-8000-%','f2640000-0000-4000-8000-%']));
rollback;
SQL
)"
[[ "$source_fixture_count_before" == 0 ]] || {
  printf 'source zero-fixture audit failed before cloning: %s\n' "$source_fixture_count_before" >&2
  exit 65
}

source_sha256_before="$(source_fingerprint)"
artifact_manifest_before="$(artifact_manifest)"
runtime_integrity_sha256="$(sha256_file "$runtime_integrity_file")"
privacy_sha256="$(sha256_file "$privacy_file")"
messaging_sha256="$(sha256_file "$messaging_file")"
storage_sha256="$(sha256_file "$storage_file")"
catalog_sha256="$(sha256_file "$catalog_file")"

[[ "$runtime_integrity_sha256" == 'f1400bd3e4ac3d1d4e2c67b6cd33a0b7a551a26bfc018633c31f9c494096b24f' \
   && "$privacy_sha256" == 'bc859122de962efee0a5d11d5e56be9ba7f42bc54ce097ead672241686f89fc2' \
   && "$messaging_sha256" == '26695c1b5567a182777f15fa81249d234857fd3e608abcc6056dbdb39a6c55b8' \
   && "$storage_sha256" == '19b02bd08d14be47b5f2ef086700bc8248be63f5ecac9b1501e6024b436d164b' \
   && "$catalog_sha256" == '90dbaf281ea0c9209373fe16964e1aaaa34152f0272ef067fdee80f831fdc60c' ]] || {
  printf 'official predecessor chain hash mismatch\n' >&2
  exit 65
}

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/fb-tailor-marketplace.XXXXXX")"
failure_log="$temporary_directory/intentional-failure.log"
drift_log="$temporary_directory/drift.log"
race_a_log="$temporary_directory/race-a.log"
race_b_log="$temporary_directory/race-b.log"
independent_a_log="$temporary_directory/independent-a.log"
independent_b_log="$temporary_directory/independent-b.log"
blocker_log="$temporary_directory/blocker.log"
reject_log="$temporary_directory/reject.log"
shortlist_log="$temporary_directory/shortlist.log"
log_files=(
  "$failure_log" "$drift_log" "$race_a_log" "$race_b_log"
  "$independent_a_log" "$independent_b_log" "$blocker_log"
  "$reject_log" "$shortlist_log"
)
scratch_database=""
scratch_created=0

is_scratch_database() {
  [[ "$1" =~ ^fb_tailor_catalog_[0-9]+_[0-9]+_old$ ]]
}

cleanup_scratch() {
  if ((scratch_created == 1)); then
    if ! is_scratch_database "$scratch_database" \
      || [[ "$scratch_database" == "$source_database" ]]; then
      printf 'refusing unsafe scratch cleanup target: %s\n' "$scratch_database" >&2
      return 1
    fi
    dropdb --host="$socket_directory" --port="$postgres_port" \
      --maintenance-db=template1 -- "$scratch_database"
    scratch_created=0
  fi
}

cleanup() {
  local exit_status=$?
  trap - EXIT INT TERM
  cleanup_scratch || exit_status=1
  rm -f -- "${log_files[@]}"
  rmdir "$temporary_directory" 2>/dev/null || exit_status=1
  exit "$exit_status"
}
trap cleanup EXIT INT TERM

validate_scratch() {
  is_scratch_database "$scratch_database" || return 1
  [[ "$scratch_database" != "$source_database" ]] || return 1
  [[ "$(database_count "$scratch_database")" == 1 ]] || return 1
  [[ "$("${psql_scratch[@]}" --tuples-only --no-align \
    --command='select current_database();')" == "$scratch_database" ]] || return 1
  [[ "$("${psql_scratch[@]}" --tuples-only --no-align \
    --command="select pg_catalog.current_database() ~ '^fb_tailor_catalog_[0-9]+_[0-9]+_old$';")" == t ]]
}

target_state_sha256() {
  "${psql_scratch[@]}" --tuples-only --no-align --field-separator='|' <<'SQL' \
    | sha256_stream
select 'relation', namespace.nspname, relation.relname,
       relation.relowner::text, relation.relrowsecurity::text,
       relation.relforcerowsecurity::text, coalesce(relation.relacl::text, '')
  from pg_catalog.pg_class as relation
  join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
 where namespace.nspname = 'public'
   and relation.relname in (
     'airfnb_applications','airfnb_bookings','airfnb_booking_trucks','airfnb_lock_fees'
   )
union all
select 'policy', 'public', relation.relname, policy.polname,
       policy.polcmd::text, policy.polroles::text,
       pg_catalog.md5(pg_catalog.concat_ws('|', policy.polpermissive::text,
         coalesce(pg_catalog.pg_get_expr(policy.polqual, policy.polrelid), ''),
         coalesce(pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid), '')))
  from pg_catalog.pg_policy as policy
  join pg_catalog.pg_class as relation on relation.oid = policy.polrelid
 where relation.oid = 'public.airfnb_applications'::pg_catalog.regclass
union all
select 'function', namespace.nspname, procedure.proname,
       pg_catalog.pg_get_function_identity_arguments(procedure.oid),
       procedure.proowner::text,
       pg_catalog.concat_ws(':', procedure.prosecdef::text, procedure.provolatile::text,
         coalesce(procedure.proconfig::text, ''), coalesce(procedure.proacl::text, '')),
       pg_catalog.md5(procedure.prosrc)
  from pg_catalog.pg_proc as procedure
  join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
 where namespace.nspname = 'public'
   and procedure.proname in (
     'airfnb_can_manage_truck','airfnb_can_submit_application',
     'airfnb_own_application_truck',
     'airfnb_accept_application',
     'airfnb_shortlist_application','airfnb_reject_application',
     'airfnb_supplier_lock_fee'
   )
union all
select 'index', schemaname, tablename, indexname, indexdef, '', ''
  from pg_catalog.pg_indexes
 where schemaname = 'public'
   and indexname = 'airfnb_bookings_application_unique'
order by 1,2,3,4,5,6,7;
SQL
}

run_runtime_matrix() {
  "${psql_scratch[@]}" \
    --set=marketplace_runtime_database="$scratch_database" \
    --file="$runtime_file" >/dev/null
}

run_state_matrix() {
  "${psql_scratch[@]}" >/dev/null <<'SQL'
begin;
set local statement_timeout = '60s';

do $fixture_guard$
begin
  if pg_catalog.current_database() !~ '^fb_tailor_catalog_[0-9]+_[0-9]+_old$'
     or exists (
       select 1 from auth.users where id::text like 'f2640000-0000-4000-8000-%'
     ) then
    raise exception 'marketplace state matrix refused unsafe fixture target';
  end if;
end
$fixture_guard$;

insert into auth.users(id, email, raw_user_meta_data) values
  ('f2640000-0000-4000-8000-000000000001', 'matrix-organizer@example.invalid', '{}'),
  ('f2640000-0000-4000-8000-000000000002', 'matrix-supplier@example.invalid', '{}');
update public.airfnb_profiles
   set role = case id
     when 'f2640000-0000-4000-8000-000000000001' then 'organizer'::public.airfnb_user_role
     else 'owner'::public.airfnb_user_role
   end
 where id in (
   'f2640000-0000-4000-8000-000000000001',
   'f2640000-0000-4000-8000-000000000002'
 );
insert into public.airfnb_trucks(
  id, owner_id, slug, name, status, service_type, base_city
) values (
  'f2640000-0000-4000-8000-000000000010',
  'f2640000-0000-4000-8000-000000000002',
  'marketplace-state-matrix', 'Marketplace State Matrix',
  'active', 'food_truck', 'Lisboa'
);

insert into public.airfnb_event_requests(
  id, organizer_id, title, start_at, end_at, expected_pax, slots_needed,
  applications_deadline, status, visibility, application_response_window_hours, city
)
select fixture.id, 'f2640000-0000-4000-8000-000000000001', fixture.title,
       '2036-08-20 12:00:00+00', '2036-08-20 18:00:00+00', 100, 1,
       '2036-08-10 00:00:00+00', fixture.status::public.airfnb_request_status,
       'public', 48, 'Lisboa'
  from (values
    ('f2640000-0000-4000-8000-000000000100'::uuid, 'Shortlist matrix', 'open'),
    ('f2640000-0000-4000-8000-000000000110'::uuid, 'Reject matrix', 'open'),
    ('f2640000-0000-4000-8000-000000000120'::uuid, 'Invalid matrix', 'open'),
    ('f2640000-0000-4000-8000-000000000130'::uuid, 'Accept open submitted', 'open'),
    ('f2640000-0000-4000-8000-000000000131'::uuid, 'Accept open shortlisted', 'open'),
    ('f2640000-0000-4000-8000-000000000132'::uuid, 'Accept reviewing submitted', 'reviewing'),
    ('f2640000-0000-4000-8000-000000000133'::uuid, 'Accept reviewing shortlisted', 'reviewing')
  ) as fixture(id, title, status);

insert into public.airfnb_applications(id, request_id, truck_id, proposed_price, status)
select fixture.id, fixture.request_id,
       'f2640000-0000-4000-8000-000000000010', 600,
       fixture.status::public.airfnb_application_status
  from (values
    ('f2640000-0000-4000-8000-000000000200'::uuid, 'f2640000-0000-4000-8000-000000000100'::uuid, 'submitted'),
    ('f2640000-0000-4000-8000-000000000210'::uuid, 'f2640000-0000-4000-8000-000000000110'::uuid, 'submitted'),
    ('f2640000-0000-4000-8000-000000000220'::uuid, 'f2640000-0000-4000-8000-000000000120'::uuid, 'submitted'),
    ('f2640000-0000-4000-8000-000000000230'::uuid, 'f2640000-0000-4000-8000-000000000130'::uuid, 'submitted'),
    ('f2640000-0000-4000-8000-000000000231'::uuid, 'f2640000-0000-4000-8000-000000000131'::uuid, 'shortlisted'),
    ('f2640000-0000-4000-8000-000000000232'::uuid, 'f2640000-0000-4000-8000-000000000132'::uuid, 'submitted'),
    ('f2640000-0000-4000-8000-000000000233'::uuid, 'f2640000-0000-4000-8000-000000000133'::uuid, 'shortlisted')
  ) as fixture(id, request_id, status);

insert into public.airfnb_platform_settings(key, "group", description, value, secret)
values
  ('lock_fee.platform_fee', 'lock_fee', 'state matrix', '25', false),
  ('lock_fee.organizer_share', 'lock_fee', 'state matrix', '25', false)
on conflict (key) do update set value = excluded.value;

select pg_catalog.set_config(
  'request.jwt.claim.sub', 'f2640000-0000-4000-8000-000000000001', true
);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);

do $valid_shortlist_reject$
declare
  v_request_status public.airfnb_request_status;
  v_application_status public.airfnb_application_status;
begin
  foreach v_request_status in array array['open','reviewing']::public.airfnb_request_status[] loop
    update public.airfnb_event_requests set status = v_request_status
     where id = 'f2640000-0000-4000-8000-000000000100';
    update public.airfnb_applications
       set status = 'submitted', shortlisted_at = null, decided_at = null
     where id = 'f2640000-0000-4000-8000-000000000200';
    perform public.airfnb_shortlist_application('f2640000-0000-4000-8000-000000000200');
    if (select status from public.airfnb_applications
         where id = 'f2640000-0000-4000-8000-000000000200') <> 'shortlisted' then
      raise exception 'valid shortlist transition failed: %', v_request_status;
    end if;
  end loop;

  foreach v_request_status in array array['open','reviewing','awarded']::public.airfnb_request_status[] loop
    foreach v_application_status in array array['submitted','shortlisted']::public.airfnb_application_status[] loop
      update public.airfnb_event_requests set status = v_request_status
       where id = 'f2640000-0000-4000-8000-000000000110';
      update public.airfnb_applications
         set status = v_application_status, shortlisted_at = null, decided_at = null
       where id = 'f2640000-0000-4000-8000-000000000210';
      perform public.airfnb_reject_application(
        'f2640000-0000-4000-8000-000000000210', 'state matrix'
      );
      if (select status from public.airfnb_applications
           where id = 'f2640000-0000-4000-8000-000000000210') <> 'rejected' then
        raise exception 'valid reject transition failed: %/%',
          v_request_status, v_application_status;
      end if;
    end loop;
  end loop;
end
$valid_shortlist_reject$;

do $valid_accept$
declare
  v_application uuid;
begin
  foreach v_application in array array[
    'f2640000-0000-4000-8000-000000000230'::uuid,
    'f2640000-0000-4000-8000-000000000231'::uuid,
    'f2640000-0000-4000-8000-000000000232'::uuid,
    'f2640000-0000-4000-8000-000000000233'::uuid
  ] loop
    perform public.airfnb_accept_application(v_application);
  end loop;
  if (select pg_catalog.count(*) from public.airfnb_bookings
       where application_id = any (array[
         'f2640000-0000-4000-8000-000000000230'::uuid,
         'f2640000-0000-4000-8000-000000000231'::uuid,
         'f2640000-0000-4000-8000-000000000232'::uuid,
         'f2640000-0000-4000-8000-000000000233'::uuid
       ])) <> 4 then
    raise exception 'valid accept transition matrix failed';
  end if;
end
$valid_accept$;

do $invalid_application_states$
declare
  v_status public.airfnb_application_status;
begin
  update public.airfnb_event_requests set status = 'open', slots_needed = 1,
         application_response_window_hours = 48
   where id = 'f2640000-0000-4000-8000-000000000120';

  foreach v_status in array array['shortlisted','accepted','rejected','withdrawn','expired']::public.airfnb_application_status[] loop
    update public.airfnb_applications set status = v_status
     where id = 'f2640000-0000-4000-8000-000000000220';
    begin
      perform public.airfnb_shortlist_application('f2640000-0000-4000-8000-000000000220');
      raise exception 'shortlist terminal state unexpectedly succeeded: %', v_status;
    exception when sqlstate '55000' then
      if sqlerrm <> 'application is not eligible for shortlist' then raise; end if;
    end;
  end loop;

  foreach v_status in array array['accepted','rejected','withdrawn','expired']::public.airfnb_application_status[] loop
    update public.airfnb_applications set status = v_status
     where id = 'f2640000-0000-4000-8000-000000000220';
    begin
      perform public.airfnb_reject_application('f2640000-0000-4000-8000-000000000220');
      raise exception 'reject terminal state unexpectedly succeeded: %', v_status;
    exception when sqlstate '55000' then
      if sqlerrm <> 'application is not eligible for rejection' then raise; end if;
    end;
  end loop;

  foreach v_status in array array['accepted','rejected','withdrawn','expired']::public.airfnb_application_status[] loop
    update public.airfnb_applications set status = v_status
     where id = 'f2640000-0000-4000-8000-000000000220';
    begin
      perform public.airfnb_accept_application('f2640000-0000-4000-8000-000000000220');
      raise exception 'accept terminal state unexpectedly succeeded: %', v_status;
    exception when sqlstate '55000' then
      if sqlerrm <> 'application is not eligible for acceptance' then raise; end if;
    end;
  end loop;

  update public.airfnb_applications set status = null
   where id = 'f2640000-0000-4000-8000-000000000220';
  begin
    perform public.airfnb_shortlist_application('f2640000-0000-4000-8000-000000000220');
    raise exception 'null shortlist state unexpectedly succeeded';
  exception when sqlstate '55000' then
    if sqlerrm <> 'application is not eligible for shortlist' then raise; end if;
  end;
  begin
    perform public.airfnb_reject_application('f2640000-0000-4000-8000-000000000220');
    raise exception 'null reject state unexpectedly succeeded';
  exception when sqlstate '55000' then
    if sqlerrm <> 'application is not eligible for rejection' then raise; end if;
  end;
  begin
    perform public.airfnb_accept_application('f2640000-0000-4000-8000-000000000220');
    raise exception 'null accept state unexpectedly succeeded';
  exception when sqlstate '55000' then
    if sqlerrm <> 'application is not eligible for acceptance' then raise; end if;
  end;
end
$invalid_application_states$;

do $invalid_request_states$
declare
  v_status public.airfnb_request_status;
begin
  update public.airfnb_applications set status = 'submitted'
   where id = 'f2640000-0000-4000-8000-000000000220';
  foreach v_status in array array['draft','awarded','closed','expired','cancelled']::public.airfnb_request_status[] loop
    update public.airfnb_event_requests set status = v_status
     where id = 'f2640000-0000-4000-8000-000000000120';
    begin
      perform public.airfnb_shortlist_application('f2640000-0000-4000-8000-000000000220');
      raise exception 'shortlist terminal request unexpectedly succeeded: %', v_status;
    exception when sqlstate '55000' then
      if sqlerrm <> 'request is not reviewing applications' then raise; end if;
    end;
    begin
      perform public.airfnb_accept_application('f2640000-0000-4000-8000-000000000220');
      raise exception 'accept terminal request unexpectedly succeeded: %', v_status;
    exception when sqlstate '55000' then
      if sqlerrm <> 'request is not accepting applications' then raise; end if;
    end;
  end loop;

  foreach v_status in array array['draft','closed','expired','cancelled']::public.airfnb_request_status[] loop
    update public.airfnb_event_requests set status = v_status
     where id = 'f2640000-0000-4000-8000-000000000120';
    begin
      perform public.airfnb_reject_application('f2640000-0000-4000-8000-000000000220');
      raise exception 'reject terminal request unexpectedly succeeded: %', v_status;
    exception when sqlstate '55000' then
      if sqlerrm <> 'request cannot reject applications' then raise; end if;
    end;
  end loop;

  update public.airfnb_event_requests set status = null
   where id = 'f2640000-0000-4000-8000-000000000120';
  begin
    perform public.airfnb_shortlist_application('f2640000-0000-4000-8000-000000000220');
    raise exception 'null shortlist request unexpectedly succeeded';
  exception when sqlstate '55000' then
    if sqlerrm <> 'request is not reviewing applications' then raise; end if;
  end;
  begin
    perform public.airfnb_reject_application('f2640000-0000-4000-8000-000000000220');
    raise exception 'null reject request unexpectedly succeeded';
  exception when sqlstate '55000' then
    if sqlerrm <> 'request cannot reject applications' then raise; end if;
  end;
  begin
    perform public.airfnb_accept_application('f2640000-0000-4000-8000-000000000220');
    raise exception 'null accept request unexpectedly succeeded';
  exception when sqlstate '55000' then
    if sqlerrm <> 'request is not accepting applications' then raise; end if;
  end;
end
$invalid_request_states$;

do $invalid_accept_settings$
begin
  update public.airfnb_applications set status = 'submitted'
   where id = 'f2640000-0000-4000-8000-000000000220';
  update public.airfnb_event_requests set status = 'open', slots_needed = null,
         application_response_window_hours = 48
   where id = 'f2640000-0000-4000-8000-000000000120';
  begin
    perform public.airfnb_accept_application('f2640000-0000-4000-8000-000000000220');
    raise exception 'null slots unexpectedly accepted';
  exception when sqlstate '22023' then
    if sqlerrm <> 'request acceptance settings are invalid' then raise; end if;
  end;
  begin
    update public.airfnb_event_requests set slots_needed = 0
     where id = 'f2640000-0000-4000-8000-000000000120';
    raise exception 'zero slots constraint unexpectedly accepted';
  exception when sqlstate '23514' then null;
  end;
  begin
    update public.airfnb_event_requests set slots_needed = 11
     where id = 'f2640000-0000-4000-8000-000000000120';
    raise exception 'eleven slots constraint unexpectedly accepted';
  exception when sqlstate '23514' then null;
  end;
  update public.airfnb_event_requests set slots_needed = 1,
         application_response_window_hours = null
   where id = 'f2640000-0000-4000-8000-000000000120';
  begin
    perform public.airfnb_accept_application('f2640000-0000-4000-8000-000000000220');
    raise exception 'null response window unexpectedly accepted';
  exception when sqlstate '22023' then null;
  end;
  update public.airfnb_event_requests set application_response_window_hours = 0
   where id = 'f2640000-0000-4000-8000-000000000120';
  begin
    perform public.airfnb_accept_application('f2640000-0000-4000-8000-000000000220');
    raise exception 'zero response window unexpectedly accepted';
  exception when sqlstate '22023' then null;
  end;
end
$invalid_accept_settings$;

rollback;
SQL
}

setup_concurrency_fixtures() {
  "${psql_scratch[@]}" >/dev/null <<'SQL'
begin;
do $fixture_guard$
begin
  if pg_catalog.current_database() !~ '^fb_tailor_catalog_[0-9]+_[0-9]+_old$'
     or exists (
       select 1 from auth.users where id::text like 'f2630000-0000-4000-8000-%'
     ) then
    raise exception 'marketplace concurrency refused unsafe fixture target';
  end if;
end
$fixture_guard$;
insert into auth.users(id, email, raw_user_meta_data) values
  ('f2630000-0000-4000-8000-000000000001', 'race-organizer@example.invalid', '{}'),
  ('f2630000-0000-4000-8000-000000000002', 'race-supplier-a@example.invalid', '{}'),
  ('f2630000-0000-4000-8000-000000000003', 'race-supplier-b@example.invalid', '{}');
update public.airfnb_profiles
   set role = case id
     when 'f2630000-0000-4000-8000-000000000001' then 'organizer'::public.airfnb_user_role
     else 'owner'::public.airfnb_user_role
   end
 where id in (
   'f2630000-0000-4000-8000-000000000001',
   'f2630000-0000-4000-8000-000000000002',
   'f2630000-0000-4000-8000-000000000003'
 );
insert into public.airfnb_trucks(id, owner_id, slug, name, status, service_type, base_city)
values
  ('f2630000-0000-4000-8000-000000000010', 'f2630000-0000-4000-8000-000000000002', 'race-supplier-a', 'Race Supplier A', 'active', 'food_truck', 'Lisboa'),
  ('f2630000-0000-4000-8000-000000000011', 'f2630000-0000-4000-8000-000000000003', 'race-supplier-b', 'Race Supplier B', 'active', 'catering', 'Porto');
insert into public.airfnb_event_requests(
  id, organizer_id, title, start_at, end_at, expected_pax, slots_needed,
  applications_deadline, status, visibility, application_response_window_hours, city
)
select fixture.id, 'f2630000-0000-4000-8000-000000000001', fixture.title,
       '2036-09-20 12:00:00+00', '2036-09-20 18:00:00+00', 100, 1,
       '2036-09-10 00:00:00+00', fixture.status::public.airfnb_request_status,
       'public', 48, 'Lisboa'
  from (values
    ('f2630000-0000-4000-8000-000000000100'::uuid, 'Same application race', 'open'),
    ('f2630000-0000-4000-8000-000000000110'::uuid, 'Final slot race', 'open'),
    ('f2630000-0000-4000-8000-000000000120'::uuid, 'Independent A', 'open'),
    ('f2630000-0000-4000-8000-000000000121'::uuid, 'Independent B', 'open'),
    ('f2630000-0000-4000-8000-000000000130'::uuid, 'Shortlist reject race', 'reviewing')
  ) as fixture(id, title, status);
insert into public.airfnb_applications(id, request_id, truck_id, proposed_price, status)
values
  ('f2630000-0000-4000-8000-000000000200', 'f2630000-0000-4000-8000-000000000100', 'f2630000-0000-4000-8000-000000000010', 700, 'submitted'),
  ('f2630000-0000-4000-8000-000000000210', 'f2630000-0000-4000-8000-000000000110', 'f2630000-0000-4000-8000-000000000010', 710, 'submitted'),
  ('f2630000-0000-4000-8000-000000000211', 'f2630000-0000-4000-8000-000000000110', 'f2630000-0000-4000-8000-000000000011', 720, 'submitted'),
  ('f2630000-0000-4000-8000-000000000220', 'f2630000-0000-4000-8000-000000000120', 'f2630000-0000-4000-8000-000000000010', 730, 'submitted'),
  ('f2630000-0000-4000-8000-000000000221', 'f2630000-0000-4000-8000-000000000121', 'f2630000-0000-4000-8000-000000000010', 740, 'submitted'),
  ('f2630000-0000-4000-8000-000000000230', 'f2630000-0000-4000-8000-000000000130', 'f2630000-0000-4000-8000-000000000010', 750, 'submitted');
insert into public.airfnb_platform_settings(key, "group", description, value, secret)
values
  ('lock_fee.platform_fee', 'lock_fee', 'concurrency fixture', '25', false),
  ('lock_fee.organizer_share', 'lock_fee', 'concurrency fixture', '25', false)
on conflict (key) do update set value = excluded.value;
commit;
SQL
}

run_rpc() {
  local application_name="$1"
  local rpc_name="$2"
  local application_id="$3"
  local rpc_sql
  [[ "$application_name" =~ ^[a-z0-9-]+$ ]] || return 64
  [[ "$application_id" =~ ^[0-9a-f-]{36}$ ]] || return 64
  case "$rpc_name" in
    accept) rpc_sql="select public.airfnb_accept_application(:'application_id'::uuid);" ;;
    shortlist) rpc_sql="select public.airfnb_shortlist_application(:'application_id'::uuid);" ;;
    reject) rpc_sql="select public.airfnb_reject_application(:'application_id'::uuid, 'race');" ;;
    *) return 64 ;;
  esac
  PGAPPNAME="$application_name" "${psql_scratch[@]}" \
    --set=application_id="$application_id" <<SQL
select pg_catalog.set_config(
  'request.jwt.claim.sub', 'f2630000-0000-4000-8000-000000000001', false
);
select pg_catalog.set_config('request.jwt.claim.role', 'authenticated', false);
set role authenticated;
$rpc_sql
SQL
}

assert_one_success_one_failure() {
  local label="$1"
  local first_status="$2"
  local first_log="$3"
  local second_status="$4"
  local second_log="$5"
  local expected_message="$6"
  local successes=0
  ((first_status == 0)) && successes=$((successes + 1))
  ((second_status == 0)) && successes=$((successes + 1))
  if ((successes != 1)); then
    printf '%s did not produce exactly one success: %s/%s\n' \
      "$label" "$first_status" "$second_status" >&2
    sed -n '1,100p' "$first_log" >&2
    sed -n '1,100p' "$second_log" >&2
    return 1
  fi
  if ((first_status != 0)) && ! grep -Fq "$expected_message" "$first_log"; then
    printf '%s first loser had unexpected error\n' "$label" >&2
    sed -n '1,100p' "$first_log" >&2
    return 1
  fi
  if ((second_status != 0)) && ! grep -Fq "$expected_message" "$second_log"; then
    printf '%s second loser had unexpected error\n' "$label" >&2
    sed -n '1,100p' "$second_log" >&2
    return 1
  fi
}

wait_for_lock_waiter() {
  local application_name="$1"
  local attempts=0
  while ((attempts < 100)); do
    if [[ "$("${psql_scratch[@]}" --tuples-only --no-align --command="
        select pg_catalog.count(*) from pg_catalog.pg_stat_activity
         where datname = pg_catalog.current_database()
           and application_name = '$application_name'
           and wait_event_type = 'Lock';")" == 1 ]]; then
      return 0
    fi
    sleep 0.05
    attempts=$((attempts + 1))
  done
  printf 'timed out waiting for lock waiter: %s\n' "$application_name" >&2
  return 1
}

wait_for_sleeping_blocker() {
  local application_name="$1"
  local attempts=0
  while ((attempts < 100)); do
    if [[ "$("${psql_scratch[@]}" --tuples-only --no-align --command="
        select pg_catalog.count(*) from pg_catalog.pg_stat_activity
         where datname = pg_catalog.current_database()
           and application_name = '$application_name'
           and wait_event = 'PgSleep';")" == 1 ]]; then
      return 0
    fi
    sleep 0.05
    attempts=$((attempts + 1))
  done
  printf 'timed out waiting for sleeping blocker: %s\n' "$application_name" >&2
  return 1
}

assert_sql_denied() {
  local label="$1"
  local expected_message="$2"
  local sql="$3"
  if "${psql_scratch[@]}" --command="$sql" >"$drift_log" 2>&1; then
    printf 'expected denial unexpectedly succeeded: %s\n' "$label" >&2
    return 1
  fi
  if ! grep -Fqi "$expected_message" "$drift_log"; then
    printf 'denial failed for an unexpected reason: %s\n' "$label" >&2
    sed -n '1,100p' "$drift_log" >&2
    return 1
  fi
}

scratch_database="fb_tailor_catalog_${$}_${RANDOM}_old"
is_scratch_database "$scratch_database" || {
  printf 'generated unsafe scratch database name\n' >&2
  exit 70
}
[[ "$scratch_database" != "$source_database" ]] || exit 70
[[ "$(database_count "$scratch_database")" == 0 ]] || {
  printf 'refusing pre-existing scratch database: %s\n' "$scratch_database" >&2
  exit 65
}

createdb --host="$socket_directory" --port="$postgres_port" \
  --maintenance-db=template1 --template="$source_database" -- "$scratch_database"
scratch_created=1
printf 'SCRATCH_CLONE_CREATED database=%s\n' "$scratch_database"

psql_scratch=(
  psql -X --no-psqlrc --host="$socket_directory" --port="$postgres_port"
  --dbname="$scratch_database" --set=ON_ERROR_STOP=1 --quiet
)
validate_scratch || {
  printf 'scratch clone identity validation failed\n' >&2
  exit 65
}

for predecessor_file in \
  "$runtime_integrity_file" "$privacy_file" "$messaging_file" \
  "$storage_file" "$catalog_file"
do
  "${psql_scratch[@]}" --file="$predecessor_file" >/dev/null
done

predecessor_contract="$("${psql_scratch[@]}" --tuples-only --no-align <<'SQL'
select pg_catalog.concat_ws(
  ':',
  (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc
    where oid = 'public.airfnb_accept_application(uuid)'::pg_catalog.regprocedure),
  (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc
    where oid = 'public.airfnb_can_manage_truck(text)'::pg_catalog.regprocedure),
  (select pg_catalog.array_agg(polname order by polname)::text
    from pg_catalog.pg_policy
    where polrelid = 'public.airfnb_applications'::pg_catalog.regclass),
  (pg_catalog.to_regprocedure('public.airfnb_supplier_lock_fee(uuid)') is null)::integer,
  (select pg_catalog.count(*) from pg_catalog.pg_attribute
    where attrelid = 'public.airfnb_applications'::pg_catalog.regclass
      and attnum > 0 and not attisdropped),
  (select pg_catalog.count(*) from pg_catalog.pg_attribute
    where attrelid = 'public.airfnb_bookings'::pg_catalog.regclass
      and attnum > 0 and not attisdropped)
);
SQL
)"
[[ "$predecessor_contract" == 'b7c875f8b312e246e2f4621f5748b0a1:982caee25d35d0ac9dfe1d3a343ab0a5:{airfnb_app_insert,airfnb_app_read}:1:17:15' ]] || {
  printf 'exact predecessor runtime contract mismatch: %s\n' "$predecessor_contract" >&2
  exit 65
}
printf 'EXACT_PREDECESSOR_CHAIN_VERIFIED contract=%s\n' "$predecessor_contract"

predecessor_state="$(target_state_sha256)"

"${psql_scratch[@]}" --command="
  create policy marketplace_policy_drift_probe
    on public.airfnb_applications for select to authenticated using (false);" >/dev/null
policy_drift_state="$(target_state_sha256)"
if "${psql_scratch[@]}" --file="$migration_file" >"$drift_log" 2>&1; then
  printf 'policy-catalog drift unexpectedly passed\n' >&2
  exit 1
fi
grep -Fq 'application policy catalog drifted' "$drift_log" || {
  sed -n '1,120p' "$drift_log" >&2
  exit 1
}
[[ "$policy_drift_state" == "$(target_state_sha256)" ]] || {
  printf 'refused policy drift changed target state\n' >&2
  exit 1
}
"${psql_scratch[@]}" \
  --command='drop policy marketplace_policy_drift_probe on public.airfnb_applications;' \
  >/dev/null
[[ "$predecessor_state" == "$(target_state_sha256)" ]] || exit 1
printf 'POLICY_CATALOG_DRIFT_REJECTED\n'

"${psql_scratch[@]}" \
  --command='revoke execute on function public.airfnb_can_manage_truck(text) from authenticated;' \
  >/dev/null
helper_drift_state="$(target_state_sha256)"
if "${psql_scratch[@]}" --file="$migration_file" >"$drift_log" 2>&1; then
  printf 'helper ACL drift unexpectedly passed\n' >&2
  exit 1
fi
grep -Fq 'privacy, fee or catalog helper drifted' "$drift_log" || {
  sed -n '1,120p' "$drift_log" >&2
  exit 1
}
[[ "$helper_drift_state" == "$(target_state_sha256)" ]] || {
  printf 'refused helper drift changed target state\n' >&2
  exit 1
}
"${psql_scratch[@]}" \
  --command='grant execute on function public.airfnb_can_manage_truck(text) to authenticated;' \
  >/dev/null
[[ "$predecessor_state" == "$(target_state_sha256)" ]] || exit 1
printf 'HELPER_FUNCTION_ACL_DRIFT_REJECTED\n'

"${psql_scratch[@]}" >/dev/null <<'SQL'
create schema marketplace_reconciliation_sabotage;
create function marketplace_reconciliation_sabotage.fail_after_marketplace_writes()
returns event_trigger
language plpgsql
set search_path = pg_catalog
as $sabotage$
declare
  v_command record;
begin
  for v_command in select * from pg_catalog.pg_event_trigger_ddl_commands()
  loop
    if v_command.command_tag = 'CREATE FUNCTION'
       and v_command.object_identity like 'public.airfnb_accept_application(%' then
      raise exception 'intentional marketplace reconciliation rollback proof';
    end if;
  end loop;
end
$sabotage$;
create event trigger marketplace_reconciliation_sabotage
  on ddl_command_end
  execute function marketplace_reconciliation_sabotage.fail_after_marketplace_writes();
SQL

state_before_failure="$(target_state_sha256)"
if "${psql_scratch[@]}" --file="$migration_file" >"$failure_log" 2>&1; then
  printf 'expected fail-closed migration failure did not occur\n' >&2
  exit 1
fi
grep -Fq 'intentional marketplace reconciliation rollback proof' "$failure_log" || {
  sed -n '1,140p' "$failure_log" >&2
  exit 1
}
[[ "$state_before_failure" == "$(target_state_sha256)" ]] || {
  printf 'intentional failure did not roll target state back\n' >&2
  exit 1
}
printf 'INTENTIONAL_FAILURE_ROLLBACK_VERIFIED state=%s\n' "$state_before_failure"
"${psql_scratch[@]}" \
  --command='drop event trigger marketplace_reconciliation_sabotage' \
  --command='drop schema marketplace_reconciliation_sabotage cascade' >/dev/null

"${psql_scratch[@]}" --file="$migration_file" >/dev/null
state_after_apply="$(target_state_sha256)"
[[ "$state_after_apply" != "$predecessor_state" ]] || {
  printf 'good apply did not change predecessor target state\n' >&2
  exit 1
}
printf 'GOOD_APPLY_VERIFIED state=%s\n' "$state_after_apply"

run_runtime_matrix
[[ "$state_after_apply" == "$(target_state_sha256)" ]] || {
  printf 'actor/settings/runtime matrix changed reconciled state\n' >&2
  exit 1
}
printf 'ACTOR_SETTINGS_RETRY_ATOMICITY_MATRIX_VERIFIED\n'

run_state_matrix
[[ "$state_after_apply" == "$(target_state_sha256)" ]] || {
  printf 'state-transition matrix changed reconciled state\n' >&2
  exit 1
}
printf 'VALID_NULL_TERMINAL_STATE_MATRIX_VERIFIED\n'

setup_concurrency_fixtures

assert_sql_denied forged_application_id 'permission denied' "
  begin;
  select pg_catalog.set_config('request.jwt.claim.sub','f2630000-0000-4000-8000-000000000002',true);
  select pg_catalog.set_config('request.jwt.claim.role','authenticated',true);
  set local role authenticated;
  insert into public.airfnb_applications(id,request_id,truck_id,proposed_price)
  values ('f2630000-0000-4000-8000-000000000299','f2630000-0000-4000-8000-000000000120','f2630000-0000-4000-8000-000000000010',1);
  rollback;"
assert_sql_denied forged_application_state 'permission denied' "
  begin;
  select pg_catalog.set_config('request.jwt.claim.sub','f2630000-0000-4000-8000-000000000002',true);
  select pg_catalog.set_config('request.jwt.claim.role','authenticated',true);
  set local role authenticated;
  insert into public.airfnb_applications(request_id,truck_id,proposed_price,status)
  values ('f2630000-0000-4000-8000-000000000120','f2630000-0000-4000-8000-000000000010',1,'accepted');
  rollback;"
printf 'DIRECT_UNTRUSTED_KEY_STATE_WRITES_DENIED\n'

run_rpc marketplace-same-a accept f2630000-0000-4000-8000-000000000200 \
  >"$race_a_log" 2>&1 &
same_a_pid=$!
run_rpc marketplace-same-b accept f2630000-0000-4000-8000-000000000200 \
  >"$race_b_log" 2>&1 &
same_b_pid=$!
set +e
wait "$same_a_pid"; same_a_status=$?
wait "$same_b_pid"; same_b_status=$?
set -e
assert_one_success_one_failure same_application "$same_a_status" "$race_a_log" \
  "$same_b_status" "$race_b_log" 'application is not eligible for acceptance'
same_application_state="$("${psql_scratch[@]}" --tuples-only --no-align <<'SQL'
select pg_catalog.concat_ws(':',
  (select status from public.airfnb_applications where id = 'f2630000-0000-4000-8000-000000000200'),
  (select count(*) from public.airfnb_bookings where application_id = 'f2630000-0000-4000-8000-000000000200'),
  (select count(*) from public.airfnb_lock_fees where application_id = 'f2630000-0000-4000-8000-000000000200'),
  (select count(*) from public.airfnb_conversations where application_id = 'f2630000-0000-4000-8000-000000000200'),
  (select count(*) from public.airfnb_conversation_participants as participant
    join public.airfnb_conversations as conversation on conversation.id = participant.conversation_id
    where conversation.application_id = 'f2630000-0000-4000-8000-000000000200'),
  (select count(*) from public.airfnb_notifications
    where kind = 'application.accepted'
      and payload ->> 'application_id' = 'f2630000-0000-4000-8000-000000000200')
);
SQL
)"
[[ "$same_application_state" == 'accepted:1:1:1:2:1' ]] || {
  printf 'same-application race side effects drifted: %s\n' "$same_application_state" >&2
  exit 1
}
printf 'SAME_APPLICATION_RACE_VERIFIED state=%s\n' "$same_application_state"

run_rpc marketplace-slot-a accept f2630000-0000-4000-8000-000000000210 \
  >"$race_a_log" 2>&1 &
slot_a_pid=$!
run_rpc marketplace-slot-b accept f2630000-0000-4000-8000-000000000211 \
  >"$race_b_log" 2>&1 &
slot_b_pid=$!
set +e
wait "$slot_a_pid"; slot_a_status=$?
wait "$slot_b_pid"; slot_b_status=$?
set -e
assert_one_success_one_failure final_slot "$slot_a_status" "$race_a_log" \
  "$slot_b_status" "$race_b_log" 'request has no remaining slots'
final_slot_state="$("${psql_scratch[@]}" --tuples-only --no-align <<'SQL'
select pg_catalog.concat_ws(':',
  (select count(*) from public.airfnb_applications
    where request_id = 'f2630000-0000-4000-8000-000000000110' and status = 'accepted'),
  (select count(*) from public.airfnb_applications
    where request_id = 'f2630000-0000-4000-8000-000000000110' and status = 'submitted'),
  (select count(*) from public.airfnb_bookings as booking
    join public.airfnb_applications as application on application.id = booking.application_id
    where application.request_id = 'f2630000-0000-4000-8000-000000000110'),
  (select count(*) from public.airfnb_lock_fees as fee
    join public.airfnb_applications as application on application.id = fee.application_id
    where application.request_id = 'f2630000-0000-4000-8000-000000000110'),
  (select status from public.airfnb_event_requests where id = 'f2630000-0000-4000-8000-000000000110')
);
SQL
)"
[[ "$final_slot_state" == '1:1:1:1:awarded' ]] || {
  printf 'final-slot loser or side effects drifted: %s\n' "$final_slot_state" >&2
  exit 1
}
printf 'FINAL_SLOT_RACE_VERIFIED state=%s\n' "$final_slot_state"

run_rpc marketplace-independent-a accept f2630000-0000-4000-8000-000000000220 \
  >"$independent_a_log" 2>&1 &
independent_a_pid=$!
run_rpc marketplace-independent-b accept f2630000-0000-4000-8000-000000000221 \
  >"$independent_b_log" 2>&1 &
independent_b_pid=$!
set +e
wait "$independent_a_pid"; independent_a_status=$?
wait "$independent_b_pid"; independent_b_status=$?
set -e
if ((independent_a_status != 0 || independent_b_status != 0)); then
  printf 'independent request concurrency failed: %s/%s\n' \
    "$independent_a_status" "$independent_b_status" >&2
  sed -n '1,100p' "$independent_a_log" >&2
  sed -n '1,100p' "$independent_b_log" >&2
  exit 1
fi
independent_state="$("${psql_scratch[@]}" --tuples-only --no-align <<'SQL'
select pg_catalog.concat_ws(':',
  (select count(*) from public.airfnb_applications
    where id in ('f2630000-0000-4000-8000-000000000220','f2630000-0000-4000-8000-000000000221')
      and status = 'accepted'),
  (select count(*) from public.airfnb_bookings
    where application_id in ('f2630000-0000-4000-8000-000000000220','f2630000-0000-4000-8000-000000000221')),
  (select count(*) from public.airfnb_event_requests
    where id in ('f2630000-0000-4000-8000-000000000120','f2630000-0000-4000-8000-000000000121')
      and status = 'awarded')
);
SQL
)"
[[ "$independent_state" == '2:2:2' ]] || {
  printf 'independent request state drifted: %s\n' "$independent_state" >&2
  exit 1
}
printf 'INDEPENDENT_REQUEST_CONCURRENCY_VERIFIED state=%s\n' "$independent_state"

PGAPPNAME=marketplace-race-blocker "${psql_scratch[@]}" --command="
  begin;
  select id from public.airfnb_applications
   where id = 'f2630000-0000-4000-8000-000000000230' for update;
  select pg_catalog.pg_sleep(3);
  commit;" >"$blocker_log" 2>&1 &
blocker_pid=$!
wait_for_sleeping_blocker marketplace-race-blocker
run_rpc marketplace-race-reject reject f2630000-0000-4000-8000-000000000230 \
  >"$reject_log" 2>&1 &
reject_pid=$!
wait_for_lock_waiter marketplace-race-reject
run_rpc marketplace-race-shortlist shortlist f2630000-0000-4000-8000-000000000230 \
  >"$shortlist_log" 2>&1 &
shortlist_pid=$!
wait_for_lock_waiter marketplace-race-shortlist
set +e
wait "$blocker_pid"; blocker_status=$?
wait "$reject_pid"; reject_status=$?
wait "$shortlist_pid"; shortlist_status=$?
set -e
if ((blocker_status != 0 || reject_status != 0 || shortlist_status == 0)) \
  || ! grep -Fq 'application is not eligible for shortlist' "$shortlist_log"; then
  printf 'shortlist/reject serialization race failed: %s/%s/%s\n' \
    "$blocker_status" "$reject_status" "$shortlist_status" >&2
  sed -n '1,100p' "$blocker_log" >&2
  sed -n '1,100p' "$reject_log" >&2
  sed -n '1,100p' "$shortlist_log" >&2
  exit 1
fi
shortlist_reject_state="$("${psql_scratch[@]}" --tuples-only --no-align <<'SQL'
select pg_catalog.concat_ws(':',
  (select status from public.airfnb_applications where id = 'f2630000-0000-4000-8000-000000000230'),
  (select count(*) from public.airfnb_notifications
    where kind = 'application.rejected'
      and payload ->> 'application_id' = 'f2630000-0000-4000-8000-000000000230'),
  (select count(*) from public.airfnb_notifications
    where kind = 'application.shortlisted'
      and payload ->> 'application_id' = 'f2630000-0000-4000-8000-000000000230')
);
SQL
)"
[[ "$shortlist_reject_state" == 'rejected:1:0' ]] || {
  printf 'shortlist/reject final state drifted: %s\n' "$shortlist_reject_state" >&2
  exit 1
}
printf 'SHORTLIST_REJECT_RACE_VERIFIED state=%s\n' "$shortlist_reject_state"

"${psql_scratch[@]}" \
  --command='drop index public.airfnb_bookings_application_unique;' >/dev/null
final_drift_state="$(target_state_sha256)"
if "${psql_scratch[@]}" --file="$migration_file" >"$drift_log" 2>&1; then
  printf 'final uniqueness drift unexpectedly passed\n' >&2
  exit 1
fi
grep -Fq 'final booking uniqueness drifted' "$drift_log" || {
  sed -n '1,120p' "$drift_log" >&2
  exit 1
}
[[ "$final_drift_state" == "$(target_state_sha256)" ]] || {
  printf 'refused final-state drift changed target state\n' >&2
  exit 1
}
"${psql_scratch[@]}" --command="
  create unique index airfnb_bookings_application_unique
    on public.airfnb_bookings(application_id)
    where application_id is not null;" >/dev/null
[[ "$state_after_apply" == "$(target_state_sha256)" ]] || exit 1
printf 'FINAL_STATE_DRIFT_REJECTED\n'

"${psql_scratch[@]}" --file="$migration_file" >/dev/null
state_after_reapply="$(target_state_sha256)"
[[ "$state_after_apply" == "$state_after_reapply" ]] || {
  printf 'reapply changed final semantic state\n' >&2
  exit 1
}
printf 'GOOD_REAPPLY_VERIFIED state=%s\n' "$state_after_reapply"

cleanup_scratch
[[ "$(database_count "$scratch_database")" == 0 ]] || {
  printf 'scratch database remains after cleanup: %s\n' "$scratch_database" >&2
  exit 1
}
printf 'SCRATCH_CLEANED database=%s\n' "$scratch_database"

source_sha256_after="$(source_fingerprint)"
[[ "$source_sha256_before" == "$source_sha256_after" ]] || {
  printf 'source database fingerprint changed\n' >&2
  exit 1
}
artifact_manifest_after="$(artifact_manifest)"
[[ "$artifact_manifest_before" == "$artifact_manifest_after" ]] || {
  printf 'reconciliation artifacts changed while driver was running\n' >&2
  exit 1
}
source_fixture_count_after="$(PGOPTIONS='-c default_transaction_read_only=on' \
  "${psql_source[@]}" <<'SQL'
begin transaction read only;
select
  (select pg_catalog.count(*) from auth.users
    where id::text like any (array['f2620000-0000-4000-8000-%','f2630000-0000-4000-8000-%','f2640000-0000-4000-8000-%']))
  + (select pg_catalog.count(*) from public.airfnb_event_requests
    where id::text like any (array['f2620000-0000-4000-8000-%','f2630000-0000-4000-8000-%','f2640000-0000-4000-8000-%']))
  + (select pg_catalog.count(*) from public.airfnb_applications
    where id::text like any (array['f2620000-0000-4000-8000-%','f2630000-0000-4000-8000-%','f2640000-0000-4000-8000-%']));
rollback;
SQL
)"
[[ "$source_fixture_count_after" == 0 ]] || {
  printf 'source zero-fixture audit failed after scratch run: %s\n' "$source_fixture_count_after" >&2
  exit 1
}
scratch_residue="$(PGOPTIONS='-c default_transaction_read_only=on' \
  "${psql_source[@]}" --command="
    select pg_catalog.count(*) from pg_catalog.pg_database
     where datname like 'fb_tailor_catalog_%';")"
[[ "$scratch_residue" == 0 ]] || {
  printf 'scratch residue: %s\n' "$scratch_residue" >&2
  exit 1
}

printf 'SOURCE_SHA256_BEFORE=%s\n' "$source_sha256_before"
printf 'SOURCE_SHA256_AFTER=%s\n' "$source_sha256_after"
printf 'RUNTIME_INTEGRITY_PREDECESSOR_SHA256=%s\n' "$runtime_integrity_sha256"
printf 'PRIVACY_PREDECESSOR_SHA256=%s\n' "$privacy_sha256"
printf 'MESSAGING_PREDECESSOR_SHA256=%s\n' "$messaging_sha256"
printf 'STORAGE_PREDECESSOR_SHA256=%s\n' "$storage_sha256"
printf 'CATALOG_PREDECESSOR_SHA256=%s\n' "$catalog_sha256"
printf 'MIGRATION_SHA256=%s\n' "$(sha256_file "$migration_file")"
printf 'RUNTIME_SHA256=%s\n' "$(sha256_file "$runtime_file")"
printf 'SOURCE_TEST_SHA256=%s\n' "$(sha256_file "$source_test_file")"
printf 'DRIVER_SHA256=%s\n' "$(sha256_file "$driver_file")"
printf 'scratch residue: 0\n'
