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
  printf 'refusing non-absolute or root PostgreSQL socket directory: %s\n' \
    "$socket_directory" >&2
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
  printf 'refusing a PostgreSQL template database as the source fixture\n' >&2
  exit 64
}
[[ ! "$source_database" =~ ^fb_tailor_identity_runtime_ ]] || {
  printf 'refusing a runtime scratch database as the source fixture\n' >&2
  exit 64
}
[[ -S "$socket_directory/.s.PGSQL.$postgres_port" ]] || {
  printf 'local PostgreSQL socket does not exist for the explicit input\n' >&2
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
migration_file="$repository_root/supabase/migrations/20260819094823_airfnb_identity_reconciliation.sql"
runtime_file="$repository_root/tests/identity-reconciliation-runtime.sql"

[[ -f "$migration_file" && -f "$runtime_file" ]] || {
  printf 'identity reconciliation migration or runtime harness is missing\n' >&2
  exit 66
}

psql_source=(
  psql -X --no-psqlrc --host="$socket_directory" --port="$postgres_port"
  --dbname="$source_database" --set=ON_ERROR_STOP=1 --tuples-only --no-align
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
    --no-privileges \
    | sed '/^\\restrict /d; /^\\unrestrict /d' \
    | shasum -a 256 \
    | awk '{print $1}'
}

source_fixture_count() {
  "${psql_source[@]}" <<'SQL'
select
  (case when to_regnamespace('identity_runtime') is null then 0 else 1 end)
  + (case when to_regclass('auth.sessions') is null then 0 else 1 end)
  + (case when to_regclass('auth.refresh_tokens') is null then 0 else 1 end)
  + (case when to_regclass('auth.identities') is null then 0 else 1 end)
  + (case when to_regclass('auth.mfa_factors') is null then 0 else 1 end)
  + (select count(*) from auth.users
      where id::text in (
        '11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222',
        '33333333-3333-3333-3333-333333333333',
        '44444444-4444-4444-4444-444444444444',
        '55555555-5555-5555-5555-555555555555',
        '66666666-6666-6666-6666-666666666666',
        '77777777-7777-7777-7777-777777777777',
        '88888888-8888-8888-8888-888888888888',
        '99999999-9999-9999-9999-999999999999'
      ) or lower(email) = lower('seed@airfnb.local'))
  + (select count(*) from public.airfnb_profiles
      where id::text in (
        '11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222',
        '33333333-3333-3333-3333-333333333333',
        '44444444-4444-4444-4444-444444444444',
        '55555555-5555-5555-5555-555555555555',
        '66666666-6666-6666-6666-666666666666',
        '77777777-7777-7777-7777-777777777777',
        '88888888-8888-8888-8888-888888888888',
        '99999999-9999-9999-9999-999999999999'
      ))
  + (select count(*) from public.airfnb_trucks
      where slug = 'identity-runtime-unrelated-service')
  + (select count(*) from public.airfnb_blog_posts
      where slug = 'identity-runtime-unrelated-article')
  + (select count(*) from public.airfnb_blog_authors
      where id = '99999999-9999-9999-9999-999999999999');
SQL
}

database_count() {
  local database_name="$1"
  "${psql_source[@]}" --set=database_name="$database_name" <<'SQL'
select count(*)
  from pg_catalog.pg_database
 where datname = :'database_name';
SQL
}

source_contract="$("${psql_source[@]}" <<'SQL'
select concat_ws(':',
  (select count(*) from pg_catalog.pg_tables where schemaname = 'public'),
  (to_regprocedure('public.airfnb_guard_profile_role()') is not null)::integer,
  (to_regclass('auth.sessions') is null)::integer,
  (to_regclass('auth.refresh_tokens') is null)::integer,
  (to_regclass('auth.identities') is null)::integer,
  (to_regclass('auth.mfa_factors') is null)::integer,
  (select count(*) from public.airfnb_trucks
    where owner_id is null and slug in (
      'bbq-kings', 'creperia-pt', 'divine-burguers', 'el-mexicano',
      'gypsy-kitchen', 'la-dolce-vita', 'pizza-vesuvio',
      'portuguese-tradition', 'sushi-zen', 'taco-fiesta',
      'turkish-delights', 'wok-and-roll'
    )),
  (select count(*) from public.airfnb_blog_posts
    where author_id is null and status = 'published' and slug in (
      'casamentos-food-trucks-5-dicas',
      'como-organizar-evento-perfeito-food-trucks',
      'festivais-2025-o-que-ai-vem',
      'quanto-custa-catering-50-pessoas',
      'tendencias-gastronomicas-2025'
    ))
);
SQL
)"
[[ "$source_contract" == "41:1:1:1:1:1:12:5" ]] || {
  printf 'source database does not match the cumulative 41-table/guard/12/5 fixture: %s\n' \
    "$source_contract" >&2
  exit 65
}

source_fingerprint_before="$(source_fingerprint)"
source_fixture_count_before="$(source_fixture_count)"
[[ "$source_fingerprint_before" =~ ^[0-9a-f]{64}$ ]] || {
  printf 'failed to compute the source fingerprint\n' >&2
  exit 70
}
[[ "$source_fixture_count_before" == "0" ]] || {
  printf 'source zero-fixture audit failed before cloning: %s\n' \
    "$source_fixture_count_before" >&2
  exit 65
}
printf 'SOURCE_AUDIT_BEFORE fingerprint=%s fixture_count=%s contract=%s\n' \
  "$source_fingerprint_before" "$source_fixture_count_before" "$source_contract"

