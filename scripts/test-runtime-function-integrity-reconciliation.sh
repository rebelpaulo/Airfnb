#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "usage: $0 --socket SOCKET_DIR --port PORT --source-db DATABASE" >&2
}

SOCKET_DIR=""
PORT=""
SOURCE_DB=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --socket)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SOCKET_DIR=$2
      shift 2
      ;;
    --port)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      PORT=$2
      shift 2
      ;;
    --source-db)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SOURCE_DB=$2
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$SOCKET_DIR" || -z "$PORT" || -z "$SOURCE_DB" ]]; then
  usage
  exit 2
fi

if [[ ! "$PORT" =~ ^[0-9]+$ ]] || [[ ! -d "$SOCKET_DIR" ]]; then
  echo "invalid local PostgreSQL socket or port" >&2
  exit 2
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)
MIGRATION="$REPO_ROOT/supabase/migrations/20260820152018_airfnb_runtime_function_integrity_reconciliation.sql"
RUNTIME_SQL="$REPO_ROOT/tests/runtime-function-integrity-reconciliation-runtime.sql"

if [[ ! -f "$MIGRATION" || ! -f "$RUNTIME_SQL" ]]; then
  echo "runtime-function-integrity artifacts are missing" >&2
  exit 1
fi

for command_name in psql createdb dropdb pg_dump; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "required command is unavailable: $command_name" >&2
    exit 1
  fi
done

sha256_stream() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    echo "no SHA-256 command is available" >&2
    return 1
  fi
}

sha256_file() {
  local file_path=$1
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file_path" | awk '{print $1}'
  else
    echo "no SHA-256 command is available" >&2
    return 1
  fi
}

database_fingerprint() {
  pg_dump \
    -h "$SOCKET_DIR" \
    -p "$PORT" \
    -d "$SOURCE_DB" \
    --no-owner \
    --no-privileges \
    | sed -e '/^\\restrict /d' -e '/^\\unrestrict /d' \
    | sha256_stream
}

PSQL_SOURCE=(
  psql -h "$SOCKET_DIR" -p "$PORT" -d "$SOURCE_DB"
  -X -v ON_ERROR_STOP=1 -At
)

SOURCE_MATCHES=$(
  "${PSQL_SOURCE[@]}" \
    -c "select count(*) from pg_catalog.pg_database where datname = pg_catalog.current_database() and datallowconn and not datistemplate"
)
if [[ "$SOURCE_MATCHES" != "1" ]]; then
  echo "source database is absent, a template, or not connectable" >&2
  exit 1
fi

SCRATCH_DB="fb_tailor_rfi_$$_${RANDOM}"
if [[ ! "$SCRATCH_DB" =~ ^fb_tailor_rfi_[0-9]+_[0-9]+$ ]] || [[ "$SCRATCH_DB" == "$SOURCE_DB" ]]; then
  echo "unsafe scratch database name" >&2
  exit 1
fi

SCRATCH_CREATED=0
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fb-tailor-rfi.XXXXXX")
FAILURE_LOG="$TEMP_DIR/intentional-failure.log"
DENIAL_LOG="$TEMP_DIR/direct-denial.log"

cleanup_files() {
  rm -f "$FAILURE_LOG" "$DENIAL_LOG"
  rmdir "$TEMP_DIR" 2>/dev/null || true
}

cleanup_scratch() {
  if [[ "$SCRATCH_CREATED" -eq 1 ]]; then
    if [[ "$SCRATCH_DB" =~ ^fb_tailor_rfi_[0-9]+_[0-9]+$ ]] \
      && [[ "$SCRATCH_DB" != "$SOURCE_DB" ]]; then
      dropdb -h "$SOCKET_DIR" -p "$PORT" "$SCRATCH_DB"
      SCRATCH_CREATED=0
    else
      echo "refusing unsafe scratch cleanup target" >&2
      return 1
    fi
  fi
}

cleanup_on_exit() {
  local exit_status=$?
  trap - EXIT
  if ! cleanup_scratch; then
    exit_status=1
  fi
  cleanup_files
  exit "$exit_status"
}
trap cleanup_on_exit EXIT

