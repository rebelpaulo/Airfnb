import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const migrationPath = new URL('../scripts/migrations/apply/20260821124724_indigo_shared_project_baseline.sql', import.meta.url)
const rollbackPath = new URL('../scripts/migrations/rollback/20260821124724_indigo_shared_project_baseline.sql', import.meta.url)
const driverPath = new URL('../scripts/test-indigo-shared-project-baseline.sh', import.meta.url)
const runtimePath = new URL('./indigo-shared-project-baseline-runtime.sql', import.meta.url)
const runbookPath = new URL('../supabase/INDIGO_SHARED_PROJECT_MIGRATION_RUNBOOK.md', import.meta.url)

const [migration, rollback, driver, runtime, runbook] = await Promise.all([
  readFile(migrationPath, 'utf8'),
  readFile(rollbackPath, 'utf8'),
  readFile(driverPath, 'utf8'),
  readFile(runtimePath, 'utf8'),
  readFile(runbookPath, 'utf8'),
])

test('pins the exact Indigo predecessor before durable writes', () => {
  assert.match(migration, /deliberately outside[\s\S]*must never be applied by supabase db push/i)
  assert.match(migration, /v_history_count <> 85/)
  assert.match(migration, /v_history_latest is distinct from '20260821171040'/)
  assert.match(migration, /v_history_hash is distinct from '1f0eebdf3bcee57d873c3d4f87f260a9'/)
  assert.match(runbook, /permanece nas 85 versões Indigo/)
  assert.match(runbook, /as mesmas 85 versões Indigo/)
  assert.doesNotMatch(runbook, /\b82 versões Indigo\b/)
  assert.match(migration, /set local check_function_bodies = off;/)
  assert.ok(migration.indexOf("pg_catalog.hashtext('airfnb-indigo-baseline-installer')") < migration.indexOf('do $preflight$'))
  assert.ok(rollback.indexOf("pg_catalog.hashtext('airfnb-indigo-baseline-installer')") < rollback.indexOf('do $preflight$'))
  assert.equal((migration.match(/pg_catalog\.hashtext\('airfnb-indigo-baseline-installer'\)/g) ?? []).length, 1)
  assert.equal((rollback.match(/pg_catalog\.hashtext\('airfnb-indigo-baseline-installer'\)/g) ?? []).length, 1)
  assert.match(migration, /lock table supabase_migrations\.schema_migrations in share mode;/)
  assert.match(rollback, /lock table supabase_migrations\.schema_migrations in share mode;/)
  assert.ok(migration.indexOf('do $preflight$') < migration.indexOf("create extension if not exists pg_trgm"))
  assert.ok(migration.indexOf("create extension if not exists pg_cron") < migration.indexOf("pg_catalog.hashtext('airfnb-indigo-cron-catalog')"))
  assert.doesNotMatch(migration + rollback, /lock table cron\.job/i)
  assert.equal((migration.match(/pg_catalog\.hashtext\('airfnb-indigo-cron-catalog'\)/g) ?? []).length, 1)
  assert.equal((rollback.match(/pg_catalog\.hashtext\('airfnb-indigo-cron-catalog'\)/g) ?? []).length, 1)
  assert.match(migration, /create extension if not exists pg_trgm with schema extensions/)
  assert.match(migration, /create extension if not exists unaccent with schema extensions/)
  assert.match(migration, /create extension if not exists postgis with schema extensions/)
  assert.match(migration, /base_city extensions\.gin_trgm_ops/)
  assert.doesNotMatch(migration, /\bpublic\.gin_trgm_ops\b/)
  assert.match(runtime, /operator_namespace\.nspname='extensions'/)
  assert.match(runtime, /operator_class\.opcname='gin_trgm_ops'/)
  assert.equal((migration.match(/^begin;$/gm) ?? []).length, 1)
  assert.equal((migration.match(/^commit;$/gm) ?? []).length, 1)
})

test('installs only namespaced F&B objects and never imports or triggers Auth users', () => {
  assert.equal(/\b(?:insert\s+into|update|delete\s+from)\s+auth\.users\b/i.test(migration), false)
  assert.equal(/create\s+trigger[\s\S]{0,300}\bon\s+auth\.users\b/i.test(migration), false)
  assert.match(migration, /tgrelid='auth\.users'::pg_catalog\.regclass[\s\S]*tgname like 'airfnb_%'/)
  assert.match(migration, /CREATE TYPE public\.airfnb_user_role/)
  assert.match(migration, /CREATE TABLE public\.airfnb_profiles/)
  assert.match(migration, /CREATE TABLE public\.airfnb_membership_tombstones/)
  assert.match(migration, /CREATE FUNCTION public\.airfnb_ensure_profile/)
  assert.equal(/^CREATE (?:TYPE|FUNCTION|TABLE|VIEW) public\.(?!airfnb_)/m.test(migration), false)
  assert.equal((migration.match(/CREATE TYPE public\.airfnb_/g) ?? []).length, 24)
  assert.equal((migration.match(/CREATE FUNCTION public\.airfnb_/g) ?? []).length, 68)
  assert.equal((migration.match(/CREATE TABLE public\.airfnb_/g) ?? []).length, 42)
})

