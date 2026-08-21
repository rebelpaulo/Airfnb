#!/usr/bin/env bash

set -euo pipefail

readonly EXPECTED_REF_PATTERN='^[a-z]{20}$'
readonly SAFE_RESULT='AIRFNB_PREFLIGHT_V1:1111111'
readonly SUPABASE_COMMAND="${SUPABASE_BIN:-supabase}"

fail() {
  printf 'Supabase production preflight failed: %s\n' "$1" >&2
  exit 1
}

if [[ $# -ne 1 ]]; then
  fail 'provide exactly one 20-letter project ref'
fi

readonly PROJECT_REF="$1"
if [[ ! "$PROJECT_REF" =~ $EXPECTED_REF_PATTERN ]]; then
  fail 'project ref must contain exactly 20 lowercase letters'
fi

command -v "$SUPABASE_COMMAND" >/dev/null 2>&1 \
  || fail 'Supabase CLI executable was not found'
command -v node >/dev/null 2>&1 \
  || fail 'Node.js is required to validate CLI output'

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly MIGRATIONS_DIR="$REPOSITORY_ROOT/supabase/migrations"

[[ -d "$MIGRATIONS_DIR" ]] \
  || fail 'local migration directory was not found'

shopt -s nullglob
migration_files=("$MIGRATIONS_DIR"/*.sql)
shopt -u nullglob
(( ${#migration_files[@]} > 0 )) \
  || fail 'no local migrations were found'

migration_versions=()
expected_values=''
previous_version=''
for migration_file in "${migration_files[@]}"; do
  migration_name="$(basename "$migration_file")"
  if [[ ! "$migration_name" =~ ^([0-9]+)_.+\.sql$ ]]; then
    fail 'a local migration filename is malformed'
  fi

  migration_version="${BASH_REMATCH[1]}"
  if [[ "$migration_version" == "$previous_version" ]]; then
    fail 'duplicate local migration versions were found'
  fi
  previous_version="$migration_version"
  migration_versions+=("$migration_version")

  if [[ -n "$expected_values" ]]; then
    expected_values+=", "
  fi
  expected_values+="('$migration_version')"
done

cd "$REPOSITORY_ROOT"

# Project discovery is intentionally separate from the database calls. It
# proves that the explicit ref belongs to an accessible project before any
# project-scoped inspection is attempted.
if ! projects_output="$(
  CI=true SUPABASE_TELEMETRY_DISABLED=1 \
    "$SUPABASE_COMMAND" projects list --output-format json 2>/dev/null
)"; then
  fail 'could not list accessible Supabase projects'
fi

if ! printf '%s' "$projects_output" | node -e '
  const fs = require("node:fs");
  const expected = process.argv[1];
  let payload;
  try {
    payload = JSON.parse(fs.readFileSync(0, "utf8"));
  } catch {
    process.exit(1);
  }

  let projects;
  if (Array.isArray(payload)) {
    projects = payload;
  } else if (payload && typeof payload === "object") {
    for (const key of ["projects", "data", "result"]) {
      if (Array.isArray(payload[key])) {
        projects = payload[key];
        break;
      }
    }
  }

  if (!projects || projects.length === 0) process.exit(1);

  const refs = [];
  for (const project of projects) {
    if (!project || typeof project !== "object") process.exit(1);
    const ref = project.id ?? project.ref ?? project.project_ref;
    if (typeof ref !== "string" || !/^[a-z]{20}$/.test(ref)) process.exit(1);
    refs.push(ref);
  }

  process.exit(refs.filter((ref) => ref === expected).length === 1 ? 0 : 1);
' "$PROJECT_REF" 2>/dev/null; then
  fail 'explicit project ref did not match exactly one accessible project'
fi

# This documented read-only command gives operators the CLI-native view of
# local/remote history. Its output must show an exact one-to-one match; the SQL
# inspection below repeats the comparison directly against schema_migrations.
if ! migrations_output="$(
  CI=true SUPABASE_TELEMETRY_DISABLED=1 \
    "$SUPABASE_COMMAND" migration list \
      --linked \
      --project-ref "$PROJECT_REF" \
      --output-format json 2>/dev/null
)"; then
  fail 'could not inspect migration history'
fi

expected_versions_csv="$(IFS=,; printf '%s' "${migration_versions[*]}")"
if ! printf '%s' "$migrations_output" | node -e '
  const fs = require("node:fs");
  const expected = process.argv[1].split(",").filter(Boolean);
  let payload;
  try {
    payload = JSON.parse(fs.readFileSync(0, "utf8"));
  } catch {
    process.exit(1);
  }

  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    process.exit(1);
  }
  if (!Array.isArray(payload.migrations) || payload.migrations.length === 0) {
    process.exit(1);
  }

  const actual = [];
  for (const migration of payload.migrations) {
    if (!migration || typeof migration !== "object" || Array.isArray(migration)) {
      process.exit(1);
    }
    if (typeof migration.local !== "string" || !/^\d+$/.test(migration.local)) {
      process.exit(1);
    }
    if (typeof migration.remote !== "string" || !/^\d+$/.test(migration.remote)) {
      process.exit(1);
    }
    if (migration.local !== migration.remote) process.exit(1);
    actual.push(migration.local);
  }

  const unique = new Set(actual);
  if (unique.size !== actual.length || actual.length !== expected.length) {
    process.exit(1);
  }
  process.exit(expected.every((version) => unique.has(version)) ? 0 : 1);
' "$expected_versions_csv" 2>/dev/null; then
  fail 'local and remote migration histories diverged or output was malformed'
fi

# One SELECT-only statement returns seven booleans as a fixed marker. Raw query
# output is never echoed, so credentials, project metadata, and row data cannot
# leak through this guard.
IFS= read -r -d '' PREFLIGHT_SQL <<SQL || true
WITH
expected_migrations(version) AS (
  VALUES $expected_values
),
identity_check(ok) AS (
  SELECT
    NOT EXISTS (
      SELECT 1
      FROM auth.users
      WHERE id = '11111111-1111-1111-1111-111111111111'::uuid
         OR lower(email) = 'seed@airfnb.local'
    )
    AND to_regprocedure('public.airfnb_guard_profile_role()') IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS trigger_row
      JOIN pg_catalog.pg_class AS relation
        ON relation.oid = trigger_row.tgrelid
      JOIN pg_catalog.pg_namespace AS namespace
        ON namespace.oid = relation.relnamespace
      WHERE namespace.nspname = 'public'
        AND relation.relname = 'airfnb_profiles'
        AND trigger_row.tgname = 'airfnb_profiles_guard_role'
        AND trigger_row.tgenabled <> 'D'
        AND trigger_row.tgfoid = to_regprocedure('public.airfnb_guard_profile_role()')
    )
    AND NOT coalesce(has_function_privilege(
      'anon',
      to_regprocedure('public.airfnb_guard_profile_role()'),
      'EXECUTE'
    ), false)
    AND NOT coalesce(has_function_privilege(
      'authenticated',
      to_regprocedure('public.airfnb_guard_profile_role()'),
      'EXECUTE'
    ), false)
),
pii_check(ok) AS (
  SELECT
    NOT has_column_privilege('anon', 'public.airfnb_event_requests', 'contact_name', 'SELECT')
    AND NOT has_column_privilege('anon', 'public.airfnb_event_requests', 'contact_email', 'SELECT')
    AND NOT has_column_privilege('anon', 'public.airfnb_event_requests', 'contact_phone', 'SELECT')
    AND NOT has_column_privilege('anon', 'public.airfnb_event_requests', 'address_line', 'SELECT')
    AND NOT has_column_privilege('anon', 'public.airfnb_event_requests', 'address_id', 'SELECT')
    AND NOT has_column_privilege('authenticated', 'public.airfnb_event_requests', 'contact_name', 'SELECT')
    AND NOT has_column_privilege('authenticated', 'public.airfnb_event_requests', 'contact_email', 'SELECT')
    AND NOT has_column_privilege('authenticated', 'public.airfnb_event_requests', 'contact_phone', 'SELECT')
    AND NOT has_column_privilege('authenticated', 'public.airfnb_event_requests', 'address_line', 'SELECT')
    AND NOT has_column_privilege('authenticated', 'public.airfnb_event_requests', 'address_id', 'SELECT')
    AND has_column_privilege('service_role', 'public.airfnb_event_requests', 'contact_name', 'SELECT')
    AND has_column_privilege('service_role', 'public.airfnb_event_requests', 'contact_email', 'SELECT')
    AND has_column_privilege('service_role', 'public.airfnb_event_requests', 'contact_phone', 'SELECT')
    AND has_column_privilege('service_role', 'public.airfnb_event_requests', 'address_line', 'SELECT')
    AND has_column_privilege('service_role', 'public.airfnb_event_requests', 'address_id', 'SELECT')
),
rate_limit_check(ok) AS (
  SELECT
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_class AS relation
      JOIN pg_catalog.pg_namespace AS namespace
        ON namespace.oid = relation.relnamespace
      WHERE namespace.nspname = 'public'
        AND relation.relname = 'airfnb_rate_limits'
        AND relation.relkind IN ('r', 'p')
        AND relation.relrowsecurity
    )
    AND NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_policies
      WHERE schemaname = 'public'
        AND tablename = 'airfnb_rate_limits'
    )
    AND NOT has_table_privilege('anon', 'public.airfnb_rate_limits', 'INSERT')
    AND NOT has_table_privilege('anon', 'public.airfnb_rate_limits', 'UPDATE')
    AND NOT has_table_privilege('anon', 'public.airfnb_rate_limits', 'DELETE')
    AND NOT has_table_privilege('authenticated', 'public.airfnb_rate_limits', 'INSERT')
    AND NOT has_table_privilege('authenticated', 'public.airfnb_rate_limits', 'UPDATE')
    AND NOT has_table_privilege('authenticated', 'public.airfnb_rate_limits', 'DELETE')
    AND has_table_privilege('service_role', 'public.airfnb_rate_limits', 'SELECT')
    AND has_table_privilege('service_role', 'public.airfnb_rate_limits', 'INSERT')
    AND has_table_privilege('service_role', 'public.airfnb_rate_limits', 'UPDATE')
    AND has_table_privilege('service_role', 'public.airfnb_rate_limits', 'DELETE')
    AND to_regprocedure(
      'public.airfnb_check_rate_limit(text,text,integer,integer)'
    ) IS NOT NULL
    AND coalesce((
      SELECT procedure.prosecdef
      FROM pg_catalog.pg_proc AS procedure
      WHERE procedure.oid = to_regprocedure(
        'public.airfnb_check_rate_limit(text,text,integer,integer)'
      )
    ), false)
    AND NOT coalesce(has_function_privilege(
      'anon',
      to_regprocedure('public.airfnb_check_rate_limit(text,text,integer,integer)'),
      'EXECUTE'
    ), false)
    AND NOT coalesce(has_function_privilege(
      'authenticated',
      to_regprocedure('public.airfnb_check_rate_limit(text,text,integer,integer)'),
      'EXECUTE'
    ), false)
    AND coalesce(has_function_privilege(
      'service_role',
      to_regprocedure('public.airfnb_check_rate_limit(text,text,integer,integer)'),
      'EXECUTE'
    ), false)
),
service_type_check(ok) AS (
  SELECT
    EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute AS attribute
      JOIN pg_catalog.pg_class AS relation
        ON relation.oid = attribute.attrelid
      JOIN pg_catalog.pg_namespace AS namespace
        ON namespace.oid = relation.relnamespace
      JOIN pg_catalog.pg_type AS data_type
        ON data_type.oid = attribute.atttypid
      WHERE namespace.nspname = 'public'
        AND relation.relname = 'airfnb_trucks'
        AND attribute.attname = 'service_type'
        AND attribute.attnum > 0
        AND NOT attribute.attisdropped
        AND attribute.attnotnull
        AND data_type.typname = 'airfnb_service_type'
        AND data_type.typtype = 'e'
    )
    AND ARRAY[
      'bar',
      'catering',
      'food_truck'
    ]::text[] = ARRAY(
      SELECT enumlabel::text
      FROM pg_catalog.pg_enum
      WHERE enumtypid = to_regtype('public.airfnb_service_type')
      ORDER BY enumlabel
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.airfnb_trucks
      WHERE service_type IS NULL
    )
),
stripe_check(ok) AS (
  SELECT
    to_regprocedure(
      'public.airfnb_reconcile_stripe_event(text,text,timestamp with time zone,uuid,uuid,uuid,text,bigint,text,text,bigint)'
    ) IS NOT NULL
    AND coalesce((
      SELECT procedure.prosecdef
      FROM pg_catalog.pg_proc AS procedure
      WHERE procedure.oid = to_regprocedure(
        'public.airfnb_reconcile_stripe_event(text,text,timestamp with time zone,uuid,uuid,uuid,text,bigint,text,text,bigint)'
      )
    ), false)
    AND NOT coalesce(has_function_privilege(
      'anon',
      to_regprocedure(
        'public.airfnb_reconcile_stripe_event(text,text,timestamp with time zone,uuid,uuid,uuid,text,bigint,text,text,bigint)'
      ),
      'EXECUTE'
    ), false)
    AND NOT coalesce(has_function_privilege(
      'authenticated',
      to_regprocedure(
        'public.airfnb_reconcile_stripe_event(text,text,timestamp with time zone,uuid,uuid,uuid,text,bigint,text,text,bigint)'
      ),
      'EXECUTE'
    ), false)
    AND coalesce(has_function_privilege(
      'service_role',
      to_regprocedure(
        'public.airfnb_reconcile_stripe_event(text,text,timestamp with time zone,uuid,uuid,uuid,text,bigint,text,text,bigint)'
      ),
      'EXECUTE'
    ), false)
    AND EXISTS (
      SELECT 1
      FROM pg_catalog.pg_class AS relation
      JOIN pg_catalog.pg_namespace AS namespace
        ON namespace.oid = relation.relnamespace
      WHERE namespace.nspname = 'public'
        AND relation.relname = 'airfnb_stripe_events'
        AND relation.relrowsecurity
        AND relation.relforcerowsecurity
    )
),
privacy_rpc_check(ok) AS (
  SELECT
    to_regprocedure('public.airfnb_private_event_requests(uuid)') IS NOT NULL
    AND coalesce((
      SELECT procedure.prosecdef
      FROM pg_catalog.pg_proc AS procedure
      WHERE procedure.oid = to_regprocedure(
        'public.airfnb_private_event_requests(uuid)'
      )
    ), false)
    AND NOT coalesce(has_function_privilege(
      'anon',
      to_regprocedure('public.airfnb_private_event_requests(uuid)'),
      'EXECUTE'
    ), false)
    AND coalesce(has_function_privilege(
      'authenticated',
      to_regprocedure('public.airfnb_private_event_requests(uuid)'),
      'EXECUTE'
    ), false)
),
migration_check(ok) AS (
  SELECT NOT EXISTS (
    (
      SELECT version FROM expected_migrations
      EXCEPT
      SELECT version FROM supabase_migrations.schema_migrations
    )
    UNION ALL
    (
      SELECT version FROM supabase_migrations.schema_migrations
      EXCEPT
      SELECT version FROM expected_migrations
    )
  )
)
SELECT
  'AIRFNB_PREFLIGHT_V1:'
  || CASE WHEN identity_check.ok IS TRUE THEN '1' ELSE '0' END
  || CASE WHEN pii_check.ok IS TRUE THEN '1' ELSE '0' END
  || CASE WHEN rate_limit_check.ok IS TRUE THEN '1' ELSE '0' END
  || CASE WHEN service_type_check.ok IS TRUE THEN '1' ELSE '0' END
  || CASE WHEN stripe_check.ok IS TRUE THEN '1' ELSE '0' END
  || CASE WHEN privacy_rpc_check.ok IS TRUE THEN '1' ELSE '0' END
  || CASE WHEN migration_check.ok IS TRUE THEN '1' ELSE '0' END
  AS preflight_result
FROM identity_check
CROSS JOIN pii_check
CROSS JOIN rate_limit_check
CROSS JOIN service_type_check
CROSS JOIN stripe_check
CROSS JOIN privacy_rpc_check
CROSS JOIN migration_check
SQL

if ! query_output="$(
  CI=true SUPABASE_TELEMETRY_DISABLED=1 \
    "$SUPABASE_COMMAND" db query \
      --linked \
      --project-ref "$PROJECT_REF" \
      --output csv \
      "$PREFLIGHT_SQL" 2>/dev/null
)"; then
  fail 'could not run read-only database inspection'
fi

set +e
failed_checks="$(printf '%s' "$query_output" | node -e '
  const fs = require("node:fs");
  const labels = [
    "identity",
    "PII privacy",
    "rate limits",
    "service type",
    "Stripe reconciliation",
    "privacy RPC",
    "migration history",
  ];
  const input = fs.readFileSync(0, "utf8");
  const matches = [];

  const collect = (value) => {
    if (typeof value === "string") {
      if (/^AIRFNB_PREFLIGHT_V1:[01]{7}$/.test(value)) matches.push(value);
      return;
    }
    if (Array.isArray(value)) {
      value.forEach(collect);
      return;
    }
    if (value && typeof value === "object") {
      Object.values(value).forEach(collect);
    }
  };

  const trimmed = input.trim();
  if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
    try {
      collect(JSON.parse(trimmed));
    } catch {
      process.exit(2);
    }
  } else {
    for (const rawLine of input.split(/\r?\n/)) {
      let line = rawLine.trim();
      if (line.startsWith("|") && line.endsWith("|")) {
        line = line.slice(1, -1).trim();
      }
      if (line.startsWith("\"") && line.endsWith("\"")) {
        line = line.slice(1, -1).replace(/\"\"/g, "\"");
      }
      if (/^AIRFNB_PREFLIGHT_V1:[01]{7}$/.test(line)) matches.push(line);
    }
  }

  if (matches.length !== 1) process.exit(2);
  const bits = matches[0].slice("AIRFNB_PREFLIGHT_V1:".length);
  if (`AIRFNB_PREFLIGHT_V1:${bits}` === process.argv[1]) process.exit(0);

  process.stdout.write(labels.filter((_, index) => bits[index] === "0").join(", "));
  process.exit(1);
' "$SAFE_RESULT" 2>/dev/null)"
parse_status=$?
set -e

case "$parse_status" in
  0)
    printf 'Supabase production preflight passed.\n'
    ;;
  1)
    fail "unsafe production state: ${failed_checks:-unknown check}"
    ;;
  *)
    fail 'database inspection output was malformed'
    ;;
esac