SOURCE_SHA256_BEFORE=$(database_fingerprint)
CANDIDATE_SHA256=$(sha256_file "$MIGRATION")

SCRATCH_MATCHES=$(
  "${PSQL_SOURCE[@]}" \
    -c "select count(*) from pg_catalog.pg_database where datname = '$SCRATCH_DB'"
)
if [[ "$SCRATCH_MATCHES" != "0" ]]; then
  echo "refusing pre-existing scratch database" >&2
  exit 1
fi

createdb -h "$SOCKET_DIR" -p "$PORT" --template="$SOURCE_DB" "$SCRATCH_DB"
SCRATCH_CREATED=1

PSQL_SCRATCH=(
  psql -h "$SOCKET_DIR" -p "$PORT" -d "$SCRATCH_DB"
  -X -v ON_ERROR_STOP=1
)

CLONE_NAME=$("${PSQL_SCRATCH[@]}" -Atc "select pg_catalog.current_database()")
if [[ "$CLONE_NAME" != "$SCRATCH_DB" ]]; then
  echo "clone identity validation failed" >&2
  exit 1
fi

target_state_sha256() {
  "${PSQL_SCRATCH[@]}" -At -F '|' -c "
    select procedure.oid,
           procedure.proowner,
           procedure.prosecdef,
           coalesce(pg_catalog.array_to_string(procedure.proconfig, ','), ''),
           coalesce(procedure.proacl::text, ''),
           pg_catalog.md5(pg_catalog.pg_get_functiondef(procedure.oid))
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace
        on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname in (
         'airfnb_generate_referral_code',
         'airfnb_assign_referral_code',
         'airfnb_handle_new_user'
       )
     order by procedure.proname,
              pg_catalog.pg_get_function_identity_arguments(procedure.oid)
  " | sha256_stream
}

assert_direct_call_denied() {
  local role_name=$1
  local function_name=$2
  local call_sql

  case "$role_name" in
    anon|authenticated|service_role) ;;
    *) echo "unsafe direct-call role" >&2; return 1 ;;
  esac

  case "$function_name" in
    airfnb_generate_referral_code|airfnb_assign_referral_code|airfnb_handle_new_user) ;;
    *) echo "unsafe direct-call function" >&2; return 1 ;;
  esac

  call_sql="set role $role_name; select public.$function_name();"
  if "${PSQL_SCRATCH[@]}" -c "$call_sql" >"$DENIAL_LOG" 2>&1; then
    echo "direct call unexpectedly succeeded for $role_name/$function_name" >&2
    return 1
  fi
  if ! grep -Fq "permission denied for function $function_name" "$DENIAL_LOG"; then
    echo "direct call failed for an unexpected reason: $role_name/$function_name" >&2
    sed -n '1,80p' "$DENIAL_LOG" >&2
    return 1
  fi
}

assert_all_direct_calls_denied() {
  local role_name
  local function_name

  for role_name in anon authenticated service_role; do
    for function_name in \
      airfnb_generate_referral_code \
      airfnb_assign_referral_code \
      airfnb_handle_new_user
    do
      assert_direct_call_denied "$role_name" "$function_name"
    done
  done
}

install_sabotage() {
  "${PSQL_SCRATCH[@]}" >/dev/null <<'SQL'
create schema rfi_runtime_integrity_sabotage;

create function rfi_runtime_integrity_sabotage.fail_after_generator()
returns event_trigger
language plpgsql
set search_path = pg_catalog, public
as $sabotage$
declare
  v_command record;
begin
  for v_command in select * from pg_catalog.pg_event_trigger_ddl_commands()
  loop
    if v_command.command_tag = 'CREATE FUNCTION'
       and v_command.object_identity = 'public.airfnb_assign_referral_code()' then
      if not exists (
        select 1
          from pg_catalog.pg_proc as procedure
          join pg_catalog.pg_namespace as namespace
            on namespace.oid = procedure.pronamespace
         where namespace.nspname = 'public'
           and procedure.proname = 'airfnb_generate_referral_code'
           and pg_catalog.strpos(procedure.prosrc, 'if v_attempts > 10 then') > 0
      ) then
        raise exception 'rollback proof reached assignment without generator replacement';
      end if;

      raise exception 'intentional runtime-function-integrity rollback proof';
    end if;
  end loop;
end
$sabotage$;

create event trigger rfi_runtime_integrity_sabotage
  on ddl_command_end
  execute function rfi_runtime_integrity_sabotage.fail_after_generator();
SQL
}

