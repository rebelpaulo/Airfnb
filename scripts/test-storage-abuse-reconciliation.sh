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
[[ ! "$source_database" =~ ^fb_tailor_storage_ ]] || {
  printf 'refusing storage scratch database as source\n' >&2
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
migration_file="$repository_root/supabase/migrations/20260820154100_storage_abuse_reconciliation.sql"
runtime_file="$repository_root/tests/storage-abuse-reconciliation-runtime.sql"

[[ -f "$migration_file" && -f "$runtime_file" ]] || {
  printf 'storage reconciliation migration/runtime artifact is missing\n' >&2
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
  --dbname="$source_database" --set=ON_ERROR_STOP=1 --tuples-only --no-align --quiet
)

actual_source_database="$(PGOPTIONS='-c default_transaction_read_only=on' "${psql_source[@]}" --command='select current_database();')"
[[ "$actual_source_database" == "$source_database" ]] || {
  printf 'source database connection mismatch\n' >&2
  exit 65
}

source_fingerprint() {
  PGOPTIONS='-c default_transaction_read_only=on' pg_dump \
    --host="$socket_directory" \
    --port="$postgres_port" \
    --dbname="$source_database" \
    --format=plain \
    --schema=auth \
    --schema=public \
    --schema=storage \
    --no-owner \
    | sed '/^\\restrict /d; /^\\unrestrict /d' \
    | sha256_stream
}

database_count() {
  local database_name="$1"
  [[ "$database_name" =~ ^fb_tailor_storage_[0-9]+_[0-9]+_(historical|old)$ ]] || return 1
  PGOPTIONS='-c default_transaction_read_only=on' "${psql_source[@]}" \
    --command="select pg_catalog.count(*) from pg_catalog.pg_database where datname = '$database_name';"
}

source_contract="$(PGOPTIONS='-c default_transaction_read_only=on' "${psql_source[@]}" <<'SQL'
begin transaction read only;
select pg_catalog.concat_ws(
  ':',
  current_setting('transaction_read_only'),
  (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc
    where oid = 'public.airfnb_can_read_truck_child(text)'::regprocedure),
  (select pg_catalog.md5(prosrc) from pg_catalog.pg_proc
    where oid = 'public.airfnb_check_rate_limit(text,text,integer,integer)'::regprocedure),
  (select pg_catalog.count(*) from pg_catalog.pg_policy
    where polrelid = 'storage.objects'::regclass),
  (select pg_catalog.bool_and(
     case when id = 'airfnb-documents'
       then not public and file_size_limit = 8388608 and allowed_mime_types = array['application/pdf']::text[]
       else public and file_size_limit = 2097152 and allowed_mime_types = array['image/jpeg','image/png','image/webp']::text[]
     end
   ) from storage.buckets where id like 'airfnb-%'),
  (select pg_catalog.count(*) from storage.buckets where id like 'airfnb-%'),
  (select pg_catalog.count(*) from auth.users where id::text like 'f2600000-0000-4000-8000-%'),
  (select pg_catalog.count(*) from storage.objects where id::text like 'f2600000-0000-4000-8000-%')
);
rollback;
SQL
)"
[[ "$source_contract" == "on:3d9d41a7dc6e3f52091dddeba50a1884:4c11600d1e054c11a972171d36dc7b8e:12:t:5:0:0" ]] || {
  printf 'source database does not match verified old-candidate fixture: %s\n' "$source_contract" >&2
  exit 65
}

source_sha256_before="$(source_fingerprint)"
migration_sha256="$(sha256_file "$migration_file")"
runtime_sha256="$(sha256_file "$runtime_file")"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/fb-tailor-storage.XXXXXX")"
failure_log="$temporary_directory/intentional-failure.log"
denial_log="$temporary_directory/denial.log"
scratch_database=""
scratch_created=0

is_scratch_database() {
  [[ "$1" =~ ^fb_tailor_storage_[0-9]+_[0-9]+_(historical|old)$ ]]
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
    --set=storage_runtime_phase="$phase" \
    --set=storage_runtime_database="$scratch_database" \
    --file="$runtime_file" >/dev/null
}

