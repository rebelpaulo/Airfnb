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
  printf 'refusing unsafe socket directory: %s\n' "$socket_directory" >&2
  exit 64
}
[[ "$postgres_port" =~ ^[0-9]+$ ]] && ((postgres_port >= 1 && postgres_port <= 65535)) || {
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
  printf 'refusing catalog scratch database as source\n' >&2
  exit 64
}
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
migration_file="$repository_root/supabase/migrations/20260820154104_catalog_service_types_reconciliation.sql"
runtime_file="$repository_root/tests/catalog-service-types-reconciliation-runtime.sql"
runtime_integrity_file="$repository_root/supabase/migrations/20260820152018_airfnb_runtime_function_integrity_reconciliation.sql"
privacy_file="$repository_root/supabase/migrations/20260820153725_public_event_request_privacy_reconciliation.sql"
messaging_file="$repository_root/supabase/migrations/20260820154054_messaging_reviews_reconciliation.sql"
storage_file="$repository_root/supabase/migrations/20260820154100_storage_abuse_reconciliation.sql"

for required_file in \
  "$migration_file" "$runtime_file" "$runtime_integrity_file" \
  "$privacy_file" "$messaging_file" "$storage_file"
do
  [[ -f "$required_file" ]] || {
    printf 'catalog reconciliation artifact is missing: %s\n' "$required_file" >&2
    exit 66
  }
done

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

sha256_stream() {
  shasum -a 256 | awk '{print $1}'
}

psql_source=(
  psql -X --no-psqlrc --host="$socket_directory" --port="$postgres_port"
  --dbname="$source_database" --set=ON_ERROR_STOP=1 --tuples-only --no-align --quiet
)

actual_source_database="$(PGOPTIONS='-c default_transaction_read_only=on' "${psql_source[@]}" --command='select current_database();')"
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
  [[ "$database_name" =~ ^fb_tailor_catalog_[0-9]+_[0-9]+_(legacy|old)$ ]] || return 1
  PGOPTIONS='-c default_transaction_read_only=on' "${psql_source[@]}" \
    --command="select pg_catalog.count(*) from pg_catalog.pg_database where datname = '$database_name';"
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
  printf 'source database does not match verified old-candidate fixture: %s\n' "$source_contract" >&2
  exit 65
}

source_sha256_before="$(source_fingerprint)"
migration_sha256="$(sha256_file "$migration_file")"
runtime_sha256="$(sha256_file "$runtime_file")"
runtime_integrity_sha256="$(sha256_file "$runtime_integrity_file")"
privacy_sha256="$(sha256_file "$privacy_file")"
messaging_sha256="$(sha256_file "$messaging_file")"
storage_sha256="$(sha256_file "$storage_file")"
[[ "$runtime_integrity_sha256" == 'f1400bd3e4ac3d1d4e2c67b6cd33a0b7a551a26bfc018633c31f9c494096b24f' \
   && "$privacy_sha256" == 'bc859122de962efee0a5d11d5e56be9ba7f42bc54ce097ead672241686f89fc2' \
   && "$messaging_sha256" == '26695c1b5567a182777f15fa81249d234857fd3e608abcc6056dbdb39a6c55b8' \
   && "$storage_sha256" == '19b02bd08d14be47b5f2ef086700bc8248be63f5ecac9b1501e6024b436d164b' ]] || {
  printf 'official predecessor chain hash mismatch\n' >&2
  exit 65
}
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/fb-tailor-catalog.XXXXXX")"
failure_log="$temporary_directory/intentional-failure.log"
denial_log="$temporary_directory/denial.log"
scratch_database=""
scratch_created=0

is_scratch_database() {
  [[ "$1" =~ ^fb_tailor_catalog_[0-9]+_[0-9]+_(legacy|old)$ ]]
}

cleanup_scratch() {
  if ((scratch_created == 1)); then
    if ! is_scratch_database "$scratch_database" || [[ "$scratch_database" == "$source_database" ]]; then
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
  rm -f -- "$failure_log" "$denial_log"
  rmdir "$temporary_directory" 2>/dev/null || true
  exit "$exit_status"
}
trap cleanup EXIT INT TERM

run_runtime_phase() {
  local phase="$1"
  "${psql_scratch[@]}" \
    --set=catalog_runtime_phase="$phase" \
    --set=catalog_runtime_database="$scratch_database" \
    --file="$runtime_file" >/dev/null
}