test('seals and revalidates the exact installed catalogue', () => {
  assert.match(migration, /v_public_relations <> 169/)
  assert.match(migration, /v_public_functions <> 68/)
  assert.match(migration, /catalog_hash text not null/)
  assert.match(migration, /storage_hash text not null/)
  assert.match(migration, /seed_count bigint not null/)
  assert.match(migration, /seed_hash text not null/)
  assert.match(migration, /v_actual_seed_count <> 101/)
  assert.match(migration, /v_expected_seed_hash is distinct from v_actual_seed_hash/)
  assert.ok((migration.match(/string_agg\(entry, E'\\n' order by entry\)/g) ?? []).length >= 4)
  assert.match(migration, /v_expected_catalog_hash is distinct from v_actual_catalog_hash/)
  assert.match(migration, /v_expected_storage_hash is distinct from v_actual_storage_hash/)
  assert.match(runtime, /exact_manifest_counts_ok/)
  assert.match(runtime, /sealed_manifest_and_auth_boundary_ok/)
  assert.match(runtime, /exact_membership_tombstone_boundary_ok/)
  assert.match(runtime, /exact_seed_counts_ok/)
  assert.match(runtime, /exact_destination_acl_hardening_ok/)
  assert.match(runtime, /\) = 104/)
})

test('neutralizes destination default privileges before sealing', () => {
  const hardening = migration.match(/do \$acl_hardening\$[\s\S]*?\$acl_hardening\$;/)?.[0]
  assert.ok(hardening)
  assert.match(migration, /v_expected_catalog_hash = 'c7587da9523bd65c2f30e24073c76eac'/)
  assert.match(migration, /airfnb\.baseline_mode', 'harden'/)
  assert.match(hardening, /alter table public\.airfnb_baseline_manifest enable row level security/)
  assert.match(hardening, /revoke all on table public\.airfnb_baseline_manifest[\s\S]*from public, anon, authenticated, service_role/)
  assert.match(hardening, /revoke all on function %s from public, anon, authenticated, service_role/)
  assert.match(hardening, /grant execute on function %s to %I/)
  assert.match(hardening, /airfnb_make_ics_token\(\) set search_path = pg_catalog, public, extensions/)
  assert.match(migration, /r\.rolname='anon'\) <> 7/)
  assert.match(migration, /r\.rolname='authenticated'\) <> 43/)
  assert.match(migration, /r\.rolname='service_role'\) <> 11/)
  assert.match(migration, /acl\.grantee=0/)
  assert.match(runbook, /DEFAULT PRIVILEGES/)
  assert.match(runbook, /7.*43.*11/)
})

