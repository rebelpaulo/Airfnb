#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf '%s\n' "usage: $0 --socket SOCKET_DIRECTORY --port PORT --source-db SOURCE_DATABASE [--fixture-history-hash MD5]" >&2
  exit 64
}

socket_directory=""
postgres_port=""
source_database=""
fixture_history_hash=""
while (($# > 0)); do
  case "$1" in
    --socket) (($# >= 2)) || usage; socket_directory="$2"; shift 2 ;;
    --port) (($# >= 2)) || usage; postgres_port="$2"; shift 2 ;;
    --source-db) (($# >= 2)) || usage; source_database="$2"; shift 2 ;;
    --fixture-history-hash) (($# >= 2)) || usage; fixture_history_hash="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ "$socket_directory" == /* && "$socket_directory" != "/" ]] || usage
[[ "$postgres_port" =~ ^[0-9]+$ ]] && ((postgres_port >= 1 && postgres_port <= 65535)) || usage
[[ "$source_database" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]] || usage
[[ "$source_database" != template0 && "$source_database" != template1 ]] || usage
[[ ! "$source_database" =~ ^fb_tailor_indigo_ ]] || usage
[[ -z "$fixture_history_hash" || "$fixture_history_hash" =~ ^[0-9a-f]{32}$ ]] || usage
[[ -S "$socket_directory/.s.PGSQL.$postgres_port" ]] || { printf 'local socket unavailable\n' >&2; exit 66; }

for command_name in psql pg_dump createdb dropdb shasum awk sed mktemp grep cp; do
  command -v "$command_name" >/dev/null || { printf 'missing local command: %s\n' "$command_name" >&2; exit 69; }
done

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
migration_file="$repository_root/scripts/migrations/apply/20260821124724_indigo_shared_project_baseline.sql"
rollback_file="$repository_root/scripts/migrations/rollback/20260821124724_indigo_shared_project_baseline.sql"
runtime_file="$repository_root/tests/indigo-shared-project-baseline-runtime.sql"
source_test_file="$repository_root/tests/indigo-shared-project-baseline-source.test.mjs"
runbook_file="$repository_root/supabase/INDIGO_SHARED_PROJECT_MIGRATION_RUNBOOK.md"
driver_file="$repository_root/scripts/test-indigo-shared-project-baseline.sh"
artifacts=("$migration_file" "$rollback_file" "$driver_file" "$runtime_file" "$source_test_file" "$runbook_file")

sha256_file() { shasum -a 256 "$1" | awk '{print $1}'; }
sha256_stream() { shasum -a 256 | awk '{print $1}'; }
artifact_manifest() { local path; for path in "${artifacts[@]}"; do printf '%s  %s\n' "$(sha256_file "$path")" "$path"; done; }

psql_source=(psql -X --no-psqlrc --host="$socket_directory" --port="$postgres_port" --dbname="$source_database" --set=ON_ERROR_STOP=1 --quiet)
[[ "$(PGOPTIONS='-c default_transaction_read_only=on' "${psql_source[@]}" --tuples-only --no-align --command='select current_database();')" == "$source_database" ]] || exit 65

source_history="$(PGOPTIONS='-c default_transaction_read_only=on' "${psql_source[@]}" --tuples-only --no-align --field-separator=':' --command="select count(*),max(version),md5(string_agg(version,',' order by version)) from supabase_migrations.schema_migrations;")"
if [[ -z "$fixture_history_hash" ]]; then
  [[ "$source_history" == '85:20260821171040:1f0eebdf3bcee57d873c3d4f87f260a9' ]] || { printf 'source is not the exact Indigo predecessor: %s\n' "$source_history" >&2; exit 65; }
else
  [[ "$source_history" == "85:20260821171040:$fixture_history_hash" ]] || { printf 'fixture history mismatch: %s\n' "$source_history" >&2; exit 65; }
fi
[[ "$(PGOPTIONS='-c default_transaction_read_only=on' "${psql_source[@]}" --tuples-only --no-align --command="select count(*) from pg_catalog.pg_extension where extname='pg_trgm';")" == 0 ]] || {
  printf 'source predecessor unexpectedly has pg_trgm installed\n' >&2; exit 65;
}

source_fingerprint() {
  PGOPTIONS='-c default_transaction_read_only=on' pg_dump --host="$socket_directory" --port="$postgres_port" --dbname="$source_database" \
    --format=plain --schema=auth --schema=public --schema=storage --schema=cron --schema=supabase_migrations --no-owner \
    | sed '/^\\restrict /d; /^\\unrestrict /d' | sha256_stream
}

source_fingerprint_before="$(source_fingerprint)"
manifest_before="$(artifact_manifest)"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/fb-tailor-indigo-baseline.XXXXXX")"
scratch_databases=()

is_scratch() { [[ "$1" =~ ^fb_tailor_indigo_[0-9]+_[0-9]+_(tamper|good)$ ]]; }
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

candidate_migration="$migration_file"
if [[ -n "$fixture_history_hash" && "$fixture_history_hash" != '1f0eebdf3bcee57d873c3d4f87f260a9' ]]; then
  candidate_migration="$temporary_directory/fixture-baseline.sql"
  cp "$migration_file" "$candidate_migration"
  sed -i.bak "s/1f0eebdf3bcee57d873c3d4f87f260a9/$fixture_history_hash/" "$candidate_migration"
  find "$temporary_directory" -name '*.bak' -delete
fi

create_scratch() {
  local suffix="$1"
  scratch_database="fb_tailor_indigo_${$}_${RANDOM}_${suffix}"
  is_scratch "$scratch_database" || exit 65
  scratch_databases+=("$scratch_database")
  createdb --host="$socket_directory" --port="$postgres_port" --maintenance-db=template1 --template="$source_database" -- "$scratch_database"
  psql_scratch=(psql -X --no-psqlrc --host="$socket_directory" --port="$postgres_port" --dbname="$scratch_database" --set=ON_ERROR_STOP=1 --quiet)
}

scratch_fingerprint() {
  {
  "${psql_scratch[@]}" --tuples-only --no-align --field-separator='|' <<'SQL'
select 'auth',count(*)::text,md5(string_agg(id::text||':'||coalesce(email,''),',' order by id)) from auth.users
union all select 'history',count(*)::text,max(version)||':'||md5(string_agg(version,',' order by version)) from supabase_migrations.schema_migrations
union all select 'relations',count(*)::text,coalesce(string_agg(c.relname||':'||c.relkind::text,',' order by c.relname),'') from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname like 'airfnb_%'
union all select 'policies',count(*)::text,coalesce(md5(string_agg(entry,E'\n' order by entry)),'')
 from (
   select jsonb_build_array(schemaname,tablename,policyname,permissive,roles,cmd,coalesce(qual,''),coalesce(with_check,''))::text as entry
     from pg_catalog.pg_policies where schemaname='public'
 ) policy_entries
union all select 'triggers',count(*)::text,coalesce(md5(string_agg(entry,E'\n' order by entry)),'')
 from (
   select jsonb_build_array(n.nspname,c.relname,t.tgname,pg_catalog.pg_get_triggerdef(t.oid,true))::text as entry
     from pg_catalog.pg_trigger t
     join pg_catalog.pg_class c on c.oid=t.tgrelid
     join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and not t.tgisinternal
 ) trigger_entries
union all select 'buckets',count(*)::text,coalesce(string_agg(id||':'||file_size_limit::text,',' order by id),'') from storage.buckets where id like 'airfnb-%'
union all select 'objects',count(*)::text,coalesce(string_agg(bucket_id||':'||name,',' order by bucket_id,name),'') from storage.objects where bucket_id like 'airfnb-%'
union all select 'jobs',count(*)::text,coalesce(string_agg(jobname||':'||schedule||':'||command,',' order by jobname),'') from cron.job where jobname like 'airfnb_%'
order by 1;
SQL
  if [[ "$("${psql_scratch[@]}" --tuples-only --no-align --command="select pg_catalog.to_regclass('public.airfnb_baseline_manifest') is not null;")" == t ]]; then
    "${psql_scratch[@]}" --tuples-only --no-align --field-separator='|' <<'SQL'
select 'seed',count(*)::text,md5(string_agg(entry,E'\n' order by entry))
 from (
    select jsonb_build_array('airfnb_blog_categories',to_jsonb(seed_row))::text as entry from public.airfnb_blog_categories seed_row
    union all select jsonb_build_array('airfnb_blog_posts',to_jsonb(seed_row))::text from public.airfnb_blog_posts seed_row
    union all select jsonb_build_array('airfnb_categories',to_jsonb(seed_row))::text from public.airfnb_categories seed_row
    union all select jsonb_build_array('airfnb_faqs',to_jsonb(seed_row))::text from public.airfnb_faqs seed_row
    union all select jsonb_build_array('airfnb_menu_items',to_jsonb(seed_row))::text from public.airfnb_menu_items seed_row
    union all select jsonb_build_array('airfnb_platform_settings',to_jsonb(seed_row))::text from public.airfnb_platform_settings seed_row
    union all select jsonb_build_array('airfnb_service_providers',to_jsonb(seed_row))::text from public.airfnb_service_providers seed_row
    union all select jsonb_build_array('airfnb_truck_categories',to_jsonb(seed_row))::text from public.airfnb_truck_categories seed_row
    union all select jsonb_build_array('airfnb_truck_images',to_jsonb(seed_row))::text from public.airfnb_truck_images seed_row
    union all select jsonb_build_array('airfnb_trucks',to_jsonb(seed_row))::text from public.airfnb_trucks seed_row
 ) seed_entries;
SQL
  else
    printf 'seed|absent|\n'
  fi
  } | sha256_stream
}

assert_seed_drift_refused() {
  local label="$1" before log_file
  before="$(scratch_fingerprint)"
  log_file="$temporary_directory/seed-$label.log"
  if "${psql_scratch[@]}" --file="$candidate_migration" >"$log_file" 2>&1; then
    printf 'seed %s unexpectedly accepted\n' "$label" >&2; exit 1
  fi
  grep -Fq 'indigo baseline refused: F&B seed drift detected' "$log_file" || { sed -n '1,100p' "$log_file" >&2; exit 1; }
  [[ "$(scratch_fingerprint)" == "$before" ]] || { printf 'seed %s failure was not atomic\n' "$label" >&2; exit 1; }
}

create_scratch tamper
"${psql_scratch[@]}" --command="create table public.airfnb_collision(id integer primary key);" >/dev/null
tamper_before="$(scratch_fingerprint)"
if "${psql_scratch[@]}" --file="$candidate_migration" >"$temporary_directory/predecessor-tamper.log" 2>&1; then
  printf 'colliding predecessor unexpectedly accepted\n' >&2; exit 1
fi
grep -Fq 'indigo baseline refused: F&B collision or final-state drift detected' "$temporary_directory/predecessor-tamper.log" || { sed -n '1,100p' "$temporary_directory/predecessor-tamper.log" >&2; exit 1; }
[[ "$(scratch_fingerprint)" == "$tamper_before" ]] || { printf 'predecessor tamper failure was not atomic\n' >&2; exit 1; }

create_scratch good
auth_before="$("${psql_scratch[@]}" --tuples-only --no-align --command="select count(*)||':'||md5(string_agg(id::text||':'||coalesce(email,''),',' order by id)) from auth.users;")"
history_before="$("${psql_scratch[@]}" --tuples-only --no-align --command="select count(*)||':'||max(version)||':'||md5(string_agg(version,',' order by version)) from supabase_migrations.schema_migrations;")"
"${psql_scratch[@]}" --file="$candidate_migration" >/dev/null
"${psql_scratch[@]}" --file="$runtime_file" >/dev/null
candidate_before_reapply="$(scratch_fingerprint)"
"${psql_scratch[@]}" --file="$candidate_migration" >/dev/null
[[ "$(scratch_fingerprint)" == "$candidate_before_reapply" ]] || { printf 'reapply changed final state\n' >&2; exit 1; }
"${psql_scratch[@]}" --file="$runtime_file" >/dev/null

"${psql_scratch[@]}" --command="delete from public.airfnb_faqs where id=5;" >/dev/null
assert_seed_drift_refused removal
"${psql_scratch[@]}" --command="insert into public.airfnb_faqs(id,question,answer,topic,sort_order) values(5,'Restrições alimentares ou alergias.','A maioria dos trucks oferece opções vegetarianas, veganas e sem glúten. Indica as restrições no formulário de reserva.','menus',5);" >/dev/null
"${psql_scratch[@]}" --command="update public.airfnb_faqs set answer=answer||' tampered' where id=5;" >/dev/null
assert_seed_drift_refused alteration
"${psql_scratch[@]}" --command="update public.airfnb_faqs set answer='A maioria dos trucks oferece opções vegetarianas, veganas e sem glúten. Indica as restrições no formulário de reserva.' where id=5;" >/dev/null
"${psql_scratch[@]}" --command="insert into public.airfnb_faqs(id,question,answer,topic,sort_order) values(999,'Unexpected seed','Unexpected seed','runtime',999);" >/dev/null
assert_seed_drift_refused addition
"${psql_scratch[@]}" --command="delete from public.airfnb_faqs where id=999;" >/dev/null
"${psql_scratch[@]}" --file="$runtime_file" >/dev/null

"${psql_scratch[@]}" >/dev/null <<'SQL'
create table public.indigo_policy_collision_probe(id bigint primary key);
alter table public.indigo_policy_collision_probe enable row level security;
create policy airfnb_cross_tenant_policy on public.indigo_policy_collision_probe for select using (true);
SQL
policy_collision_before="$(scratch_fingerprint)"
if "${psql_scratch[@]}" --file="$rollback_file" >"$temporary_directory/policy-collision.log" 2>&1; then
  printf 'rollback accepted a cross-tenant policy collision\n' >&2; exit 1
fi
grep -Fq 'indigo baseline rollback refused: catalog drifted' "$temporary_directory/policy-collision.log" || { sed -n '1,100p' "$temporary_directory/policy-collision.log" >&2; exit 1; }
[[ "$(scratch_fingerprint)" == "$policy_collision_before" ]] || { printf 'policy-collision rollback failure was not atomic\n' >&2; exit 1; }
[[ "$("${psql_scratch[@]}" --tuples-only --no-align --command="select count(*) from pg_catalog.pg_policies where schemaname='public' and tablename='indigo_policy_collision_probe' and policyname='airfnb_cross_tenant_policy';")" == 1 ]] || { printf 'cross-tenant policy was removed\n' >&2; exit 1; }
"${psql_scratch[@]}" --command="drop table public.indigo_policy_collision_probe;" >/dev/null

"${psql_scratch[@]}" >/dev/null <<'SQL'
create table public.indigo_trigger_collision_probe(id bigint primary key);
create function public.indigo_trigger_collision_probe_fn()
returns trigger
language plpgsql
set search_path=pg_catalog
as $probe$
begin
  return new;
end
$probe$;
create trigger airfnbXcross_tenant_trigger before insert on public.indigo_trigger_collision_probe
for each row execute function public.indigo_trigger_collision_probe_fn();
SQL
trigger_collision_before="$(scratch_fingerprint)"
if "${psql_scratch[@]}" --file="$rollback_file" >"$temporary_directory/trigger-collision.log" 2>&1; then
  printf 'rollback accepted a cross-tenant trigger collision\n' >&2; exit 1
fi
grep -Fq 'indigo baseline rollback refused: catalog drifted' "$temporary_directory/trigger-collision.log" || { sed -n '1,100p' "$temporary_directory/trigger-collision.log" >&2; exit 1; }
[[ "$(scratch_fingerprint)" == "$trigger_collision_before" ]] || { printf 'trigger-collision rollback failure was not atomic\n' >&2; exit 1; }
[[ "$("${psql_scratch[@]}" --tuples-only --no-align --command="select count(*) from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid=t.tgrelid join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='indigo_trigger_collision_probe' and t.tgname='airfnbXcross_tenant_trigger' and not t.tgisinternal;")" == 1 ]] || { printf 'cross-tenant trigger was removed\n' >&2; exit 1; }
"${psql_scratch[@]}" --command="drop table public.indigo_trigger_collision_probe; drop function public.indigo_trigger_collision_probe_fn();" >/dev/null

"${psql_scratch[@]}" --command="update storage.buckets set file_size_limit=123 where id='airfnb-avatars';" >/dev/null
storage_tamper_before="$(scratch_fingerprint)"
if "${psql_scratch[@]}" --file="$candidate_migration" >"$temporary_directory/final-tamper.log" 2>&1; then
  printf 'drifted final state unexpectedly accepted\n' >&2; exit 1
fi
grep -Fq 'indigo baseline refused: F&B collision or final-state drift detected' "$temporary_directory/final-tamper.log" || { sed -n '1,100p' "$temporary_directory/final-tamper.log" >&2; exit 1; }
[[ "$(scratch_fingerprint)" == "$storage_tamper_before" ]] || { printf 'final-state tamper failure was not atomic\n' >&2; exit 1; }
if "${psql_scratch[@]}" --file="$rollback_file" >"$temporary_directory/storage-drift.log" 2>&1; then
  printf 'rollback accepted Storage drift\n' >&2; exit 1
fi
grep -Fq 'indigo baseline rollback refused: manifest, buckets, objects or jobs drifted' "$temporary_directory/storage-drift.log" || { sed -n '1,100p' "$temporary_directory/storage-drift.log" >&2; exit 1; }
[[ "$(scratch_fingerprint)" == "$storage_tamper_before" ]] || { printf 'Storage-drift rollback failure was not atomic\n' >&2; exit 1; }
"${psql_scratch[@]}" --command="update storage.buckets set file_size_limit=2097152 where id='airfnb-avatars';" >/dev/null

"${psql_scratch[@]}" --command="insert into storage.objects(bucket_id,name) values('airfnb-avatars','11111111-1111-4111-8111-111111111111/proof.png');" >/dev/null
object_tamper_before="$(scratch_fingerprint)"
if "${psql_scratch[@]}" --file="$rollback_file" >"$temporary_directory/storage-object.log" 2>&1; then
  printf 'rollback accepted a non-empty F&B bucket\n' >&2; exit 1
fi
grep -Fq 'indigo baseline rollback refused: manifest, buckets, objects or jobs drifted' "$temporary_directory/storage-object.log" || { sed -n '1,100p' "$temporary_directory/storage-object.log" >&2; exit 1; }
[[ "$(scratch_fingerprint)" == "$object_tamper_before" ]] || { printf 'Storage-object rollback failure was not atomic\n' >&2; exit 1; }
"${psql_scratch[@]}" --command="delete from storage.objects where bucket_id='airfnb-avatars';" >/dev/null

"${psql_scratch[@]}" --command="create view public.indigo_foreign_dependency as select id from public.airfnb_profiles;" >/dev/null
dependency_before="$(scratch_fingerprint)"
if "${psql_scratch[@]}" --file="$rollback_file" >"$temporary_directory/foreign-dependency.log" 2>&1; then
  printf 'rollback cascaded into a non-F&B dependency\n' >&2; exit 1
fi
grep -Fq 'cannot drop desired object' "$temporary_directory/foreign-dependency.log" || { sed -n '1,120p' "$temporary_directory/foreign-dependency.log" >&2; exit 1; }
[[ "$(scratch_fingerprint)" == "$dependency_before" ]] || { printf 'foreign-dependency rollback failure was not atomic\n' >&2; exit 1; }
"${psql_scratch[@]}" --command="drop view public.indigo_foreign_dependency;" >/dev/null

"${psql_scratch[@]}" --file="$rollback_file" >/dev/null
residue="$("${psql_scratch[@]}" --tuples-only --no-align --command="select (select count(*) from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname like 'airfnb_%')+(select count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'airfnb_%')+(select count(*) from storage.buckets where id like 'airfnb-%')+(select count(*) from cron.job where jobname like 'airfnb_%');")"
[[ "$residue" == 0 ]] || { printf 'F&B residue remains after rollback: %s\n' "$residue" >&2; exit 1; }
[[ "$("${psql_scratch[@]}" --tuples-only --no-align --command="select count(*)||':'||md5(string_agg(id::text||':'||coalesce(email,''),',' order by id)) from auth.users;")" == "$auth_before" ]] || { printf 'Auth identities changed\n' >&2; exit 1; }
[[ "$("${psql_scratch[@]}" --tuples-only --no-align --command="select count(*)||':'||max(version)||':'||md5(string_agg(version,',' order by version)) from supabase_migrations.schema_migrations;")" == "$history_before" ]] || { printf 'migration history changed\n' >&2; exit 1; }
[[ "$("${psql_scratch[@]}" --tuples-only --no-align --command="select count(*) from pg_catalog.pg_extension where extname in ('pgcrypto','pg_trgm','unaccent','postgis','pg_cron');")" == 5 ]] || { printf 'shared extensions changed during rollback\n' >&2; exit 1; }

[[ "$(source_fingerprint)" == "$source_fingerprint_before" ]] || { printf 'source fingerprint changed\n' >&2; exit 1; }
[[ "$(artifact_manifest)" == "$manifest_before" ]] || { printf 'source artifacts changed during driver\n' >&2; exit 1; }

printf 'indigo_shared_project_baseline: pg_trgm absent-to-extensions install, catalog/policy/trigger collisions fail-closed, apply/reapply, Storage refusal, selective rollback PASS\n'
printf 'Auth/history sentinels preserved; shared extensions intentionally remain; scratch cleanup enforced by EXIT trap\n'
