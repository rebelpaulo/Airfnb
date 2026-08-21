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
    *)
      usage
      ;;
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
  printf 'refusing unsafe source database name: %s\n' "$source_database" >&2
  exit 64
}
[[ "$source_database" != "template0" && "$source_database" != "template1" ]] || {
  printf 'refusing a PostgreSQL template database as source\n' >&2
  exit 64
}
[[ ! "$source_database" =~ ^fb_tailor_privacy_ ]] || {
  printf 'refusing a privacy scratch database as source\n' >&2
  exit 64
}
[[ -S "$socket_directory/.s.PGSQL.$postgres_port" ]] || {
  printf 'explicit local PostgreSQL socket does not exist\n' >&2
  exit 66
}

for required_command in psql pg_dump createdb dropdb shasum sed awk grep mktemp; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'required local command is unavailable: %s\n' "$required_command" >&2
    exit 69
  }
done

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
migration_file="$repository_root/supabase/migrations/20260820153725_public_event_request_privacy_reconciliation.sql"
runtime_file="$repository_root/tests/public-request-privacy-reconciliation-runtime.sql"

[[ -f "$migration_file" && -f "$runtime_file" ]] || {
  printf 'privacy reconciliation migration or runtime harness is missing\n' >&2
  exit 66
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

sha256_stream() {
  shasum -a 256 | awk '{print $1}'
}

psql_source=(
  psql -X --no-psqlrc --host="$socket_directory" --port="$postgres_port"
  --dbname="$source_database" --set=ON_ERROR_STOP=1 --tuples-only --no-align
  --quiet
)

actual_source_database="$("${psql_source[@]}" --command='select current_database();')"
[[ "$actual_source_database" == "$source_database" ]] || {
  printf 'source database connection mismatch: expected %s, got %s\n' \
    "$source_database" "$actual_source_database" >&2
  exit 65
}

source_fingerprint() {
  pg_dump \
    --host="$socket_directory" \
    --port="$postgres_port" \
    --dbname="$source_database" \
    --format=plain \
    --schema=auth \
    --schema=public \
    --no-owner \
    | sed '/^\\restrict /d; /^\\unrestrict /d' \
    | sha256_stream
}

database_count() {
  local database_name="$1"
  "${psql_source[@]}" --set=database_name="$database_name" <<'SQL'
select pg_catalog.count(*)
  from pg_catalog.pg_database
 where datname = :'database_name';
SQL
}

source_contract="$("${psql_source[@]}" <<'SQL'
begin transaction read only;
select pg_catalog.concat_ws(
  ':',
  (select pg_catalog.count(*)
     from pg_catalog.pg_attribute
    where attrelid = 'public.airfnb_event_requests'::regclass
      and attnum > 0 and not attisdropped),
  (select pg_catalog.md5(pg_catalog.string_agg(
            pg_catalog.format('%s:%s:%s', attname, pg_catalog.format_type(atttypid, atttypmod), attnotnull),
            ',' order by attnum
          ))
     from pg_catalog.pg_attribute
    where attrelid = 'public.airfnb_event_requests'::regclass
      and attnum > 0 and not attisdropped),
  (select pg_catalog.md5(pg_catalog.string_agg(
            pg_catalog.concat_ws('|', polname, polcmd, polpermissive, polroles::text,
              coalesce(pg_catalog.pg_get_expr(polqual, polrelid), ''),
              coalesce(pg_catalog.pg_get_expr(polwithcheck, polrelid), '')),
            E'\n' order by polname
          ))
     from pg_catalog.pg_policy
    where polrelid = 'public.airfnb_event_requests'::regclass),
  (select (pg_catalog.length(prosrc) - pg_catalog.length(pg_catalog.replace(prosrc, 'select *', ''))) / 8
     from pg_catalog.pg_proc
    where oid = 'public.airfnb_match_score(uuid,uuid)'::regprocedure),
  (select pg_catalog.count(*)
     from pg_catalog.pg_attribute
    where attrelid = 'public.airfnb_event_requests'::regclass
      and attnum > 0 and not attisdropped
      and pg_catalog.has_column_privilege('anon', attrelid, attnum, 'SELECT')),
  (select pg_catalog.count(*)
     from pg_catalog.pg_attribute
    where attrelid = 'public.airfnb_event_requests'::regclass
      and attnum > 0 and not attisdropped
      and pg_catalog.has_column_privilege('authenticated', attrelid, attnum, 'SELECT')),
  pg_catalog.has_table_privilege('anon', 'public.airfnb_event_requests', 'SELECT')::integer,
  pg_catalog.has_table_privilege('authenticated', 'public.airfnb_event_requests', 'SELECT')::integer,
  pg_catalog.has_table_privilege('service_role', 'public.airfnb_event_requests', 'SELECT')::integer,
  (select pg_catalog.md5(pg_catalog.string_agg(
            pg_catalog.concat_ws('|', relation.relname, policy.polname, policy.polcmd,
              policy.polpermissive, policy.polroles::text,
              coalesce(pg_catalog.pg_get_expr(policy.polqual, policy.polrelid), ''),
              coalesce(pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid), '')),
            E'\n' order by relation.relname, policy.polname
          ))
     from pg_catalog.pg_policy as policy
     join pg_catalog.pg_class as relation on relation.oid = policy.polrelid
    where policy.polrelid in (
      'public.airfnb_truck_categories'::regclass,
      'public.airfnb_truck_availability'::regclass
    )),
  (select pg_catalog.count(*)
     from pg_catalog.pg_attribute as attribute
    where attribute.attrelid in (
      'public.airfnb_truck_categories'::regclass,
      'public.airfnb_truck_availability'::regclass
    )
      and attribute.attnum > 0
      and not attribute.attisdropped
      and (
        pg_catalog.has_column_privilege(
          'anon', attribute.attrelid, attribute.attnum, 'SELECT'
        )
        or pg_catalog.has_column_privilege(
          'authenticated', attribute.attrelid, attribute.attnum, 'SELECT'
        )
      ))
);
rollback;
SQL
)"
[[ "$source_contract" == "50:b1c7105b115d8fe4bed8fb89882c993d:be3e742b43c1e53d2a5dd22720ad30ce:2:45:45:0:0:1:27f0dfa2dfe1fed0a5667e0bc9c1dfb5:0" ]] || {
  printf 'source database does not match the verified old-candidate fixture: %s\n' \
    "$source_contract" >&2
  exit 65
}

