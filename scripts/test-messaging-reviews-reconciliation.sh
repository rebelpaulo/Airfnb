#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --socket SOCKET_DIR --port PORT --source-db DATABASE" >&2
}

socket_dir=""
port=""
source_db=""
while (($#)); do
  case "$1" in
    --socket)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      socket_dir=$2
      shift 2
      ;;
    --port)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      port=$2
      shift 2
      ;;
    --source-db)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      source_db=$2
      shift 2
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

[[ -n "$socket_dir" && -n "$port" && -n "$source_db" ]] || { usage; exit 64; }
[[ "$port" =~ ^[0-9]+$ ]] || { echo "Port must be numeric" >&2; exit 64; }
[[ "$source_db" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] || { echo "Unsafe source database name" >&2; exit 64; }

for tool in psql createdb dropdb pg_dump shasum awk sed; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 69; }
done

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
migration="$repo_root/supabase/migrations/20260820154054_messaging_reviews_reconciliation.sql"
runtime_test="$repo_root/tests/messaging-reviews-reconciliation-runtime.sql"
[[ -f "$migration" && -f "$runtime_test" ]] || { echo "Missing migration/runtime test" >&2; exit 66; }

connection=(-X -h "$socket_dir" -p "$port" -v ON_ERROR_STOP=1)
scratch="fb_tailor_mr_${$}_${RANDOM}"
marker="fb-tailor-messaging-reconciliation:${$}:${RANDOM}"
scratch_created=0

[[ "$scratch" =~ ^fb_tailor_mr_[0-9]+_[0-9]+$ ]] || { echo "Unsafe scratch name" >&2; exit 70; }
[[ "$scratch" != "$source_db" ]] || { echo "Scratch/source collision" >&2; exit 70; }

sha256_stream() {
  shasum -a 256 | awk '{print $1}'
}

source_schema_fingerprint() {
  pg_dump -h "$socket_dir" -p "$port" --schema-only --no-owner --no-privileges "$source_db" \
    | sed -E '/^\\(un)?restrict /d' \
    | sha256_stream
}

source_state_fingerprint() {
  psql "${connection[@]}" -d "$source_db" -At -F '|' <<'SQL' | sha256_stream
begin read only;
select current_database(), current_user;
select c.relname, c.relowner, c.relrowsecurity, c.relforcerowsecurity, coalesce(c.relacl::text, 'NULL')
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public'
   and c.relname in (
     'airfnb_conversations', 'airfnb_conversation_participants',
     'airfnb_messages', 'airfnb_reviews', 'airfnb_organizer_reviews'
   )
 order by c.relname;
select 'counts',
  (select count(*) from public.airfnb_conversations),
  (select count(*) from public.airfnb_conversation_participants),
  (select count(*) from public.airfnb_messages),
  (select count(*) from public.airfnb_reviews),
  (select count(*) from public.airfnb_organizer_reviews);
select md5(string_agg(
  t.id::text || ':' || coalesce(t.rating_avg::text, 'NULL') || ':' || coalesce(t.rating_count::text, 'NULL'),
  ',' order by t.id
)) from public.airfnb_trucks t;
select md5(p.prosrc), p.proacl::text, p.proconfig::text, p.proowner
  from pg_catalog.pg_proc p
 where p.oid = 'public.airfnb_accept_application(uuid)'::regprocedure;
commit;
SQL
}