scratch_database="fb_tailor_identity_runtime_$$_$RANDOM"
failure_log=""
scratch_created=0

is_scratch_database() {
  [[ "$1" =~ ^fb_tailor_identity_runtime_[0-9]+_[0-9]+$ ]]
}

cleanup() {
  local exit_status=$?
  trap - EXIT INT TERM

  if [[ -n "$failure_log" && -f "$failure_log" ]]; then
    rm -f -- "$failure_log"
  fi

  if ((scratch_created == 1)); then
    if ! is_scratch_database "$scratch_database"; then
      printf 'refusing cleanup because scratch name validation failed: %s\n' \
        "$scratch_database" >&2
      exit_status=1
    elif dropdb \
      --host="$socket_directory" \
      --port="$postgres_port" \
      --maintenance-db=template1 \
      -- "$scratch_database"; then
      scratch_created=0
      residual_count="$(database_count "$scratch_database")"
      if [[ "$residual_count" == "0" ]]; then
        printf 'SCRATCH_CLEANUP_PASS database=%s residual_count=0\n' "$scratch_database"
      else
        printf 'scratch cleanup audit found a residual database: %s\n' \
          "$scratch_database" >&2
        exit_status=1
      fi
    else
      printf 'failed to drop the driver-created scratch database: %s\n' \
        "$scratch_database" >&2
      exit_status=1
    fi
  fi

  exit "$exit_status"
}
trap cleanup EXIT INT TERM

is_scratch_database "$scratch_database" || {
  printf 'generated scratch database name failed validation\n' >&2
  exit 70
}

preexisting_count="$(database_count "$scratch_database")"
[[ "$preexisting_count" == "0" ]] || {
  printf 'refusing pre-existing scratch database: %s\n' "$scratch_database" >&2
  exit 65
}

createdb \
  --host="$socket_directory" \
  --port="$postgres_port" \
  --maintenance-db=template1 \
  --template="$source_database" \
  -- "$scratch_database"
scratch_created=1
printf 'SCRATCH_CLONE_CREATED database=%s source=%s\n' \
  "$scratch_database" "$source_database"

psql_scratch=(
  psql -X --no-psqlrc --host="$socket_directory" --port="$postgres_port"
  --dbname="$scratch_database" --set=ON_ERROR_STOP=1
)

run_runtime_phase() {
  local phase="$1"
  "${psql_scratch[@]}" \
    --set=identity_runtime_database="$scratch_database" \
    --set=identity_runtime_phase="$phase" \
    --file="$runtime_file"
}

run_runtime_phase setup_drift

failure_log="$(mktemp "${TMPDIR:-/tmp}/fb-tailor-identity-failure.XXXXXX")"
set +e
"${psql_scratch[@]}" --file="$migration_file" >"$failure_log" 2>&1
intentional_failure_status=$?
set -e

if ((intentional_failure_status == 0)); then
  printf '11-of-12 candidate unexpectedly succeeded\n' >&2
  exit 1
fi
if ! grep -Fq \
  'identity reconciliation refused: expected exactly the 12 observed catalogue services' \
  "$failure_log"; then
  printf 'candidate failed for an unexpected reason (status %s):\n' \
    "$intentional_failure_status" >&2
  sed -n '1,120p' "$failure_log" >&2
  exit 1
fi
printf 'INTENTIONAL_FAILURE_OBSERVED status=%s error="%s"\n' \
  "$intentional_failure_status" \
  'identity reconciliation refused: expected exactly the 12 observed catalogue services'
rm -f -- "$failure_log"
failure_log=""

run_runtime_phase assert_failed_atomicity_and_prepare_good

"${psql_scratch[@]}" --file="$migration_file"
run_runtime_phase assert_good
printf 'GOOD_APPLY_VERIFIED database=%s\n' "$scratch_database"

"${psql_scratch[@]}" --file="$migration_file"
run_runtime_phase assert_good
printf 'GOOD_REAPPLY_VERIFIED database=%s\n' "$scratch_database"

run_runtime_phase role_paths

source_fingerprint_after="$(source_fingerprint)"
source_fixture_count_after="$(source_fixture_count)"
printf 'SOURCE_AUDIT_AFTER fingerprint=%s fixture_count=%s\n' \
  "$source_fingerprint_after" "$source_fixture_count_after"

[[ "$source_fingerprint_after" == "$source_fingerprint_before" ]] || {
  printf 'source fingerprint changed during disposable testing\n' >&2
  exit 1
}
[[ "$source_fixture_count_after" == "$source_fixture_count_before" \
  && "$source_fixture_count_after" == "0" ]] || {
  printf 'source zero-fixture audit changed during disposable testing\n' >&2
  exit 1
}

printf 'SOURCE_FINGERPRINT_AND_ZERO_FIXTURE_PASS fingerprint=%s fixture_count=0\n' \
  "$source_fingerprint_after"
printf 'IDENTITY_RECONCILIATION_DRIVER_PASS database=%s\n' "$scratch_database"