target_state_sha256() {
  "${psql_scratch[@]}" --tuples-only --no-align --field-separator='|' <<'SQL' | sha256_stream
select 'relation', relation.oid::text, relation.relowner::text,
       relation.relrowsecurity::text, coalesce(relation.reloptions::text,''),
       coalesce(relation.relacl::text,'')
  from pg_catalog.pg_class as relation
 where relation.oid in (
   'public.airfnb_trucks'::regclass,
   'public.airfnb_categories'::regclass,
   'public.airfnb_truck_images'::regclass,
   'public.airfnb_truck_categories'::regclass,
   'public.airfnb_v_truck_card'::regclass
 )
union all
select 'column', attribute.attrelid::text, attribute.attnum::text,
       attribute.attname, pg_catalog.format_type(attribute.atttypid, attribute.atttypmod),
       pg_catalog.concat_ws(':', attribute.attnotnull::text,
         coalesce(pg_catalog.pg_get_expr(default_value.adbin, default_value.adrelid),''),
         coalesce(attribute.attacl::text,''))
  from pg_catalog.pg_attribute as attribute
  left join pg_catalog.pg_attrdef as default_value
    on default_value.adrelid = attribute.attrelid
   and default_value.adnum = attribute.attnum
 where attribute.attrelid in (
   'public.airfnb_trucks'::regclass,
   'public.airfnb_categories'::regclass,
   'public.airfnb_truck_images'::regclass,
   'public.airfnb_truck_categories'::regclass,
   'public.airfnb_v_truck_card'::regclass
 ) and attribute.attnum > 0 and not attribute.attisdropped
union all
select 'policy', policy.polrelid::text, policy.polname, policy.polcmd::text,
       policy.polroles::text,
       pg_catalog.concat_ws(':', policy.polpermissive::text,
         coalesce(pg_catalog.pg_get_expr(policy.polqual, policy.polrelid),''),
         coalesce(pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid),''))
  from pg_catalog.pg_policy as policy
 where policy.polrelid in (
   'public.airfnb_trucks'::regclass,
   'public.airfnb_categories'::regclass,
   'public.airfnb_truck_images'::regclass,
   'public.airfnb_menu_items'::regclass,
   'public.airfnb_truck_categories'::regclass
 )
union all
select 'function', procedure.oid::text, procedure.proname,
       pg_catalog.md5(procedure.prosrc), procedure.proconfig::text,
       pg_catalog.concat_ws(':', procedure.proowner::text, procedure.prosecdef::text,
         procedure.provolatile::text, coalesce(procedure.proacl::text,''))
  from pg_catalog.pg_proc as procedure
  join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
 where namespace.nspname = 'public'
   and procedure.proname in (
     'airfnb_is_admin','airfnb_admin_approve_truck','airfnb_admin_reject_truck',
     'airfnb_recalc_truck_rating','airfnb_touch_updated_at',
     'airfnb_guard_truck_moderation','airfnb_can_manage_truck',
     'airfnb_can_read_truck_child'
   )
union all
select 'trigger', trigger.tgrelid::text, trigger.tgname,
       trigger.tgtype::text, trigger.tgenabled::text, trigger.tgfoid::text
  from pg_catalog.pg_trigger as trigger
 where trigger.tgrelid = 'public.airfnb_trucks'::regclass and not trigger.tgisinternal
union all
select 'index', schemaname, tablename, indexname, indexdef, ''
  from pg_catalog.pg_indexes
 where schemaname = 'public' and tablename = 'airfnb_trucks'
union all
select 'viewdef', '0', '0',
       pg_catalog.md5(pg_catalog.pg_get_viewdef('public.airfnb_v_truck_card'::regclass, true)), '', ''
union all
select 'aggregate', '0', '0',
       pg_catalog.md5(pg_catalog.string_agg(
         pg_catalog.format('%s:%s:%s', id, rating_avg, rating_count), ',' order by id
       )), '', ''
  from public.airfnb_trucks
order by 1,2,3,4;
SQL
}

view_definition_md5() {
  "${psql_scratch[@]}" --tuples-only --no-align \
    --command="select pg_catalog.md5(pg_catalog.pg_get_viewdef('public.airfnb_v_truck_card'::pg_catalog.regclass, true));"
}

assert_denied() {
  local label="$1"
  local expected="$2"
  local sql="$3"
  if "${psql_scratch[@]}" --command="$sql" >"$denial_log" 2>&1; then
    printf 'expected denial unexpectedly succeeded: %s\n' "$label" >&2
    return 1
  fi
  if ! grep -Fqi "$expected" "$denial_log"; then
    printf 'denial failed for unexpected reason: %s\n' "$label" >&2
    sed -n '1,100p' "$denial_log" >&2
    return 1
  fi
}

