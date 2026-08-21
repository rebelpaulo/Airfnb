import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migrationPath =
  "supabase/migrations/20260820154104_catalog_service_types_reconciliation.sql";
const runtimePath = "tests/catalog-service-types-reconciliation-runtime.sql";
const driverPath = "scripts/test-catalog-service-types-reconciliation.sh";

const migration = readFileSync(migrationPath, "utf8");
const runtime = readFileSync(runtimePath, "utf8");
const driver = readFileSync(driverPath, "utf8");

test("migration is one guarded atomic forward reconciliation", () => {
  assert.match(migration, /^begin;/m);
  assert.match(migration, /set local lock_timeout = '5s'/);
  assert.match(migration, /set local statement_timeout = '30s'/);
  assert.match(migration, /mixed or unknown prestate/);
  assert.match(migration, /legacy.*old.*final/s);
  assert.match(migration, /protected function changed/);
  assert.match(migration, /trusted function body\/config\/ACL drifted/);
  assert.match(migration, /array\['search_path=""'\]::text\[\]/);
  assert.match(migration, /rating aggregate changed/);
  assert.match(migration, /commit;\s*$/);
  assert.doesNotMatch(migration, /drop table|truncate table/i);
});

test("storage dependency is pinned before base grants", () => {
  assert.match(migration, /982caee25d35d0ac9dfe1d3a343ab0a5/);
  assert.match(migration, /63f8f31bbf345d3075b489257b6fdea5/);
  assert.match(migration, /final Storage child policies differ/);
  assert.match(migration, /airfnb_truck_images_read/);
  assert.match(migration, /airfnb_menu_items_write/);
  assert.match(migration, /airfnb_truck_cat_write/);
  assert.ok(
    migration.indexOf("final Storage child policies differ") <
      migration.indexOf("grant select (\n    id, slug, name"),
  );
});

test("service type, index and 28-column view are exact", () => {
  assert.match(
    migration,
    /create type public\.airfnb_service_type as enum \('food_truck', 'catering', 'bar'\)/,
  );
  assert.match(migration, /not null default 'food_truck'/);
  assert.match(migration, /airfnb_trucks_active_service_type_idx/);
  assert.match(migration, /indexdef = 'CREATE INDEX airfnb_trucks_active_service_type_idx/);
  assert.match(migration, /with \(security_invoker = true\)/);
  assert.match(migration, /limit 6/);
  assert.match(migration, /ordered_image\.sort_order,\s+ordered_image\.url/);
  assert.match(migration, /image\.sort_order,\s+image\.url\s+limit 6/);
  assert.match(migration, /where truck_category\.truck_id = truck\.id\s+order by category\.slug/);
  assert.match(migration, /truck\.service_type\s+from/s);
  assert.match(migration, /5e17d15485c2be8af68157568ba84028/);
  assert.match(migration, /c3e262896aa919d75361132feff47380/);
});

test("moderation boundary and exact mutation allowlists are present", () => {
  assert.match(migration, /airfnb_trucks_owner_insert/);
  assert.match(migration, /airfnb_trucks_owner_update/);
  assert.match(migration, /tgtype = 23/);
  assert.match(migration, /9580d50b368d29269983025249704dda/);
  assert.match(migration, /new\.status is distinct from 'draft'/);
  assert.match(migration, /supplier ownership is immutable/);
  assert.match(migration, /supplier status transition is not allowed/);
  assert.match(migration, /revoke insert, update, delete on table public\.airfnb_trucks/);
  assert.match(migration, /grant insert \([\s\S]*service_type[\s\S]*\) on table public\.airfnb_trucks to authenticated/);
  assert.doesNotMatch(migration, /grant delete .*airfnb_trucks/i);
});

test("security-invoker base SELECT grants are column-scoped", () => {
  assert.match(
    migration,
    /grant select \(truck_id, url, kind, is_cover, sort_order\)[\s\S]*airfnb_truck_images/,
  );
  assert.match(
    migration,
    /grant select \(truck_id, category_id\)[\s\S]*airfnb_truck_categories/,
  );
  assert.match(migration, /grant select \(id, slug\)[\s\S]*airfnb_categories/);
  assert.match(migration, /broad final base SELECT remains/);
  assert.match(migration, /unexpected base SELECT grantee/);
  assert.doesNotMatch(
    migration,
    /grant select on table public\.airfnb_(trucks|truck_images|truck_categories|categories)/i,
  );
});

test("runtime proves both prestates, role matrix and rating compatibility", () => {
  assert.match(runtime, /privacy-final is_admin contract differs/);
  assert.match(runtime, /reconstruct_legacy/);
  assert.match(runtime, /assert_pre_legacy/);
  assert.match(runtime, /assert_pre_old/);
  assert.match(runtime, /set local role anon/);
  assert.match(runtime, /set local role authenticated/);
  assert.match(runtime, /set local role service_role/);
  assert.match(runtime, /forged_admin_claim_no_effect/);
  assert.match(runtime, /admin_approve_rpc/);
  assert.match(runtime, /staff_approve_rpc/);
  assert.match(runtime, /anon_gallery_limit/);
  assert.match(runtime, /anon_gallery_tie_order/);
  assert.match(runtime, /anon_category_order/);
  assert.match(runtime, /rating_trigger_compatibility/);
  assert.match(runtime, /rollback;\s*\\endif\s*$/);
});

test("driver is guarded, two-prestate, drift-aware and source-immutable", () => {
  assert.match(driver, /trap cleanup EXIT INT TERM/);
  assert.ok(
    driver.indexOf("trap cleanup EXIT INT TERM") <
      driver.indexOf("for prestate in legacy old"),
  );
  assert.ok(
    driver.indexOf("for prestate in legacy old") <
      driver.indexOf("createdb --host"),
  );
  assert.match(driver, /default_transaction_read_only=on/);
  assert.match(driver, /20260820152018_airfnb_runtime_function_integrity_reconciliation\.sql/);
  assert.match(driver, /20260820153725_public_event_request_privacy_reconciliation\.sql/);
  assert.ok(
    driver.indexOf('"$runtime_integrity_file" "$privacy_file" "$messaging_file" "$storage_file"') <
      driver.indexOf('"${psql_scratch[@]}" --file="$predecessor_file"'),
  );
  assert.match(driver, /source_sha256_before/);
  assert.match(driver, /source_sha256_after/);
  assert.match(driver, /intentional catalog reconciliation rollback proof/);
  assert.match(driver, /SAME_NAME_POLICY_DRIFT_REJECTED/);
  assert.match(driver, /COLUMN_ACL_DRIFT_REJECTED/);
  assert.match(driver, /LEGACY_VIEW_DEFINITION_DRIFT_REJECTED/);
  assert.match(driver, /legacy view drift hash changed during refused migration/);
  assert.match(driver, /VIEW_SEMANTIC_DRIFT_REJECTED/);
  assert.match(driver, /GOOD_APPLY_REAPPLY_VERIFIED/);
  assert.match(driver, /SCRATCH_RESIDUE=0/);
});

test("artifacts contain no live, linked, credential or unrelated edits", () => {
  for (const artifact of [migration, runtime, driver]) {
    assert.doesNotMatch(artifact, /supabase\s+(db push|migration repair|link)/i);
    assert.doesNotMatch(artifact, /project-ref|access-token|service_role_key/i);
    assert.doesNotMatch(artifact, /https:\/\//i);
  }
  assert.doesNotMatch(driver, /types\/database|app\/|package\.json|pnpm-lock/);
});