scratch_reconciliation_fingerprint() {
  psql "${connection[@]}" -d "$scratch" -At -F '|' <<'SQL' | sha256_stream
select c.relname, c.relowner, c.relrowsecurity, c.relforcerowsecurity,
       coalesce(c.relacl::text, 'NULL')
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public'
   and c.relname in (
     'airfnb_conversations', 'airfnb_conversation_participants',
     'airfnb_messages', 'airfnb_reviews', 'airfnb_organizer_reviews'
   )
 order by c.relname;
select schemaname, tablename, policyname, roles::text, cmd,
       coalesce(qual, ''), coalesce(with_check, '')
  from pg_catalog.pg_policies
 where schemaname = 'public'
   and tablename in (
     'airfnb_conversations', 'airfnb_conversation_participants',
     'airfnb_messages', 'airfnb_reviews', 'airfnb_organizer_reviews'
   )
 order by tablename, policyname;
select p.oid::regprocedure::text, md5(p.prosrc), p.proowner, p.prosecdef,
       coalesce(p.proconfig::text, 'NULL'), coalesce(p.proacl::text, 'NULL')
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in (
     'airfnb_accept_application', 'airfnb_mark_conversation_read',
     'airfnb_prepare_truck_review', 'airfnb_prepare_organizer_review',
     'airfnb_recalc_truck_rating', 'airfnb_organizer_rating_recompute',
     'airfnb_reply_to_truck_review', 'airfnb_reply_to_organizer_review'
   )
 order by p.oid::regprocedure::text;
select c.relname, t.tgname, pg_catalog.pg_get_triggerdef(t.oid, true)
  from pg_catalog.pg_trigger t
  join pg_catalog.pg_class c on c.oid = t.tgrelid
 where t.tgrelid in ('public.airfnb_reviews'::regclass, 'public.airfnb_organizer_reviews'::regclass)
   and not t.tgisinternal
 order by c.relname, t.tgname;
SQL
}

validate_scratch() {
  local valid
  valid=$(psql "${connection[@]}" -d "$source_db" -At \
    -c "select count(*) from pg_catalog.pg_database d where d.datname = '$scratch' and d.datdba = (select oid from pg_catalog.pg_roles where rolname = current_user) and pg_catalog.shobj_description(d.oid, 'pg_database') = '$marker';")
  [[ "$valid" == "1" ]]
}