source_fixture_count_before="$("${psql_source[@]}" <<'SQL'
begin transaction read only;
select
  (select pg_catalog.count(*) from auth.users
    where id::text like 'f2500000-0000-4000-8000-%')
  + (select pg_catalog.count(*) from public.airfnb_event_requests
    where id::text like 'f2500000-0000-4000-8000-%')
  + (select pg_catalog.count(*) from public.airfnb_trucks
    where id::text like 'f2500000-0000-4000-8000-%');
rollback;
SQL
)"
[[ "$source_fixture_count_before" == "0" ]] || {
  printf 'source zero-fixture audit failed before cloning: %s\n' \
    "$source_fixture_count_before" >&2
  exit 65
}

source_sha256_before="$(source_fingerprint)"
candidate_sha256="$(sha256_file "$migration_file")"
runtime_sha256="$(sha256_file "$runtime_file")"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/fb-tailor-privacy.XXXXXX")"
failure_log="$temporary_directory/intentional-failure.log"
denial_log="$temporary_directory/denial.log"
scratch_database=""
scratch_created=0

is_scratch_database() {
  [[ "$1" =~ ^fb_tailor_privacy_[0-9]+_[0-9]+_(historical|storage)$ ]]
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
  if ! cleanup_scratch; then
    exit_status=1
  fi
  rm -f -- "$failure_log" "$denial_log"
  rmdir "$temporary_directory" 2>/dev/null || true
  exit "$exit_status"
}
trap cleanup EXIT INT TERM