assert_negative_boundaries() {
  local negative_fixture="insert into auth.users (id,email,raw_user_meta_data) values ('f2610000-0000-4000-8000-000000000001','catalog-negative-owner@example.invalid','{\"full_name\":\"Catalog Negative Owner\"}'::jsonb); update public.airfnb_profiles set role='owner'::public.airfnb_user_role where id='f2610000-0000-4000-8000-000000000001'; insert into public.airfnb_trucks (id,owner_id,slug,name,status,service_type,capacity,base_price) values ('f2610000-0000-4000-8000-000000000010','f2610000-0000-4000-8000-000000000001','catalog-negative-active','Catalog Negative Active','active','food_truck',50,250);"
  local owner_claim="select pg_catalog.set_config('request.jwt.claim.sub','f2610000-0000-4000-8000-000000000001',true);"
  local owner_truck="'f2610000-0000-4000-8000-000000000010'::uuid"
  assert_denied invalid_owner_transition 'supplier status transition is not allowed' \
    "begin; $negative_fixture $owner_claim set local role authenticated; update public.airfnb_trucks set status='archived' where id=$owner_truck; rollback;"
  assert_denied protected_featured_write 'permission denied' \
    "begin; $negative_fixture $owner_claim set local role authenticated; update public.airfnb_trucks set featured=true where id=$owner_truck; rollback;"
  assert_denied protected_owner_write 'permission denied' \
    "begin; $negative_fixture $owner_claim set local role authenticated; update public.airfnb_trucks set owner_id=auth.uid() where id=$owner_truck; rollback;"
  assert_denied supplier_delete 'permission denied' \
    "begin; $negative_fixture $owner_claim set local role authenticated; delete from public.airfnb_trucks where id=$owner_truck; rollback;"
  assert_denied invalid_service_type 'invalid input value' \
    "begin; $negative_fixture $owner_claim set local role authenticated; update public.airfnb_trucks set service_type='restaurant' where id=$owner_truck; rollback;"
  assert_denied service_role_direct_mutation 'permission denied' \
    "begin; $negative_fixture set local role service_role; update public.airfnb_trucks set name='denied' where id=$owner_truck; rollback;"
}

