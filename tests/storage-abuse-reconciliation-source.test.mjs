import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const ROOT = new URL("../", import.meta.url);
const read = (relativePath) => readFileSync(new URL(relativePath, ROOT), "utf8");

const migration = read("supabase/migrations/20260820154100_storage_abuse_reconciliation.sql");
const runtime = read("tests/storage-abuse-reconciliation-runtime.sql");
const driver = read("scripts/test-storage-abuse-reconciliation.sh");
const rateLimit = read("lib/public-rate-limit.ts");
const partnerLeads = read("lib/partner-leads.ts");
const newsletter = read("app/api/newsletter/route.ts");
const databaseTypes = read("types/database.ts");

test("migration is one guarded atomic forward reconciliation", () => {
  assert.match(migration, /^begin;$/mu);
  assert.match(migration, /^commit;$/mu);
  assert.match(migration, /mixed or unknown prestate/u);
  assert.match(migration, /historical/u);
  assert.match(migration, /old_candidate/u);
  assert.match(migration, /v_final/u);
  assert.match(migration, /shape drifted/u);
  assert.match(migration, /trusted owner alignment drifted/u);
  assert.match(migration, /malformed scoped object path exists/u);
  assert.match(migration, /catalog base ACL changed/u);
  assert.doesNotMatch(
    migration,
    /grant select[^;]*(?:airfnb_trucks|airfnb_truck_images|airfnb_menu_items|airfnb_truck_categories)[^;]*to (?:anon|authenticated)/iu,
  );
});

test("bucket limits and public/private catalog are exact", () => {
  for (const bucket of [
    "airfnb-truck-images",
    "airfnb-menu-images",
    "airfnb-blog-images",
    "airfnb-avatars",
  ]) {
    assert.match(
      migration,
      new RegExp(`\\('${bucket}', true, 2097152::bigint`, "u"),
    );
  }
  assert.match(
    migration,
    /\('airfnb-documents', false, 8388608::bigint, array\['application\/pdf'\]::text\[\]\)/u,
  );
  assert.match(migration, /array\['image\/jpeg','image\/png','image\/webp'\]::text\[\]/u);
});