target_state_sha256() {
  "${psql_scratch[@]}" --tuples-only --no-align --field-separator='|' <<'SQL' \
    | sha256_stream
select 'function', procedure.oid::text, procedure.proowner::text,
       procedure.prosecdef::text, procedure.provolatile::text,
       coalesce(pg_catalog.array_to_string(procedure.proconfig, ','), ''),
       coalesce(procedure.proacl::text, ''),
       pg_catalog.md5(procedure.prosrc)
  from pg_catalog.pg_proc as procedure
  join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
 where namespace.nspname = 'public'
   and procedure.proname in (
     'airfnb_match_score', 'airfnb_match_scores_batch',
     'airfnb_match_category_availability_score',
     'airfnb_find_matching_requests', 'airfnb_find_matching_trucks',
     'airfnb_recommend_trucks_for_request', 'airfnb_is_admin',
     'airfnb_user_owns_invited_truck', 'airfnb_user_organizes_request',
     'airfnb_private_event_requests'
   )
union all
select 'relation', relation.oid::text, relation.relowner::text,
       relation.relrowsecurity::text, relation.relforcerowsecurity::text,
       '', coalesce(relation.relacl::text, ''), ''
  from pg_catalog.pg_class as relation
 where relation.oid in (
   'public.airfnb_event_requests'::regclass,
   'public.airfnb_truck_categories'::regclass,
   'public.airfnb_truck_availability'::regclass
 )
union all
select 'column', attribute.attrelid::text, attribute.attnum::text,
       false::text, false::text, '',
       coalesce(attribute.attacl::text, ''), attribute.attname
  from pg_catalog.pg_attribute as attribute
 where attribute.attrelid in (
   'public.airfnb_event_requests'::regclass,
   'public.airfnb_truck_categories'::regclass,
   'public.airfnb_truck_availability'::regclass
 )
   and attribute.attnum > 0 and not attribute.attisdropped
union all
select 'policy', '0', '0', polpermissive::text, false::text,
       polcmd::text, polroles::text,
       pg_catalog.md5(pg_catalog.concat_ws('|', polname,
         coalesce(pg_catalog.pg_get_expr(polqual, polrelid), ''),
         coalesce(pg_catalog.pg_get_expr(polwithcheck, polrelid), '')))
  from pg_catalog.pg_policy
 where polrelid in (
   'public.airfnb_event_requests'::regclass,
   'public.airfnb_truck_categories'::regclass,
   'public.airfnb_truck_availability'::regclass
 )
order by 1, 2, 3, 8;
SQL
}

run_runtime_phase() {
  local phase="$1"
  local prestate="$2"
  local historical_flag=0
  if [[ "$prestate" == "historical" ]]; then
    historical_flag=1
  fi
  "${psql_scratch[@]}" \
    --set=privacy_runtime_database="$scratch_database" \
    --set=privacy_runtime_phase="$phase" \
    --set=privacy_prestate="$prestate" \
    --set=privacy_prestate_historical="$historical_flag" \
    --file="$runtime_file" >/dev/null
}

assert_sql_denied() {
  local role_name="$1"
  local label="$2"
  local sql="$3"
  local expected_message="$4"

  case "$role_name" in
    anon|authenticated|service_role) ;;
    *) printf 'unsafe denial role: %s\n' "$role_name" >&2; return 1 ;;
  esac

  if "${psql_scratch[@]}" --command="begin; set local role $role_name; $sql; rollback;" \
    >"$denial_log" 2>&1; then
    printf 'denial unexpectedly succeeded: %s/%s\n' "$role_name" "$label" >&2
    return 1
  fi
  if ! grep -Fq "$expected_message" "$denial_log"; then
    printf 'denial failed for an unexpected reason: %s/%s\n' "$role_name" "$label" >&2
    sed -n '1,80p' "$denial_log" >&2
    return 1
  fi
}

