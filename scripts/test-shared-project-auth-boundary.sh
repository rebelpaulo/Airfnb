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
[[ ! "$source_database" =~ ^fb_tailor_shared_auth_ ]] || usage
[[ -S "$socket_directory/.s.PGSQL.$postgres_port" ]] || { printf 'local socket unavailable\n' >&2; exit 66; }

for command_name in psql pg_dump createdb dropdb shasum awk sed mktemp grep; do
  command -v "$command_name" >/dev/null || { printf 'missing local command: %s\n' "$command_name" >&2; exit 69; }
done

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
migration_file="$repository_root/supabase/migrations/20260821121634_shared_project_auth_boundary.sql"
runtime_file="$repository_root/tests/shared-project-auth-boundary-runtime.sql"
source_test_file="$repository_root/tests/shared-project-auth-boundary-source.test.mjs"
types_file="$repository_root/types/database.ts"
driver_file="$repository_root/scripts/test-shared-project-auth-boundary.sh"
identity_file="$repository_root/supabase/migrations/20260819094823_airfnb_identity_reconciliation.sql"
identity_runtime_file="$repository_root/tests/identity-reconciliation-runtime.sql"
supplier_file="$repository_root/supabase/migrations/20260820230518_supplier_acl_caller_reconciliation.sql"
predecessor_files=(
  "$repository_root/supabase/migrations/20260820152018_airfnb_runtime_function_integrity_reconciliation.sql"
  "$repository_root/supabase/migrations/20260820153725_public_event_request_privacy_reconciliation.sql"
  "$repository_root/supabase/migrations/20260820154054_messaging_reviews_reconciliation.sql"
  "$repository_root/supabase/migrations/20260820154100_storage_abuse_reconciliation.sql"
  "$repository_root/supabase/migrations/20260820154104_catalog_service_types_reconciliation.sql"
  "$repository_root/supabase/migrations/20260820154358_marketplace_workflow_reconciliation.sql"
  "$repository_root/supabase/migrations/20260820155322_stripe_canonical_reconciliation.sql"
  "$supplier_file"
)
artifacts=("$migration_file" "$runtime_file" "$source_test_file" "$types_file" "$driver_file" "$identity_file" "$identity_runtime_file" "${predecessor_files[@]}")

sha256_file() { shasum -a 256 "$1" | awk '{print $1}'; }
sha256_stream() { shasum -a 256 | awk '{print $1}'; }
artifact_manifest() { local path; for path in "${artifacts[@]}"; do printf '%s  %s\n' "$(sha256_file "$path")" "$path"; done; }

expected_predecessor_hashes=(
  f1400bd3e4ac3d1d4e2c67b6cd33a0b7a551a26bfc018633c31f9c494096b24f
  bc859122de962efee0a5d11d5e56be9ba7f42bc54ce097ead672241686f89fc2
  26695c1b5567a182777f15fa81249d234857fd3e608abcc6056dbdb39a6c55b8
  19b02bd08d14be47b5f2ef086700bc8248be63f5ecac9b1501e6024b436d164b
  90dbaf281ea0c9209373fe16964e1aaaa34152f0272ef067fdee80f831fdc60c
  07e6692f05aad35a9256ab514b73a446ee49c3d7c794b909c62240256ec1147d
  5c244501a3f2e7b9d5aef6fa9d40b48a101b3efe0221401e9c6207d03f927591
  2fdd44ad5d0da55119a867b0aafc124cd3ffa5b963904656363cccd26c366e92
)
[[ "$(sha256_file "$identity_file")" == 76b7659106d4598af471c84341e961aed2dcae88746177e1be19b7c7a60c3319
   && "$(sha256_file "$identity_runtime_file")" == ddd03863f2efe2e77fde26ead30773e1785fdff3f3c11206be1a1a4b0f03c463 ]] || {
  printf 'official identity predecessor drifted\n' >&2; exit 65;
}
for predecessor_index in "${!predecessor_files[@]}"; do
  [[ "$(sha256_file "${predecessor_files[$predecessor_index]}")" == "${expected_predecessor_hashes[$predecessor_index]}" ]] || {
  printf 'official supplier predecessor drifted\n' >&2; exit 65;
  }
done

psql_source=(psql -X --no-psqlrc --host="$socket_directory" --port="$postgres_port" --dbname="$source_database" --set=ON_ERROR_STOP=1 --quiet)
[[ "$(PGOPTIONS='-c default_transaction_read_only=on' "${psql_source[@]}" --tuples-only --no-align --command='select current_database();')" == "$source_database" ]] || exit 65

source_fingerprint() {
  PGOPTIONS='-c default_transaction_read_only=on' pg_dump --host="$socket_directory" --port="$postgres_port" --dbname="$source_database" \
    --format=plain --schema=auth --schema=public --schema=storage --no-owner \
    | sed '/^\\restrict /d; /^\\unrestrict /d' | sha256_stream
}