drop_validated_scratch() {
  ((scratch_created == 1)) || return 0
  if ! validate_scratch; then
    echo "Refusing to drop unvalidated scratch database: $scratch" >&2
    return 1
  fi
  dropdb -h "$socket_dir" -p "$port" "$scratch"
  scratch_created=0
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if ((scratch_created == 1)); then
    if ! drop_validated_scratch; then
      status=1
    fi
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

source_identity=$(psql "${connection[@]}" -d "$source_db" -At \
  -c "begin read only; select current_database() = '$source_db'; commit;")
[[ "$source_identity" == $'BEGIN\nt\nCOMMIT' ]] || { echo "Source database identity mismatch" >&2; exit 70; }

source_schema_before=$(source_schema_fingerprint)
source_state_before=$(source_state_fingerprint)
echo "source schema sha256 before: $source_schema_before"
echo "source state sha256 before:  $source_state_before"

existing=$(psql "${connection[@]}" -d "$source_db" -At \
  -c "select count(*) from pg_catalog.pg_database where datname = '$scratch';")
[[ "$existing" == "0" ]] || { echo "Scratch name already exists" >&2; exit 70; }

createdb -h "$socket_dir" -p "$port" -T "$source_db" "$scratch"
scratch_created=1
psql "${connection[@]}" -d "$scratch" \
  -c "comment on database \"$scratch\" is '$marker';" >/dev/null

scratch_identity=$(psql "${connection[@]}" -d "$scratch" -At \
  -c "select current_database() = '$scratch';")
[[ "$scratch_identity" == "t" ]] || { echo "Scratch database identity mismatch" >&2; exit 70; }
validate_scratch || { echo "Scratch ownership marker validation failed" >&2; exit 70; }

# Simulate heterogeneous pre-existing recovery grants. The migration may
# narrow API roles, but must preserve every explicit service_role table item.
psql "${connection[@]}" -d "$scratch" -c \
  "grant select, update on table public.airfnb_conversations to service_role;
   grant select, insert, update, delete on table public.airfnb_conversation_participants to service_role;
   grant select, insert, delete on table public.airfnb_messages to service_role;
   grant select, insert, update, delete on table public.airfnb_reviews to service_role;
   grant select, update, delete on table public.airfnb_organizer_reviews to service_role;" >/dev/null
service_acl_before=$(psql "${connection[@]}" -d "$scratch" -At -c \
  "select string_agg(c.relname || ':' || acl_item::text, ',' order by c.relname, acl_item::text)
     from pg_catalog.pg_class c
     join pg_catalog.pg_namespace n on n.oid = c.relnamespace
     cross join lateral unnest(c.relacl) acl_item
    where n.nspname = 'public'
      and c.relname in ('airfnb_conversations','airfnb_conversation_participants','airfnb_messages','airfnb_reviews','airfnb_organizer_reviews')
      and acl_item::text like 'service_role=%';")

seed_before=$(psql "${connection[@]}" -d "$scratch" -At -c "select md5(string_agg(id::text || ':' || coalesce(rating_avg::text,'NULL') || ':' || coalesce(rating_count::text,'NULL'), ',' order by id)) from public.airfnb_trucks;")
accept_before=$(psql "${connection[@]}" -d "$scratch" -At -c "select md5(prosrc) || '|' || coalesce(proacl::text,'NULL') from pg_catalog.pg_proc where oid = 'public.airfnb_accept_application(uuid)'::regprocedure;")

psql "${connection[@]}" -d "$scratch" -f "$migration"
psql "${connection[@]}" -d "$scratch" -f "$migration"

seed_after=$(psql "${connection[@]}" -d "$scratch" -At -c "select md5(string_agg(id::text || ':' || coalesce(rating_avg::text,'NULL') || ':' || coalesce(rating_count::text,'NULL'), ',' order by id)) from public.airfnb_trucks;")
accept_after=$(psql "${connection[@]}" -d "$scratch" -At -c "select md5(prosrc) || '|' || coalesce(proacl::text,'NULL') from pg_catalog.pg_proc where oid = 'public.airfnb_accept_application(uuid)'::regprocedure;")
service_acl_after=$(psql "${connection[@]}" -d "$scratch" -At -c \
  "select string_agg(c.relname || ':' || acl_item::text, ',' order by c.relname, acl_item::text)
     from pg_catalog.pg_class c
     join pg_catalog.pg_namespace n on n.oid = c.relnamespace
     cross join lateral unnest(c.relacl) acl_item
    where n.nspname = 'public'
      and c.relname in ('airfnb_conversations','airfnb_conversation_participants','airfnb_messages','airfnb_reviews','airfnb_organizer_reviews')
      and acl_item::text like 'service_role=%';")
[[ "$seed_before" == "$seed_after" ]] || { echo "Seeded truck ratings changed" >&2; exit 1; }
[[ "$accept_before" == "$accept_after" ]] || { echo "Accept-application body/ACL changed" >&2; exit 1; }
[[ "$service_acl_before" == "$service_acl_after" ]] || { echo "Explicit service_role table ACL changed" >&2; exit 1; }
echo "seed aggregate md5 preserved: $seed_after"
echo "accept body+acl preserved:    $accept_after"
echo "service_role table ACL:       $service_acl_after"

psql "${connection[@]}" -d "$scratch" -f "$runtime_test"

# Deliberately violate one exact precondition in the clone. The failed
# migration must leave that already-divergent clone byte-for-byte unchanged.
psql "${connection[@]}" -d "$scratch" -c "alter table public.airfnb_messages disable row level security;" >/dev/null
failure_before=$(scratch_reconciliation_fingerprint)
if psql "${connection[@]}" -d "$scratch" -f "$migration" >/dev/null 2>&1; then
  echo "Expected fail-closed migration failure did not occur" >&2
  exit 1
fi
failure_after=$(scratch_reconciliation_fingerprint)
[[ "$failure_before" == "$failure_after" ]] || { echo "Failed migration did not roll back cleanly" >&2; exit 1; }
echo "failure rollback sha256:      $failure_after"

drop_validated_scratch
residue=$(psql "${connection[@]}" -d "$source_db" -At \
  -c "select count(*) from pg_catalog.pg_database where datname = '$scratch';")
[[ "$residue" == "0" ]] || { echo "Scratch database residue remains" >&2; exit 1; }
echo "scratch cleanup: PASS ($scratch)"

source_schema_after=$(source_schema_fingerprint)
source_state_after=$(source_state_fingerprint)
echo "source schema sha256 after:  $source_schema_after"
echo "source state sha256 after:   $source_state_after"
[[ "$source_schema_before" == "$source_schema_after" ]] || { echo "Source schema fingerprint changed" >&2; exit 1; }
[[ "$source_state_before" == "$source_state_after" ]] || { echo "Source state fingerprint changed" >&2; exit 1; }

trap - EXIT INT TERM
echo "messaging-reviews reconciliation driver: PASS"