for prestate in historical storage; do
  scratch_database="fb_tailor_privacy_$$_${RANDOM}_${prestate}"
  is_scratch_database "$scratch_database" || {
    printf 'generated scratch database name failed validation\n' >&2
    exit 70
  }
  [[ "$(database_count "$scratch_database")" == "0" ]] || {
    printf 'refusing pre-existing scratch database: %s\n' "$scratch_database" >&2
    exit 65
  }

  createdb --host="$socket_directory" --port="$postgres_port" \
    --maintenance-db=template1 --template="$source_database" -- "$scratch_database"
  scratch_created=1
  printf 'SCRATCH_CLONE_CREATED database=%s prestate=%s\n' "$scratch_database" "$prestate"

  psql_scratch=(
    psql -X --no-psqlrc --host="$socket_directory" --port="$postgres_port"
    --dbname="$scratch_database" --set=ON_ERROR_STOP=1
  )
  clone_name="$("${psql_scratch[@]}" --tuples-only --no-align --command='select current_database();')"
  [[ "$clone_name" == "$scratch_database" ]] || {
    printf 'scratch clone identity mismatch\n' >&2
    exit 65
  }

  run_runtime_phase setup "$prestate"
  if [[ "$prestate" == "historical" ]]; then
    run_runtime_phase assert_pre_historical "$prestate"
    printf 'PRE_FIX_HISTORICAL_PII_AND_RAW_CATEGORY_EXPOSURE_REPRODUCED prestate=%s\n' "$prestate"
  else
    run_runtime_phase assert_pre_storage "$prestate"
    assert_sql_denied anon pii_select \
      "select contact_email from public.airfnb_event_requests limit 1" \
      "permission denied"
    assert_sql_denied authenticated match_select_star \
      "select public.airfnb_match_score('f2500000-0000-4000-8000-000000000020','f2500000-0000-4000-8000-000000000030')" \
      "permission denied for table airfnb_event_requests"
    printf 'PRE_FIX_STORAGE_CANDIDATE_SELECT_STAR_FAILURE_REPRODUCED prestate=%s\n' "$prestate"
  fi

  "${psql_scratch[@]}" <<'SQL' >/dev/null
create schema privacy_reconciliation_sabotage;
create function privacy_reconciliation_sabotage.fail_after_match_score()
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
       and v_command.object_identity like 'public.airfnb_match_score(%' then
      raise exception 'intentional public-request privacy rollback proof';
    end if;
  end loop;
end
$sabotage$;
create event trigger privacy_reconciliation_sabotage
  on ddl_command_end
  execute function privacy_reconciliation_sabotage.fail_after_match_score();