source_fingerprint_before="$(source_fingerprint)"
manifest_before="$(artifact_manifest)"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/fb-tailor-shared-auth.XXXXXX")"
scratch_databases=()

is_scratch() {
  [[ "$1" =~ ^fb_tailor_shared_auth_[0-9]+_[0-9]+_(tamper|good)$ \
     || "$1" =~ ^fb_tailor_identity_runtime_[0-9]+_[0-9]+$ ]]
}
database_exists() {
  PGOPTIONS='-c default_transaction_read_only=on' "${psql_source[@]}" --tuples-only --no-align \
    --command="select count(*) from pg_catalog.pg_database where datname='$1';"
}
cleanup() {
  local status=$? database_name
  trap - EXIT INT TERM
  for database_name in "${scratch_databases[@]}"; do
    if is_scratch "$database_name" && [[ "$(database_exists "$database_name")" == 1 ]]; then
      dropdb --host="$socket_directory" --port="$postgres_port" --maintenance-db=template1 -- "$database_name" || status=1
    fi
  done
  find "$temporary_directory" -type f -maxdepth 1 -delete 2>/dev/null || status=1
  rmdir "$temporary_directory" 2>/dev/null || status=1
  exit "$status"
}
trap cleanup EXIT INT TERM

create_scratch() {
  local suffix="$1"
  local identity_database="fb_tailor_identity_runtime_${$}_${RANDOM}"
  local identity_failure="$temporary_directory/identity-${suffix}.log"
  local -a psql_identity
  scratch_database="fb_tailor_shared_auth_${$}_${RANDOM}_${suffix}"
  is_scratch "$identity_database" && is_scratch "$scratch_database" || exit 65
  scratch_databases+=("$identity_database" "$scratch_database")
  createdb --host="$socket_directory" --port="$postgres_port" --maintenance-db=template1 --template="$source_database" -- "$identity_database"
  psql_identity=(psql -X --no-psqlrc --host="$socket_directory" --port="$postgres_port" --dbname="$identity_database" --set=ON_ERROR_STOP=1 --quiet)
  "${psql_identity[@]}" --set=identity_runtime_database="$identity_database" --set=identity_runtime_phase=setup_drift --file="$identity_runtime_file" >/dev/null
  if "${psql_identity[@]}" --file="$identity_file" >"$identity_failure" 2>&1; then
    printf 'identity 11-of-12 drift unexpectedly accepted\n' >&2; exit 1
  fi
  grep -Fq 'identity reconciliation refused: expected exactly the 12 observed catalogue services' "$identity_failure" || {
    sed -n '1,80p' "$identity_failure" >&2; exit 1;
  }
  "${psql_identity[@]}" --set=identity_runtime_database="$identity_database" --set=identity_runtime_phase=assert_failed_atomicity_and_prepare_good --file="$identity_runtime_file" >/dev/null
  "${psql_identity[@]}" --file="$identity_file" >/dev/null
  "${psql_identity[@]}" --set=identity_runtime_database="$identity_database" --set=identity_runtime_phase=assert_good --file="$identity_runtime_file" >/dev/null
  "${psql_identity[@]}" <<'SQL' >/dev/null
delete from public.airfnb_trucks where slug = 'identity-runtime-unrelated-service';
delete from public.airfnb_blog_posts where slug = 'identity-runtime-unrelated-article';
delete from public.airfnb_blog_authors where id = '99999999-9999-9999-9999-999999999999';
delete from auth.users where id in (
  '22222222-2222-2222-2222-222222222222','33333333-3333-3333-3333-333333333333',
  '44444444-4444-4444-4444-444444444444','55555555-5555-5555-5555-555555555555',
  '66666666-6666-6666-6666-666666666666','77777777-7777-7777-7777-777777777777',
  '88888888-8888-8888-8888-888888888888','99999999-9999-9999-9999-999999999999'
);
drop schema identity_runtime cascade;
SQL
  "${psql_source[@]}" --command="alter database \"$identity_database\" rename to \"$scratch_database\"" >/dev/null
  psql_scratch=(psql -X --no-psqlrc --host="$socket_directory" --port="$postgres_port" --dbname="$scratch_database" --set=ON_ERROR_STOP=1 --quiet)
}