remove_sabotage() {
  "${PSQL_SCRATCH[@]}" \
    -c "drop event trigger rfi_runtime_integrity_sabotage" \
    -c "drop schema rfi_runtime_integrity_sabotage cascade" >/dev/null
}

assert_prestate_rejected() {
  local rejection_name=$1
  local before_rejection
  local after_rejection

  before_rejection=$(target_state_sha256)
  if "${PSQL_SCRATCH[@]}" -f "$MIGRATION" >"$FAILURE_LOG" 2>&1; then
    echo "$rejection_name prestate unexpectedly passed" >&2
    return 1
  fi
  if ! grep -Fq "mixed or unknown prestate" "$FAILURE_LOG"; then
    echo "$rejection_name prestate failed for an unexpected reason" >&2
    sed -n '1,120p' "$FAILURE_LOG" >&2
    return 1
  fi
  after_rejection=$(target_state_sha256)
  if [[ "$before_rejection" != "$after_rejection" ]]; then
    echo "$rejection_name rejection changed target state" >&2
    return 1
  fi
}

MATRIX_RESULT_LINES=""

run_complete_matrix() {
  local matrix_name=$1
  local state_before_failure
  local state_after_failure
  local state_after_apply
  local state_after_reapply

  install_sabotage
  state_before_failure=$(target_state_sha256)
  if "${PSQL_SCRATCH[@]}" -f "$MIGRATION" >"$FAILURE_LOG" 2>&1; then
    echo "$matrix_name intentional mid-migration failure unexpectedly succeeded" >&2
    return 1
  fi
  if ! grep -Fq "intentional runtime-function-integrity rollback proof" "$FAILURE_LOG"; then
    echo "$matrix_name migration failed for an unexpected reason" >&2
    sed -n '1,120p' "$FAILURE_LOG" >&2
    return 1
  fi
  state_after_failure=$(target_state_sha256)
  if [[ "$state_before_failure" != "$state_after_failure" ]]; then
    echo "$matrix_name intentional failure did not roll target state back" >&2
    return 1
  fi
  remove_sabotage

  "${PSQL_SCRATCH[@]}" -f "$MIGRATION" >/dev/null
  state_after_apply=$(target_state_sha256)
  "${PSQL_SCRATCH[@]}" -f "$RUNTIME_SQL" >/dev/null
  assert_all_direct_calls_denied

  "${PSQL_SCRATCH[@]}" -f "$MIGRATION" >/dev/null
  state_after_reapply=$(target_state_sha256)
  if [[ "$state_after_apply" != "$state_after_reapply" ]]; then
    echo "$matrix_name reapply changed target OIDs, owners, definitions, or ACLs" >&2
    return 1
  fi
  "${PSQL_SCRATCH[@]}" -f "$RUNTIME_SQL" >/dev/null
  assert_all_direct_calls_denied

  MATRIX_RESULT_LINES="${MATRIX_RESULT_LINES}
${matrix_name}_FAILED_APPLY_STATE_SHA256=$state_after_failure
${matrix_name}_APPLIED_STATE_SHA256=$state_after_apply
${matrix_name}_REAPPLIED_STATE_SHA256=$state_after_reapply"
}

# Prove that the whole-state classifier rejects a mixture of accepted states
# and a mode that belongs to no accepted state, without changing either state.
"${PSQL_SCRATCH[@]}" \
  -c "alter function public.airfnb_handle_new_user() set search_path = pg_catalog, public" \
  >/dev/null
assert_prestate_rejected "MIXED_PRESTATE"
"${PSQL_SCRATCH[@]}" \
  -c "alter function public.airfnb_handle_new_user() set search_path = public" \
  >/dev/null

"${PSQL_SCRATCH[@]}" \
  -c "alter function public.airfnb_generate_referral_code() stable" \
  >/dev/null