target_state_sha256() {
  "${psql_scratch[@]}" --tuples-only --no-align --field-separator='|' <<'SQL' | sha256_stream
select 'bucket', id, name, public::text, coalesce(file_size_limit::text,''), coalesce(allowed_mime_types::text,'')
  from storage.buckets where id like 'airfnb-%'
union all
select 'function', procedure.oid::text, procedure.proowner::text, procedure.prosecdef::text,
       coalesce(procedure.proconfig::text,''), pg_catalog.md5(procedure.prosrc)
  from pg_catalog.pg_proc as procedure
  join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
 where namespace.nspname = 'public'
   and procedure.proname in ('airfnb_can_manage_truck','airfnb_can_read_truck_child','airfnb_check_rate_limit')
union all
select 'policy', policy.polrelid::text, policy.polname, policy.polcmd::text,
       policy.polroles::text,
       pg_catalog.md5(pg_catalog.concat_ws('|',
         coalesce(pg_catalog.pg_get_expr(policy.polqual, policy.polrelid),''),
         coalesce(pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid),'')))
  from pg_catalog.pg_policy as policy
 where policy.polrelid in (
   'public.airfnb_truck_images'::regclass,
   'public.airfnb_menu_items'::regclass,
   'public.airfnb_truck_categories'::regclass,
   'public.airfnb_rate_limits'::regclass,
   'public.airfnb_partner_leads'::regclass,
   'public.airfnb_newsletter_subs'::regclass,
   'public.airfnb_newsletter_subscribers'::regclass,
   'public.airfnb_contact_requests'::regclass,
   'storage.objects'::regclass
 )
union all
select 'relation', relation.oid::text, relation.relowner::text,
       relation.relrowsecurity::text, coalesce(relation.relacl::text,''), ''
  from pg_catalog.pg_class as relation
 where relation.oid in (
   'public.airfnb_trucks'::regclass,
   'public.airfnb_truck_images'::regclass,
   'public.airfnb_menu_items'::regclass,
   'public.airfnb_truck_categories'::regclass,
   'public.airfnb_rate_limits'::regclass,
   'public.airfnb_partner_leads'::regclass,
   'public.airfnb_newsletter_subs'::regclass,
   'public.airfnb_newsletter_subscribers'::regclass,
   'public.airfnb_contact_requests'::regclass
 )
union all
select 'constraint', c.conrelid::text, c.conname, c.contype::text,
       pg_catalog.pg_get_constraintdef(c.oid), ''
  from pg_catalog.pg_constraint as c
 where c.conrelid = 'public.airfnb_rate_limits'::regclass
union all
select 'index', i.schemaname, i.tablename, i.indexname, i.indexdef, ''
  from pg_catalog.pg_indexes as i
 where i.schemaname = 'public' and i.tablename = 'airfnb_rate_limits'
order by 1,2,3;
SQL
}

catalog_acl_sha256() {
  "${psql_scratch[@]}" --tuples-only --no-align --field-separator='|' <<'SQL' | sha256_stream
select 'relation', relation.oid::text, '0', coalesce(relation.relacl::text, '')
  from pg_catalog.pg_class as relation
 where relation.oid in (
   'public.airfnb_trucks'::regclass,
   'public.airfnb_truck_images'::regclass,
   'public.airfnb_menu_items'::regclass,
   'public.airfnb_truck_categories'::regclass
 )
union all
select 'column', attribute.attrelid::text, attribute.attnum::text,
       coalesce(attribute.attacl::text, '')
  from pg_catalog.pg_attribute as attribute
 where attribute.attrelid in (
   'public.airfnb_trucks'::regclass,
   'public.airfnb_truck_images'::regclass,
   'public.airfnb_menu_items'::regclass,
   'public.airfnb_truck_categories'::regclass
 )
   and attribute.attnum > 0
   and not attribute.attisdropped
order by 1,2,3;
SQL
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
    sed -n '1,80p' "$denial_log" >&2
    return 1
  fi
}