test('membership deletion is tombstoned, private, and preserves Supabase Auth', () => {
  assert.match(migration, /ALTER TABLE public\.airfnb_membership_tombstones ENABLE ROW LEVEL SECURITY/)
  assert.match(migration, /REVOKE ALL ON TABLE public\.airfnb_membership_tombstones FROM PUBLIC, anon, authenticated, service_role/)
  assert.doesNotMatch(migration, /CREATE POLICY[\s\S]{0,300}ON public\.airfnb_membership_tombstones/i)
  assert.match(migration, /storage_truck_ids uuid\[\] DEFAULT '\{\}'::uuid\[\] NOT NULL/)
  assert.match(migration, /CREATE FUNCTION public\.airfnb_self_delete\(\) RETURNS void/)
  assert.match(migration, /CREATE FUNCTION public\.airfnb_self_delete_storage_prefixes\(\) RETURNS uuid\[\]/)
  assert.match(migration, /insert into public\.airfnb_membership_tombstones \(user_id, storage_truck_ids\)/)
  assert.match(migration, /not exists \([\s\S]{0,150}select 1 from auth\.users where id = v_actor/)
  assert.equal(/\bdelete\s+from\s+auth\.users\b/i.test(migration), false)
  assert.match(runtime, /exact_membership_tombstone_boundary_ok/)
})

test('rollback is F&B-selective and fail-closed for catalogue and Storage drift', () => {
  assert.equal(/\bcascade\b/i.test(rollback), false)
  assert.match(rollback, /exists \(select 1 from storage\.objects where bucket_id like 'airfnb-%'\)/)
  assert.match(rollback, /pg_catalog\.set_config\('storage\.allow_delete_query','true',true\)/)
  assert.equal(/delete\s+from\s+storage\.objects/i.test(rollback), false)
  assert.match(rollback, /v_actual_storage_hash is distinct from v_expected_storage_hash/)
  assert.match(rollback, /v_actual_catalog_hash is distinct from v_expected_catalog_hash/)
  assert.match(rollback, /into strict v_expected_catalog_hash,v_expected_storage_hash/)
  const migrationManifestEntries = migration.match(/select pg_catalog\.jsonb_build_array\('relation'[\s\S]*?\) manifest_entries;/)?.[0]
  const rollbackManifestEntries = rollback.match(/select pg_catalog\.jsonb_build_array\('relation'[\s\S]*?\) manifest_entries;/)?.[0]
  assert.ok(migrationManifestEntries)
  assert.equal(rollbackManifestEntries, migrationManifestEntries)
  const relationControls = rollback.match(/do \$drop_public_relation_controls\$[\s\S]*?\$drop_public_relation_controls\$;/)?.[0]
  assert.ok(relationControls)
  assert.match(relationControls, /tablename::text=any\(v_owned_public_tables\)/)
  assert.match(relationControls, /c\.relname::text=any\(v_owned_public_tables\)/)
  assert.doesNotMatch(relationControls, /(?:policyname|tgname)\s+like/i)
  assert.equal((rollback.match(/'airfnb_membership_tombstones'/g) ?? []).length, 2)
  assert.match(rollback, /drop table [^;]*public\.airfnb_membership_tombstones[^;]*public\.airfnb_baseline_manifest;/)
  assert.match(rollback, /drop function if exists [^;]*public\.airfnb_self_delete\(\), public\.airfnb_self_delete_storage_prefixes\(\)[^;]*;/)
  const installedFunctionNames = [...migration.matchAll(/CREATE FUNCTION public\.(airfnb_[a-z0-9_]+)\(/g)]
    .map((match) => match[1]).sort()
  const dropFunctions = rollback.match(/drop function if exists [^;]+;/)?.[0] ?? ''
  const rollbackFunctionNames = [...dropFunctions.matchAll(/public\.(airfnb_[a-z0-9_]+)\(/g)]
    .map((match) => match[1]).sort()
  assert.deepEqual(rollbackFunctionNames, installedFunctionNames)
  assert.match(rollback, /shared extension capability changed/)
  assert.equal(/drop\s+extension/i.test(rollback), false)
  assert.equal(/(?:delete\s+from|update|drop\s+table)\s+auth\./i.test(rollback), false)
})

test('driver proves atomic tamper refusal, idempotence, selective rollback, and immutable source', () => {
  for (const marker of [
    'predecessor tamper failure was not atomic',
    'final-state tamper failure was not atomic',
    'rollback accepted Storage drift',
    'rollback accepted a non-empty F&B bucket',
    'rollback cascaded into a non-F&B dependency',
    'rollback accepted a cross-tenant policy collision',
    'policy-collision rollback failure was not atomic',
    'cross-tenant policy was removed',
    'rollback accepted a cross-tenant trigger collision',
    'trigger-collision rollback failure was not atomic',
    'cross-tenant trigger was removed',
    'reapply changed final state',
    'Auth identities changed',
    'migration history changed',
    'source fingerprint changed',
    'source artifacts changed during driver',
    'source predecessor unexpectedly has pg_trgm installed',
    'seed %s failure was not atomic',
    'assert_seed_drift_refused removal',
    'assert_seed_drift_refused alteration',
    'assert_seed_drift_refused addition',
  ]) assert.ok(driver.includes(marker), marker)
  assert.match(driver, /trap cleanup EXIT INT TERM/)
})

test('runbook forbids historical db push and covers the full operator lifecycle', () => {
  assert.match(runbook, /tzwpezkbljqkgnzhazeo/)
  assert.match(runbook, /20260821171040/)
  assert.match(runbook, /1f0eebdf3bcee57d873c3d4f87f260a9/)
  assert.match(runbook, /pg_dump/)
  assert.match(runbook, /ON_ERROR_STOP/)
  assert.match(runbook, /rollback/i)
  assert.match(runbook, /STOP/)
  assert.match(runbook, /não usar `supabase db push`/i)
  assert.match(runbook, /169 relações/)
  assert.match(runbook, /catalog_hash/)
  assert.match(runbook, /airfnb_membership_tombstones/)
  assert.match(runbook, /marcador de eliminação/i)
  assert.match(runbook, /Auth/i)
})