test("child and Storage policies enforce active/owner/admin and scoped paths", () => {
  assert.match(migration, /airfnb_can_manage_truck\(p_truck_text text\)[\s\S]*security definer[\s\S]*set search_path = ''/u);
  assert.match(migration, /truck\.owner_id = \(select auth\.uid\(\)\)[\s\S]*public\.airfnb_is_admin\(\)/u);
  assert.match(migration, /airfnb_can_read_truck_child\(p_truck_text text\)[\s\S]*truck\.status = 'active'/u);
  assert.match(migration, /p_truck_text !~ '\^\[0-9a-fA-F\]/u);
  for (const table of ["airfnb_truck_images", "airfnb_menu_items", "airfnb_truck_categories"]) {
    assert.match(
      migration,
      new RegExp(`on public\\.${table} for select to anon, authenticated[\\s\\S]{0,160}airfnb_can_read_truck_child`, "u"),
    );
    assert.match(
      migration,
      new RegExp(`on public\\.${table} for all to authenticated[\\s\\S]{0,220}using \\(public\\.airfnb_can_manage_truck[\\s\\S]{0,180}with check \\(public\\.airfnb_can_manage_truck`, "u"),
    );
  }
  assert.match(migration, /airfnb_avatars_owner_insert[\s\S]*split_part\(name, '\/', 1\) = auth\.uid\(\)::text/u);
  assert.match(migration, /airfnb_documents_owner_read[\s\S]*airfnb_can_manage_truck/u);
  for (const [policy, command] of [
    ["airfnb_avatars_public_read", "r"],
    ["airfnb_avatars_owner_insert", "a"],
    ["airfnb_avatars_owner_update", "w"],
    ["airfnb_avatars_owner_delete", "d"],
    ["airfnb_truck_images_public_read", "r"],
    ["airfnb_truck_images_owner_insert", "a"],
    ["airfnb_truck_images_owner_update", "w"],
    ["airfnb_truck_images_owner_delete", "d"],
    ["airfnb_documents_owner_read", "r"],
    ["airfnb_documents_owner_insert", "a"],
    ["airfnb_documents_owner_update", "w"],
    ["airfnb_documents_owner_delete", "d"],
  ]) {
    assert.match(migration, new RegExp(`\\('${policy}', '${command}', array\\[`, "u"));
  }
  assert.match(migration, /as expected\(policy_name, command, roles, using_expression, check_expression\)[\s\S]*policy\.polpermissive[\s\S]*policy\.polcmd::text = expected\.command[\s\S]*policy\.polroles = expected\.roles/u);
  assert.match(migration, /pg_catalog\.pg_get_expr\(policy\.polqual, policy\.polrelid\)[\s\S]*is not distinct from expected\.using_expression/u);
  assert.match(migration, /pg_catalog\.pg_get_expr\(policy\.polwithcheck, policy\.polrelid\)[\s\S]*is not distinct from expected\.check_expression/u);
  assert.match(migration, /\(bucket_id = 'airfnb-documents'::text\)[\s\S]*name ~ '\^\[0-9a-fA-F\][\s\S]*airfnb_can_manage_truck\(split_part\(name, '\/'::text, 1\)\)/u);
  assert.doesNotMatch(migration, /create policy "?airfnb_(?:menu|blog)_images_.*(?:insert|update|delete)/iu);
});

test("rate-limit state is RPC-only, validated, saturating and pruned", () => {
  assert.match(migration, /revoke all on table public\.airfnb_rate_limits[\s\S]*from public, anon, authenticated, service_role/u);
  assert.match(migration, /grant execute on function public\.airfnb_check_rate_limit[\s\S]*to service_role/u);
  assert.match(migration, /p_action !~ '\^\[a-z\]\[a-z0-9_\]\{0,63\}\$'/u);
  assert.match(migration, /p_bucket !~ '\^\[A-Za-z0-9\]\[A-Za-z0-9:_-\]\{0,159\}\$'/u);
  assert.match(migration, /p_limit_per_window > 10000/u);
  assert.match(migration, /p_window_seconds > 2678400/u);
  assert.match(migration, /2147483647::bigint/u);
  assert.match(migration, /window_at <= v_now/u);
  assert.match(migration, /delete from public\.airfnb_rate_limits/u);
  assert.match(migration, /airfnb_rate_limits_window_at_idx/u);
  assert.match(migration, /pg_catalog\.pg_get_constraintdef\(constraint_record\.oid\) = expected\.definition/u);
  assert.match(migration, /CHECK \(\(action ~ ''\^\[a-z\]\[a-z0-9_\]\{0,63\}\$''::text\)\)/u);
  assert.match(migration, /pg_catalog\.pg_get_indexdef\(index_record\.indexrelid\) = expected\.definition/u);
  assert.match(migration, /CREATE INDEX airfnb_rate_limits_window_at_idx ON public\.airfnb_rate_limits USING btree \(window_at\)/u);
  assert.doesNotMatch(migration, /create index if not exists airfnb_rate_limits_window_at_idx/iu);
});

test("public ingestion is service-role-only and callers fail closed with HMAC buckets", () => {
  for (const table of [
    "airfnb_partner_leads",
    "airfnb_newsletter_subs",
    "airfnb_newsletter_subscribers",
    "airfnb_contact_requests",
  ]) {
    assert.match(
      migration,
      new RegExp(`revoke insert on table public\\.${table}[\\s\\S]{0,80}from public, anon, authenticated`, "u"),
    );
  }
  assert.match(rateLimit, /^import "server-only";$/mu);
  assert.match(rateLimit, /createHmac\("sha256", rateLimitSecret\(\)\)/u);
  assert.match(rateLimit, /fb-tailor-public-rate-limit\\0\$\{kind\}\\0\$\{normalized\}/u);
  assert.match(rateLimit, /throw new PublicRateLimitError\("unavailable"\)/u);
  assert.doesNotMatch(rateLimit, /\bas any\b/u);
  assert.doesNotMatch(partnerLeads, /\bas any\b/u);
  assert.doesNotMatch(newsletter, /\bas any\b/u);
  assert.match(partnerLeads, /supabaseAdmin\(\)[\s\S]*\.from\("airfnb_partner_leads"\)/u);
  assert.match(newsletter, /supa\.from\("airfnb_newsletter_subs"\)/u);
  assert.match(partnerLeads, /console\.warn\("partner-lead email dispatch failed"\);/u);
  assert.doesNotMatch(partnerLeads, /console\.(?:warn|error)\([^)]*,/u);
  assert.doesNotMatch(newsletter, /console\.error\([^\n]*email/iu);
});

test("database types cover the exact RPC and trusted ingestion callers", () => {
  assert.match(databaseTypes, /airfnb_check_rate_limit:[\s\S]*p_action: string;[\s\S]*p_bucket: string;[\s\S]*Returns: boolean;/u);
  assert.match(databaseTypes, /airfnb_partner_leads:[\s\S]*kind: Database\["public"\]\["Enums"\]\["airfnb_partner_lead_kind"\]/u);
  assert.match(databaseTypes, /airfnb_newsletter_subs:[\s\S]*email: string[\s\S]*source: string \| null/u);
  assert.match(databaseTypes, /airfnb_partner_lead_kind: "venues" \| "guest_mgmt" \| "music" \| "marketing"/u);
});

test("driver proves both prestates, rollback, drift rejection and source immutability", () => {
  for (const fragment of [
    "--socket", "--port", "--source-db", "source_fingerprint",
    "SOURCE_SHA256_BEFORE", "SOURCE_SHA256_AFTER", "MIGRATION_SHA256",
    "for prestate in historical old", "PRE_FIX_REPRODUCED",
    "INTENTIONAL_FAILURE_ROLLBACK_VERIFIED", "INJECTED_DRIFT_REJECTED",
    "SAME_NAME_STORAGE_POLICY_DRIFT_REJECTED",
    "SAME_NAME_RATE_CONSTRAINT_DRIFT_REJECTED",
    "SAME_NAME_RATE_INDEX_DRIFT_REJECTED",
    "GOOD_APPLY_REAPPLY_VERIFIED", "SCRATCH_RESIDUE",
    "catalog_acl_sha256", "migration changed catalog table or column ACLs",
  ]) {
    assert.ok(driver.includes(fragment), `driver missing ${fragment}`);
  }
  for (const role of ["anon", "authenticated", "service_role", "owner", "admin", "unrelated"]) {
    assert.match(runtime + driver, new RegExp(role, "u"));
  }
  for (const proof of ["storage_reset_probe", "storage_saturation_probe", "storage_prune_stale", "malformed_storage_path", "menu_storage_write", "blog_storage_write"]) {
    assert.match(runtime + driver, new RegExp(proof, "u"));
  }
  assert.match(runtime, /pg_catalog\.aclexplode\(attribute\.attacl\)/u);
  assert.match(runtime, /acl\.privilege_type = 'SELECT'/u);
  assert.match(driver, /alter policy airfnb_documents_owner_delete[\s\S]*using \(true\)/u);
  assert.match(driver, /add constraint airfnb_rate_limits_action_format check \(true\)/u);
  assert.match(driver, /airfnb_rate_limits_window_at_idx[\s\S]*airfnb_rate_limits \(count\)/u);
  for (const proof of [
    "same-name Storage policy rejection changed target state",
    "same-name constraint rejection changed target state",
    "same-name index rejection changed target state",
  ]) {
    assert.ok(driver.includes(proof), `driver missing rollback proof ${proof}`);
  }
});

test("verification artifacts contain no live, linked, credential or checkout-specific command", () => {
  const joined = [migration, runtime, driver].join("\n");
  assert.doesNotMatch(joined, /\/Users\//u);
  assert.doesNotMatch(joined, /https?:\/\//iu);
  assert.doesNotMatch(joined, /\bsupabase\s+(?:link|db|migration|functions)\b/iu);
  assert.doesNotMatch(joined, /--linked\b/iu);
  assert.doesNotMatch(joined, /(?:service_role|postgres(?:ql)?:\/\/)[^\n]{0,24}(?:key|password|secret|token|@)/iu);
});