assert_negative_boundaries() {
  assert_denied raw_catalog_category 'permission denied' \
    "begin; set local role anon; select * from public.airfnb_truck_categories; rollback;"
  assert_denied unrelated_child_insert 'row-level security' \
    "begin; grant insert on public.airfnb_menu_items to authenticated; select set_config('request.jwt.claim.sub','f2600000-0000-4000-8000-000000000002',true); set local role authenticated; insert into public.airfnb_menu_items(truck_id,name) values('f2600000-0000-4000-8000-000000000010','denied'); rollback;"
  assert_denied owner_cross_truck_insert 'row-level security' \
    "begin; grant insert on public.airfnb_truck_images to authenticated; select set_config('request.jwt.claim.sub','f2600000-0000-4000-8000-000000000001',true); set local role authenticated; insert into public.airfnb_truck_images(truck_id,url) values('f2600000-0000-4000-8000-000000000012','/storage/denied.jpg'); rollback;"
  assert_denied unrelated_storage_insert 'row-level security' \
    "begin; grant insert on storage.objects to authenticated; select set_config('request.jwt.claim.sub','f2600000-0000-4000-8000-000000000002',true); set local role authenticated; insert into storage.objects(bucket_id,name) values('airfnb-truck-images','f2600000-0000-4000-8000-000000000010/denied.jpg'); rollback;"
  assert_denied malformed_storage_path 'row-level security' \
    "begin; grant insert on storage.objects to authenticated; select set_config('request.jwt.claim.sub','f2600000-0000-4000-8000-000000000001',true); set local role authenticated; insert into storage.objects(bucket_id,name) values('airfnb-truck-images','not-a-uuid/denied.jpg'); rollback;"
  assert_denied menu_storage_write 'row-level security' \
    "begin; grant insert on storage.objects to authenticated; select set_config('request.jwt.claim.sub','f2600000-0000-4000-8000-000000000001',true); set local role authenticated; insert into storage.objects(bucket_id,name) values('airfnb-menu-images','menu.jpg'); rollback;"
  assert_denied blog_storage_write 'row-level security' \
    "begin; grant insert on storage.objects to authenticated; select set_config('request.jwt.claim.sub','f2600000-0000-4000-8000-000000000003',true); set local role authenticated; insert into storage.objects(bucket_id,name) values('airfnb-blog-images','blog.jpg'); rollback;"
  assert_denied direct_partner_ingestion 'row-level security' \
    "begin; grant insert on public.airfnb_partner_leads to anon; set local role anon; insert into public.airfnb_partner_leads(kind,name,email) values('venues','denied','denied@example.invalid'); rollback;"
  assert_denied direct_newsletter_ingestion 'row-level security' \
    "begin; grant insert on public.airfnb_newsletter_subs to authenticated; set local role authenticated; insert into public.airfnb_newsletter_subs(email) values('denied@example.invalid'); rollback;"
  assert_denied anon_rate_rpc 'permission denied for function' \
    "begin; set local role anon; select public.airfnb_check_rate_limit('storage_probe','opaque',1,60); rollback;"
  assert_denied authenticated_rate_rpc 'permission denied for function' \
    "begin; set local role authenticated; select public.airfnb_check_rate_limit('storage_probe','opaque',1,60); rollback;"
  assert_denied service_rate_table 'permission denied for table' \
    "begin; set local role service_role; select * from public.airfnb_rate_limits; rollback;"
  assert_denied invalid_rate_action 'invalid rate-limit parameters' \
    "begin; set local role service_role; select public.airfnb_check_rate_limit('Bad-Action','opaque',1,60); rollback;"
  assert_denied invalid_rate_bucket 'invalid rate-limit parameters' \
    "begin; set local role service_role; select public.airfnb_check_rate_limit('storage_probe','raw@example.invalid',1,60); rollback;"
  assert_denied invalid_rate_limit 'invalid rate-limit parameters' \
    "begin; set local role service_role; select public.airfnb_check_rate_limit('storage_probe','opaque',10001,60); rollback;"
  assert_denied invalid_rate_window 'invalid rate-limit parameters' \
    "begin; set local role service_role; select public.airfnb_check_rate_limit('storage_probe','opaque',1,2678401); rollback;"
}

for prestate in historical old; do
  scratch_database="fb_tailor_storage_${$}_${RANDOM}_${prestate}"
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

  clone_name="$("${psql_scratch[@]}" --tuples-only --no-align --command='select current_database();')"
  [[ "$clone_name" == "$scratch_database" ]] || exit 65

  if [[ "$prestate" == historical ]]; then
    run_runtime_phase reconstruct_historical
  fi
  run_runtime_phase setup
  run_runtime_phase "assert_pre_${prestate}"
  printf 'PRE_FIX_REPRODUCED prestate=%s\n' "$prestate"
  catalog_acl_before="$(catalog_acl_sha256)"

  "${psql_scratch[@]}" >/dev/null <<'SQL'