SQL

  state_before_failure="$(target_state_sha256)"
  if "${psql_scratch[@]}" --file="$migration_file" >"$failure_log" 2>&1; then
    printf 'intentional mid-migration failure unexpectedly succeeded\n' >&2
    exit 1
  fi
  if ! grep -Fq 'intentional public-request privacy rollback proof' "$failure_log"; then
    printf 'candidate failed for an unexpected reason:\n' >&2
    sed -n '1,120p' "$failure_log" >&2
    exit 1
  fi
  state_after_failure="$(target_state_sha256)"
  [[ "$state_before_failure" == "$state_after_failure" ]] || {
    printf 'intentional failure did not roll target state back\n' >&2
    exit 1
  }
  printf 'INTENTIONAL_FAILURE_ROLLBACK_VERIFIED prestate=%s state=%s\n' \
    "$prestate" "$state_after_failure"

  "${psql_scratch[@]}" \
    --command='drop event trigger privacy_reconciliation_sabotage' \
    --command='drop schema privacy_reconciliation_sabotage cascade' >/dev/null

  "${psql_scratch[@]}" --file="$migration_file" >/dev/null
  state_after_apply="$(target_state_sha256)"
  run_runtime_phase assert_good "$prestate"

  for role_name in anon authenticated; do
    assert_sql_denied "$role_name" pii_select \
      "select contact_name, contact_email, contact_phone, address_line, address_id from public.airfnb_event_requests limit 1" \
      "permission denied"
    assert_sql_denied "$role_name" raw_categories \
      "select truck_id, category_id from public.airfnb_truck_categories limit 1" \
      "permission denied for table airfnb_truck_categories"
    assert_sql_denied "$role_name" raw_availability \
      "select id, truck_id, date, status, booking_id from public.airfnb_truck_availability limit 1" \
      "permission denied for table airfnb_truck_availability"
  done
  for role_name in anon service_role; do
    assert_sql_denied "$role_name" match_score \
      "select public.airfnb_match_score('f2500000-0000-4000-8000-000000000020','f2500000-0000-4000-8000-000000000030')" \
      "permission denied for function airfnb_match_score"
    assert_sql_denied "$role_name" match_scores_batch \
      "select * from public.airfnb_match_scores_batch('{}'::uuid[],'{}'::uuid[])" \
      "permission denied for function airfnb_match_scores_batch"
    assert_sql_denied "$role_name" category_availability_helper \
      "select public.airfnb_match_category_availability_score('f2500000-0000-4000-8000-000000000020','f2500000-0000-4000-8000-000000000030')" \
      "permission denied for function airfnb_match_category_availability_score"
    assert_sql_denied "$role_name" private_event_requests \
      "select * from public.airfnb_private_event_requests(null)" \
      "permission denied for function airfnb_private_event_requests"
  done

  "${psql_scratch[@]}" --file="$migration_file" >/dev/null
  state_after_reapply="$(target_state_sha256)"
  [[ "$state_after_apply" == "$state_after_reapply" ]] || {
    printf 'reapply changed target OIDs, owners, definitions, policies, or ACLs\n' >&2
    exit 1
  }
  run_runtime_phase assert_good "$prestate"
  printf 'GOOD_APPLY_REAPPLY_VERIFIED prestate=%s applied=%s reapplied=%s\n' \
    "$prestate" "$state_after_apply" "$state_after_reapply"

  completed_database="$scratch_database"
  cleanup_scratch
  scratch_residue="$(database_count "$completed_database")"
  [[ "$scratch_residue" == "0" ]] || {
    printf 'scratch database residue remains: %s\n' "$completed_database" >&2
    exit 1
  }
  printf 'SCRATCH_CLEANUP_PASS prestate=%s database=%s residual_count=0\n' \
    "$prestate" "$completed_database"
done

source_fixture_count_after="$("${psql_source[@]}" <<'SQL'
begin transaction read only;
select
  (select pg_catalog.count(*) from auth.users
    where id::text like 'f2500000-0000-4000-8000-%')
  + (select pg_catalog.count(*) from public.airfnb_event_requests
    where id::text like 'f2500000-0000-4000-8000-%')
  + (select pg_catalog.count(*) from public.airfnb_trucks
    where id::text like 'f2500000-0000-4000-8000-%');
rollback;
SQL
)"
source_sha256_after="$(source_fingerprint)"
scratch_residue="$("${psql_source[@]}" <<'SQL'
select pg_catalog.count(*)
  from pg_catalog.pg_database
 where datname like 'fb_tailor_privacy_%';
SQL
)"

[[ "$source_fixture_count_after" == "0" ]] || {
  printf 'source fixture audit changed: %s\n' "$source_fixture_count_after" >&2
  exit 1
}
[[ "$source_sha256_before" == "$source_sha256_after" ]] || {
  printf 'source database fingerprint changed\n' >&2
  exit 1
}
[[ "$scratch_residue" == "0" ]] || {
  printf 'privacy scratch database residue remains: %s\n' "$scratch_residue" >&2
  exit 1
}

printf 'CANDIDATE_SHA256=%s\n' "$candidate_sha256"
printf 'RUNTIME_SHA256=%s\n' "$runtime_sha256"
printf 'SOURCE_SHA256_BEFORE=%s\n' "$source_sha256_before"
printf 'SOURCE_SHA256_AFTER=%s\n' "$source_sha256_after"
printf 'SOURCE_CONTRACT=%s\n' "$source_contract"
printf 'SOURCE_FIXTURE_COUNT_BEFORE=%s\n' "$source_fixture_count_before"
printf 'SOURCE_FIXTURE_COUNT_AFTER=%s\n' "$source_fixture_count_after"
printf 'SCRATCH_RESIDUE=%s\n' "$scratch_residue"
printf 'public request privacy reconciliation: PASS\n'