apply_predecessors() {
  local predecessor_file
  for predecessor_file in "${predecessor_files[@]}"; do
    "${psql_scratch[@]}" --file="$predecessor_file" >/dev/null
  done
  [[ "$("${psql_scratch[@]}" --tuples-only --no-align --command="select pg_catalog.md5(prosrc) from pg_catalog.pg_proc where oid='public.airfnb_guard_profile_role()'::regprocedure")" == ebd2f85a1bacb5eceaca6a1c3cec5731 ]] || {
    printf 'full-chain profile guard predecessor mismatch\n' >&2; exit 65;
  }
  [[ "$("${psql_scratch[@]}" --tuples-only --no-align --command="select pg_catalog.md5(prosrc) from pg_catalog.pg_proc where oid='public.airfnb_apply_referral(text)'::regprocedure")" == 8c282e85f135c61bebfa770aba12dead ]] || {
    printf 'full-chain referral predecessor mismatch\n' >&2; exit 65;
  }
  [[ "$("${psql_scratch[@]}" --tuples-only --no-align --command="select pg_catalog.md5(prosrc) from pg_catalog.pg_proc where oid='public.airfnb_self_delete()'::regprocedure")" == 3263d4bfe0026701f234172dfc4d66a3 ]] || {
    printf 'full-chain self-delete predecessor mismatch\n' >&2; exit 65;
  }
}

candidate_fingerprint() {
  "${psql_scratch[@]}" --tuples-only --no-align --field-separator='|' <<'SQL' | sha256_stream
select 'role',attribute.attnotnull::text,coalesce(pg_catalog.pg_get_expr(default_value.adbin,default_value.adrelid),'')
  from pg_catalog.pg_attribute as attribute
  left join pg_catalog.pg_attrdef as default_value on default_value.adrelid=attribute.attrelid and default_value.adnum=attribute.attnum
 where attribute.attrelid='public.airfnb_profiles'::regclass and attribute.attname='role'
union all
select 'profile-column',attribute.attname,coalesce(attribute.attacl::text,'')
  from pg_catalog.pg_attribute as attribute
 where attribute.attrelid='public.airfnb_profiles'::regclass
   and attribute.attnum>0 and not attribute.attisdropped
union all
select 'tombstone',coalesce(relation.oid::regclass::text,'absent'),
       coalesce(relation.relrowsecurity::text,'')||':'||coalesce(relation.relacl::text,'')
  from (values (pg_catalog.to_regclass('public.airfnb_membership_tombstones'))) candidate(oid)
  left join pg_catalog.pg_class as relation on relation.oid=candidate.oid
union all
select 'function',procedure.oid::regprocedure::text,procedure.proowner::text||':'||procedure.prosecdef::text||':'||procedure.provolatile::text||':'||coalesce(procedure.proconfig::text,'')||':'||coalesce(procedure.proacl::text,'')||':'||pg_catalog.md5(procedure.prosrc)
  from pg_catalog.pg_proc as procedure
 where procedure.pronamespace='public'::regnamespace
   and procedure.proname in ('airfnb_guard_profile_role','airfnb_ensure_profile','airfnb_claim_role','airfnb_apply_referral','airfnb_self_delete','airfnb_handle_new_user')
union all
select 'trigger',trigger_row.tgname,trigger_row.tgfoid::regprocedure::text
  from pg_catalog.pg_trigger as trigger_row
 where not trigger_row.tgisinternal and trigger_row.tgname in ('airfnb_profiles_guard_role','airfnb_trg_auth_new_user')
order by 1,2,3;
SQL
}

create_scratch tamper
apply_predecessors
"${psql_scratch[@]}" <<'SQL' >/dev/null
create or replace function public.airfnb_handle_new_user() returns trigger
language plpgsql security definer set search_path=public as $$ begin return new; end $$;
SQL
tamper_before="$(candidate_fingerprint)"
if "${psql_scratch[@]}" --file="$migration_file" >"$temporary_directory/tamper.log" 2>&1; then
  printf 'tampered predecessor unexpectedly accepted\n' >&2; exit 1
fi
grep -Fq 'shared auth boundary refused: predecessor or final state drifted' "$temporary_directory/tamper.log" || {
  sed -n '1,80p' "$temporary_directory/tamper.log" >&2; exit 1;
}
[[ "$(candidate_fingerprint)" == "$tamper_before" ]] || { printf 'rollback sabotage was not atomic\n' >&2; exit 1; }

create_scratch good
apply_predecessors
"${psql_scratch[@]}" --file="$migration_file" >/dev/null
"${psql_scratch[@]}" --file="$runtime_file" >/dev/null
candidate_before_reapply="$(candidate_fingerprint)"
"${psql_scratch[@]}" --file="$migration_file" >/dev/null
[[ "$(candidate_fingerprint)" == "$candidate_before_reapply" ]] || { printf 'reapply changed final state\n' >&2; exit 1; }
"${psql_scratch[@]}" --file="$runtime_file" >/dev/null

[[ "$(source_fingerprint)" == "$source_fingerprint_before" ]] || { printf 'source_fingerprint changed\n' >&2; exit 1; }
[[ "$(artifact_manifest)" == "$manifest_before" ]] || { printf 'source artifacts changed during driver\n' >&2; exit 1; }

printf 'shared_auth_boundary: apply/reapply, tamper rollback, adversarial matrix and source_fingerprint PASS\n'
printf 'zero residue will be enforced by the EXIT cleanup trap\n'