create schema storage_reconciliation_sabotage;
create function storage_reconciliation_sabotage.fail_after_bucket_write()
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
       and v_command.object_identity like '%airfnb_can_manage_truck(%' then
      raise exception 'intentional storage abuse rollback proof';
    end if;
  end loop;
end
$sabotage$;
create event trigger storage_reconciliation_sabotage
  on ddl_command_end
  execute function storage_reconciliation_sabotage.fail_after_bucket_write();
SQL

  state_before_failure="$(target_state_sha256)"
  if "${psql_scratch[@]}" --file="$migration_file" >"$failure_log" 2>&1; then
    printf 'intentional mid-migration failure unexpectedly succeeded\n' >&2
    exit 1
  fi
  grep -Fq 'intentional storage abuse rollback proof' "$failure_log" || {
    sed -n '1,120p' "$failure_log" >&2
    exit 1
  }
  state_after_failure="$(target_state_sha256)"
  [[ "$state_before_failure" == "$state_after_failure" ]] || {
    printf 'intentional failure did not roll target state back\n' >&2
    exit 1
  }
  [[ "$catalog_acl_before" == "$(catalog_acl_sha256)" ]] || {
    printf 'intentional failure changed catalog table or column ACLs\n' >&2
    exit 1
  }
  printf 'INTENTIONAL_FAILURE_ROLLBACK_VERIFIED prestate=%s state=%s\n' "$prestate" "$state_after_failure"

  "${psql_scratch[@]}" \
    --command='drop event trigger storage_reconciliation_sabotage' \
    --command='drop schema storage_reconciliation_sabotage cascade' >/dev/null

  "${psql_scratch[@]}" --file="$migration_file" >/dev/null
  state_after_apply="$(target_state_sha256)"
  [[ "$catalog_acl_before" == "$(catalog_acl_sha256)" ]] || {
    printf 'migration changed catalog table or column ACLs\n' >&2
    exit 1
  }
  run_runtime_phase assert_good
  assert_negative_boundaries

  "${psql_scratch[@]}" --command='create policy storage_drift_probe on storage.objects for select using (false);' >/dev/null
  drift_state_before="$(target_state_sha256)"
  if "${psql_scratch[@]}" --file="$migration_file" >"$failure_log" 2>&1; then
    printf 'injected policy drift unexpectedly passed\n' >&2
    exit 1
  fi
  grep -Fq 'Storage policy set drifted' "$failure_log" || {
    sed -n '1,120p' "$failure_log" >&2
    exit 1
  }
  [[ "$drift_state_before" == "$(target_state_sha256)" ]] || {
    printf 'drift rejection changed target state\n' >&2
    exit 1
  }
  "${psql_scratch[@]}" --command='drop policy storage_drift_probe on storage.objects;' >/dev/null
  [[ "$state_after_apply" == "$(target_state_sha256)" ]] || {
    printf 'drift probe cleanup did not restore target state\n' >&2
    exit 1
  }
  printf 'INJECTED_DRIFT_REJECTED prestate=%s\n' "$prestate"

  "${psql_scratch[@]}" --command="alter policy airfnb_documents_owner_delete on storage.objects to authenticated using (true);" >/dev/null
  policy_drift_state_before="$(target_state_sha256)"
  if "${psql_scratch[@]}" --file="$migration_file" >"$failure_log" 2>&1; then
    printf 'same-name Storage policy drift unexpectedly passed\n' >&2
    exit 1
  fi
  grep -Fq 'final Storage policy drifted' "$failure_log" || {
    sed -n '1,120p' "$failure_log" >&2
    exit 1
  }
  [[ "$policy_drift_state_before" == "$(target_state_sha256)" ]] || {
    printf 'same-name Storage policy rejection changed target state\n' >&2
    exit 1
  }
  "${psql_scratch[@]}" >/dev/null <<'SQL'
alter policy airfnb_documents_owner_delete
  on storage.objects to authenticated
  using (
    bucket_id = 'airfnb-documents'
    and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+'
    and public.airfnb_can_manage_truck(split_part(name, '/', 1))
  );
SQL
  [[ "$state_after_apply" == "$(target_state_sha256)" ]] || {
    printf 'same-name Storage policy cleanup did not restore target state\n' >&2
    exit 1
  }
  printf 'SAME_NAME_STORAGE_POLICY_DRIFT_REJECTED prestate=%s\n' "$prestate"

  "${psql_scratch[@]}" >/dev/null <<'SQL'