assert_prestate_rejected "UNKNOWN_PRESTATE"
"${PSQL_SCRATCH[@]}" \
  -c "alter function public.airfnb_generate_referral_code() volatile" \
  >/dev/null

run_complete_matrix "OLD_CANDIDATE"

# Reconstruct only the exact 202605 remote function/trigger state from the
# pinned migrations. DROP/CREATE is scratch-only and deliberately restores
# PostgreSQL's NULL/default ACL on the two then-new referral functions.
"${PSQL_SCRATCH[@]}" >/dev/null <<'SQL'
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

drop trigger airfnb_profile_referral_code on public.airfnb_profiles;
drop function public.airfnb_assign_referral_code();
drop function public.airfnb_generate_referral_code();

create function public.airfnb_generate_referral_code()
returns text
language plpgsql
as $$
declare
  v_code text;
  v_attempts int := 0;
begin
  loop
    v_attempts := v_attempts + 1;
    -- Base32 alphabet without 0/O/I/L
    v_code := upper(substr(encode(gen_random_bytes(6), 'base64'), 1, 8));
    v_code := regexp_replace(v_code, '[+/=0OIL]', 'X', 'g');
    exit when not exists (select 1 from public.airfnb_profiles where referral_code = v_code);
    if v_attempts > 10 then raise exception 'could not generate unique referral code'; end if;
  end loop;
  return v_code;
end $$;

create function public.airfnb_assign_referral_code()
returns trigger
language plpgsql
as $$
begin
  if new.referral_code is null then
    new.referral_code := public.airfnb_generate_referral_code();
  end if;
  return new;
end $$;

create trigger airfnb_profile_referral_code
  before insert on public.airfnb_profiles
  for each row execute function public.airfnb_assign_referral_code();

alter function public.airfnb_handle_new_user()
  security definer;
alter function public.airfnb_handle_new_user()
  set search_path = public;
commit;
SQL

run_complete_matrix "HISTORICAL_REMOTE"

RESIDUAL_TEST_ROWS=$("${PSQL_SCRATCH[@]}" -Atc "
  select count(*)
    from auth.users
   where id in (
     'f1000000-0000-4000-8000-000000000001',
     'f1000000-0000-4000-8000-000000000002',
     'f1000000-0000-4000-8000-000000000003',
     'f1000000-0000-4000-8000-000000000004'
   )
")
RESIDUAL_TEST_SCHEMAS=$("${PSQL_SCRATCH[@]}" -Atc "
  select count(*)
    from pg_catalog.pg_namespace
   where nspname in ('rfi_hostile', 'rfi_runtime_integrity_sabotage')
")
if [[ "$RESIDUAL_TEST_ROWS" != "0" || "$RESIDUAL_TEST_SCHEMAS" != "0" ]]; then
  echo "runtime proof left scratch objects behind" >&2
  exit 1
fi

cleanup_scratch

SCRATCH_RESIDUE=$(
  "${PSQL_SOURCE[@]}" \
    -c "select count(*) from pg_catalog.pg_database where datname = '$SCRATCH_DB'"
)
SOURCE_SHA256_AFTER=$(database_fingerprint)

if [[ "$SCRATCH_RESIDUE" != "0" ]]; then
  echo "scratch database residue remains" >&2
  exit 1
fi
if [[ "$SOURCE_SHA256_BEFORE" != "$SOURCE_SHA256_AFTER" ]]; then
  echo "source database fingerprint changed" >&2
  exit 1
fi

echo "CANDIDATE_SHA256=$CANDIDATE_SHA256"
echo "SOURCE_SHA256_BEFORE=$SOURCE_SHA256_BEFORE"
echo "SOURCE_SHA256_AFTER=$SOURCE_SHA256_AFTER"
echo "MIXED_PRESTATE_REJECTION=PASS"
echo "UNKNOWN_PRESTATE_REJECTION=PASS"
printf '%s\n' "$MATRIX_RESULT_LINES"
echo "SCRATCH_RESIDUE=$SCRATCH_RESIDUE"
echo "runtime function integrity reconciliation: PASS"