for prestate in legacy old; do
  scratch_database="fb_tailor_catalog_${$}_${RANDOM}_${prestate}"
  is_scratch_database "$scratch_database" || {
    printf 'generated unsafe scratch database name\n' >&2
    exit 65
  }
  [[ "$scratch_database" != "$source_database" ]] || exit 65
  [[ "$(database_count "$scratch_database")" == 0 ]] || {
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
  [[ "$("${psql_scratch[@]}" --tuples-only --no-align --command='select current_database();')" == "$scratch_database" ]] || exit 65

  for predecessor_file in \
    "$runtime_integrity_file" "$privacy_file" "$messaging_file" "$storage_file"
  do
    "${psql_scratch[@]}" --file="$predecessor_file" >/dev/null
  done
  if [[ "$prestate" == legacy ]]; then
    run_runtime_phase reconstruct_legacy
  fi
  run_runtime_phase "assert_pre_${prestate}"
  printf 'PRE_FIX_REPRODUCED prestate=%s\n' "$prestate"

  if [[ "$prestate" == legacy ]]; then
    legacy_state_before_probe="$(target_state_sha256)"
    "${psql_scratch[@]}" >/dev/null <<'SQL'
create schema catalog_legacy_view_probe;
create table catalog_legacy_view_probe.original_definition (
  viewdef text not null
);
insert into catalog_legacy_view_probe.original_definition(viewdef)
select pg_catalog.pg_get_viewdef('public.airfnb_v_truck_card'::pg_catalog.regclass, true);
do $legacy_view_drift$
declare
  v_viewdef text;
begin
  select original.viewdef into strict v_viewdef
    from catalog_legacy_view_probe.original_definition as original;
  execute pg_catalog.format(
    'create or replace view public.airfnb_v_truck_card with (security_invoker = true) as select * from (%s) as legacy_card where false',
    pg_catalog.regexp_replace(v_viewdef, ';[[:space:]]*$', '')
  );
end
$legacy_view_drift$;
SQL
    [[ "$("${psql_scratch[@]}" --tuples-only --no-align --command="select pg_catalog.count(*) = 27 and (select reloptions from pg_catalog.pg_class where oid = 'public.airfnb_v_truck_card'::pg_catalog.regclass) = array['security_invoker=true']::text[] from pg_catalog.pg_attribute where attrelid = 'public.airfnb_v_truck_card'::pg_catalog.regclass and attnum > 0 and not attisdropped;")" == t ]] || exit 1
    legacy_drift_view_hash="$(view_definition_md5)"
    [[ "$legacy_drift_view_hash" != '5e17d15485c2be8af68157568ba84028' ]] || exit 1
    legacy_drift_state_before_reject="$(target_state_sha256)"
    if "${psql_scratch[@]}" --file="$migration_file" >"$failure_log" 2>&1; then
      printf 'same-column legacy view semantic drift unexpectedly passed\n' >&2
      exit 1
    fi
    grep -Fq 'mixed or unknown prestate' "$failure_log" || {
      sed -n '1,140p' "$failure_log" >&2
      exit 1
    }
    [[ "$legacy_drift_view_hash" == "$(view_definition_md5)" ]] || {
      printf 'legacy view drift hash changed during refused migration\n' >&2
      exit 1
    }
    [[ "$legacy_drift_state_before_reject" == "$(target_state_sha256)" ]] || {
      printf 'legacy view drift state changed during refused migration\n' >&2
      exit 1
    }
    "${psql_scratch[@]}" >/dev/null <<'SQL'
do $legacy_view_restore$
declare
  v_viewdef text;
begin
  select original.viewdef into strict v_viewdef
    from catalog_legacy_view_probe.original_definition as original;
  execute 'create or replace view public.airfnb_v_truck_card with (security_invoker = true) as ' || v_viewdef;
end
$legacy_view_restore$;
drop schema catalog_legacy_view_probe cascade;
SQL
    [[ "$(view_definition_md5)" == '5e17d15485c2be8af68157568ba84028' ]] || exit 1
    [[ "$legacy_state_before_probe" == "$(target_state_sha256)" ]] || exit 1
    printf 'LEGACY_VIEW_DEFINITION_DRIFT_REJECTED prestate=%s hash=%s\n' "$prestate" "$legacy_drift_view_hash"
  fi

  "${psql_scratch[@]}" >/dev/null <<'SQL'
create schema catalog_reconciliation_sabotage;
create function catalog_reconciliation_sabotage.fail_after_catalog_writes()
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
       and v_command.schema_name = 'public'
       and v_command.object_identity like '%airfnb_guard_truck_moderation(%' then
      raise exception 'intentional catalog reconciliation rollback proof';
    end if;
  end loop;
end
$sabotage$;
create event trigger catalog_reconciliation_sabotage
  on ddl_command_end
  execute function catalog_reconciliation_sabotage.fail_after_catalog_writes();
SQL

  state_before_failure="$(target_state_sha256)"
  if "${psql_scratch[@]}" --file="$migration_file" >"$failure_log" 2>&1; then
    printf 'intentional mid-migration failure unexpectedly succeeded\n' >&2
    exit 1
  fi
  grep -Fq 'intentional catalog reconciliation rollback proof' "$failure_log" || {
    sed -n '1,140p' "$failure_log" >&2
    exit 1
  }
  [[ "$state_before_failure" == "$(target_state_sha256)" ]] || {
    printf 'intentional failure did not roll target state back\n' >&2
    exit 1
  }
  printf 'INTENTIONAL_FAILURE_ROLLBACK_VERIFIED prestate=%s state=%s\n' "$prestate" "$state_before_failure"
  "${psql_scratch[@]}" \
    --command='drop event trigger catalog_reconciliation_sabotage' \
    --command='drop schema catalog_reconciliation_sabotage cascade' >/dev/null

  "${psql_scratch[@]}" --file="$migration_file" >/dev/null
  state_after_apply="$(target_state_sha256)"
  run_runtime_phase assert_good
  assert_negative_boundaries

  "${psql_scratch[@]}" --command="alter policy airfnb_trucks_owner_update on public.airfnb_trucks using (true) with check ((owner_id = (select auth.uid())) or public.airfnb_is_admin());" >/dev/null
  drift_state_before="$(target_state_sha256)"
  if "${psql_scratch[@]}" --file="$migration_file" >"$failure_log" 2>&1; then
    printf 'same-name moderation policy drift unexpectedly passed\n' >&2
    exit 1
  fi
  grep -Fq 'candidate moderation state drifted' "$failure_log" || {
    sed -n '1,140p' "$failure_log" >&2
    exit 1
  }
  [[ "$drift_state_before" == "$(target_state_sha256)" ]] || exit 1
  "${psql_scratch[@]}" --command="alter policy airfnb_trucks_owner_update on public.airfnb_trucks using ((owner_id = (select auth.uid())) or public.airfnb_is_admin()) with check ((owner_id = (select auth.uid())) or public.airfnb_is_admin());" >/dev/null
  [[ "$state_after_apply" == "$(target_state_sha256)" ]] || exit 1
  printf 'SAME_NAME_POLICY_DRIFT_REJECTED prestate=%s\n' "$prestate"

  "${psql_scratch[@]}" --command='grant update (featured) on public.airfnb_trucks to authenticated;' >/dev/null
  acl_drift_state_before="$(target_state_sha256)"
  if "${psql_scratch[@]}" --file="$migration_file" >"$failure_log" 2>&1; then
    printf 'protected-column ACL drift unexpectedly passed\n' >&2
    exit 1
  fi
  grep -Fq 'mutation column ACL drifted' "$failure_log" || {
    sed -n '1,140p' "$failure_log" >&2
    exit 1
  }
  [[ "$acl_drift_state_before" == "$(target_state_sha256)" ]] || exit 1
  "${psql_scratch[@]}" --command='revoke update (featured) on public.airfnb_trucks from authenticated;' >/dev/null
  [[ "$state_after_apply" == "$(target_state_sha256)" ]] || exit 1
  printf 'COLUMN_ACL_DRIFT_REJECTED prestate=%s\n' "$prestate"

  "${psql_scratch[@]}" --command='alter view public.airfnb_v_truck_card set (security_invoker = false);' >/dev/null
  view_drift_state_before="$(target_state_sha256)"
  if "${psql_scratch[@]}" --file="$migration_file" >"$failure_log" 2>&1; then
    printf 'view security semantic drift unexpectedly passed\n' >&2
    exit 1
  fi
  grep -Fq 'catalog view security mode drifted' "$failure_log" || {
    sed -n '1,140p' "$failure_log" >&2
    exit 1
  }
  [[ "$view_drift_state_before" == "$(target_state_sha256)" ]] || exit 1
  "${psql_scratch[@]}" --command='alter view public.airfnb_v_truck_card set (security_invoker = true);' >/dev/null
  [[ "$state_after_apply" == "$(target_state_sha256)" ]] || exit 1
  printf 'VIEW_SEMANTIC_DRIFT_REJECTED prestate=%s\n' "$prestate"

  "${psql_scratch[@]}" --file="$migration_file" >/dev/null
  state_after_reapply="$(target_state_sha256)"
  [[ "$state_after_apply" == "$state_after_reapply" ]] || {
    printf 'reapply changed final semantic state\n' >&2
    exit 1
  }
  run_runtime_phase assert_good
  printf 'GOOD_APPLY_REAPPLY_VERIFIED prestate=%s state=%s\n' "$prestate" "$state_after_reapply"

  cleanup_scratch
  [[ "$(database_count "$scratch_database")" == 0 ]] || {
    printf 'scratch residue remains: %s\n' "$scratch_database" >&2
    exit 1
  }
  printf 'SCRATCH_CLEANED database=%s\n' "$scratch_database"
done

source_sha256_after="$(source_fingerprint)"
[[ "$source_sha256_before" == "$source_sha256_after" ]] || {
  printf 'source database fingerprint changed\n' >&2
  exit 1
}

scratch_residue="$(PGOPTIONS='-c default_transaction_read_only=on' "${psql_source[@]}" \
  --command="select pg_catalog.count(*) from pg_catalog.pg_database where datname like 'fb_tailor_catalog_%';")"
[[ "$scratch_residue" == 0 ]] || {
  printf 'SCRATCH_RESIDUE=%s\n' "$scratch_residue" >&2
  exit 1
}

printf 'SOURCE_SHA256_BEFORE=%s\n' "$source_sha256_before"
printf 'SOURCE_SHA256_AFTER=%s\n' "$source_sha256_after"
printf 'MIGRATION_SHA256=%s\n' "$migration_sha256"
printf 'RUNTIME_SHA256=%s\n' "$runtime_sha256"
printf 'RUNTIME_INTEGRITY_PREDECESSOR_SHA256=%s\n' "$runtime_integrity_sha256"
printf 'PRIVACY_PREDECESSOR_SHA256=%s\n' "$privacy_sha256"
printf 'MESSAGING_PREDECESSOR_SHA256=%s\n' "$messaging_sha256"
printf 'STORAGE_PREDECESSOR_SHA256=%s\n' "$storage_sha256"
printf 'SCRATCH_RESIDUE=0\n'