alter table public.airfnb_rate_limits
  drop constraint airfnb_rate_limits_action_format;
alter table public.airfnb_rate_limits
  add constraint airfnb_rate_limits_action_format check (true);
SQL
  constraint_drift_state_before="$(target_state_sha256)"
  if "${psql_scratch[@]}" --file="$migration_file" >"$failure_log" 2>&1; then
    printf 'same-name rate-limit constraint drift unexpectedly passed\n' >&2
    exit 1
  fi
  grep -Fq 'rate-limit constraint/index drifted' "$failure_log" || {
    sed -n '1,120p' "$failure_log" >&2
    exit 1
  }
  [[ "$constraint_drift_state_before" == "$(target_state_sha256)" ]] || {
    printf 'same-name constraint rejection changed target state\n' >&2
    exit 1
  }
  "${psql_scratch[@]}" >/dev/null <<'SQL'
alter table public.airfnb_rate_limits
  drop constraint airfnb_rate_limits_action_format;
alter table public.airfnb_rate_limits
  add constraint airfnb_rate_limits_action_format
  check (action ~ '^[a-z][a-z0-9_]{0,63}$');
SQL
  [[ "$state_after_apply" == "$(target_state_sha256)" ]] || {
    printf 'same-name constraint cleanup did not restore target state\n' >&2
    exit 1
  }
  printf 'SAME_NAME_RATE_CONSTRAINT_DRIFT_REJECTED prestate=%s\n' "$prestate"

  "${psql_scratch[@]}" >/dev/null <<'SQL'
drop index public.airfnb_rate_limits_window_at_idx;
create index airfnb_rate_limits_window_at_idx
  on public.airfnb_rate_limits (count);
SQL
  index_drift_state_before="$(target_state_sha256)"
  if "${psql_scratch[@]}" --file="$migration_file" >"$failure_log" 2>&1; then
    printf 'same-name rate-limit index drift unexpectedly passed\n' >&2
    exit 1
  fi
  grep -Fq 'rate-limit constraint/index drifted' "$failure_log" || {
    sed -n '1,120p' "$failure_log" >&2
    exit 1
  }
  [[ "$index_drift_state_before" == "$(target_state_sha256)" ]] || {
    printf 'same-name index rejection changed target state\n' >&2
    exit 1
  }
  "${psql_scratch[@]}" >/dev/null <<'SQL'
drop index public.airfnb_rate_limits_window_at_idx;
create index airfnb_rate_limits_window_at_idx
  on public.airfnb_rate_limits (window_at);
SQL
  [[ "$state_after_apply" == "$(target_state_sha256)" ]] || {
    printf 'same-name index cleanup did not restore target state\n' >&2
    exit 1
  }
  printf 'SAME_NAME_RATE_INDEX_DRIFT_REJECTED prestate=%s\n' "$prestate"

  "${psql_scratch[@]}" --file="$migration_file" >/dev/null
  state_after_reapply="$(target_state_sha256)"
  [[ "$state_after_apply" == "$state_after_reapply" ]] || {
    printf 'reapply changed final semantic state\n' >&2
    exit 1
  }
  [[ "$catalog_acl_before" == "$(catalog_acl_sha256)" ]] || {
    printf 'reapply changed catalog table or column ACLs\n' >&2
    exit 1
  }
  run_runtime_phase assert_good
  printf 'GOOD_APPLY_REAPPLY_VERIFIED prestate=%s state=%s\n' "$prestate" "$state_after_reapply"

  cleanup_scratch
  residue="$(database_count "$scratch_database")"
  [[ "$residue" == 0 ]] || {
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
  --command="select pg_catalog.count(*) from pg_catalog.pg_database where datname like 'fb_tailor_storage_%';")"
[[ "$scratch_residue" == 0 ]] || {
  printf 'SCRATCH_RESIDUE=%s\n' "$scratch_residue" >&2
  exit 1
}

printf 'SOURCE_SHA256_BEFORE=%s\n' "$source_sha256_before"
printf 'SOURCE_SHA256_AFTER=%s\n' "$source_sha256_after"
printf 'MIGRATION_SHA256=%s\n' "$migration_sha256"
printf 'RUNTIME_SHA256=%s\n' "$runtime_sha256"
printf 'SCRATCH_RESIDUE=%s\n' "$scratch_residue"
