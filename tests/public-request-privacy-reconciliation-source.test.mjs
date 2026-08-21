import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migrationPath = new URL(
  "../supabase/migrations/20260820153725_public_event_request_privacy_reconciliation.sql",
  import.meta.url,
);
const runtimePath = new URL(
  "./public-request-privacy-reconciliation-runtime.sql",
  import.meta.url,
);
const driverPath = new URL(
  "../scripts/test-public-request-privacy-reconciliation.sh",
  import.meta.url,
);
const typesPath = new URL("../types/database.ts", import.meta.url);
const historicalMatchPath = new URL(
  "../supabase/migrations/20260524134351_airfnb_11_fix_function_security.sql",
  import.meta.url,
);
const oldPrivacyPath = new URL(
  "../supabase/migrations/20260818191533_public_data_privacy.sql",
  import.meta.url,
);

const [migration, runtime, driver, databaseTypes, historicalMatch, oldPrivacy] =
  await Promise.all([
    readFile(migrationPath, "utf8"),
    readFile(runtimePath, "utf8"),
    readFile(driverPath, "utf8"),
    readFile(typesPath, "utf8"),
    readFile(historicalMatchPath, "utf8"),
    readFile(oldPrivacyPath, "utf8"),
  ]);

const anonColumns = [
  "id", "title", "kind", "description", "start_at", "city",
  "expected_pax", "slots_needed", "budget_min", "budget_max", "status",
  "visibility", "accepted_deal_types", "min_fixed_fee",
  "min_revenue_share_pct",
];

const authenticatedColumns = [
  "id", "organizer_id", "title", "kind", "description", "start_at",
  "end_at", "city", "expected_pax", "slots_needed", "budget_min",
  "budget_max", "desired_categories", "dietary_requirements",
  "applications_deadline", "power_available", "notes", "status",
  "visibility", "created_at", "discovery_mode", "accepted_deal_types",
  "min_fixed_fee", "min_revenue_share_pct", "locality", "desired_cuisines",
  "setup_minutes", "energy_need", "energy_assistance", "sanitation_level",
];

function grantedColumns(role) {
  const grants = [...migration.matchAll(
    /grant select \(([\s\S]*?)\) on table public\.airfnb_event_requests to (anon|authenticated);/gu,
  )];
  const match = grants.find((grant) => grant[2] === role);
  assert.ok(match, `missing ${role} event-request grant`);
  return match[1].split(",").map((column) => column.trim()).filter(Boolean);
}

test("migration is one bounded fail-closed forward reconciliation", () => {
  assert.equal((migration.match(/^begin;$/gmu) ?? []).length, 1);
  assert.equal((migration.match(/^commit;$/gmu) ?? []).length, 1);
  assert.match(migration, /set local lock_timeout = '5s';/u);
  assert.match(migration, /set local statement_timeout = '30s';/u);
  assert.match(migration, /expected exact 50-column event-request shape/u);
  assert.match(migration, /four-policy row semantics drifted/u);
  assert.match(migration, /table\/helper owner drifted/u);
  assert.match(migration, /unsupported table SELECT prestate/u);
  assert.match(
    migration,
    /procedure\.oid = pg_catalog\.to_regprocedure\(\s*'public\.airfnb_match_category_availability_score\(uuid,uuid\)'\s*\)/u,
  );
  for (const prestate of ["broad_preprivacy", "old_candidate", "reconciled"]) {
    assert.ok(migration.includes(`'${prestate}'`), `missing ${prestate}`);
  }
  assert.doesNotMatch(migration, /\bdrop\s+(?:table|policy|function)\b/iu);
  assert.doesNotMatch(migration, /\bowner\s+to\b/iu);
});

test("the old boundary is pinned and match_score contains no composite load", () => {
  assert.equal((historicalMatch.match(/select \* into/gu) ?? []).length, 2);
  assert.equal((oldPrivacy.match(/contact_(?:name|email|phone)/gu) ?? []).length, 3);
  const replacementStart = migration.lastIndexOf(
    "create or replace function public.airfnb_match_score",
  );
  const replacementEnd = migration.indexOf(
    "alter function public.airfnb_match_scores_batch",
    replacementStart,
  );
  const replacement = migration.slice(replacementStart, replacementEnd);
  assert.doesNotMatch(replacement, /select\s+\*/iu);
  for (const fragment of [
    "truck.id", "truck.base_city", "truck.capacity", "truck.rating_avg",
    "truck.featured", "truck.base_price", "request_row.id",
    "request_row.status", "request_row.desired_categories", "request_row.city",
    "request_row.expected_pax", "request_row.start_at", "request_row.budget_max",
    "if not found then", "return 0;", "security invoker", "stable",
    "set search_path = ''",
    "public.airfnb_match_category_availability_score(t.id, r.id)",
  ]) {
    assert.ok(replacement.includes(fragment), `match projection missing ${fragment}`);
  }
  assert.doesNotMatch(replacement, /public\.airfnb_truck_(?:categories|availability)/u);
});

test("the scalar definer exposes only authorized combined matching context", () => {
  const helperStart = migration.indexOf(
    "create or replace function public.airfnb_match_category_availability_score",
  );
  const helperEnd = migration.indexOf(
    "create or replace function public.airfnb_match_score",
    helperStart,
  );
  const helper = migration.slice(helperStart, helperEnd);
  assert.ok(helperStart >= 0 && helperEnd > helperStart);
  for (const fragment of [
    "returns numeric", "language sql", "stable", "security definer",
    "set search_path = ''", "auth.uid() is not null",
    "truck.status = 'active'", "request_row.status in ('open', 'reviewing')",
    "request_row.visibility = 'public'", "request_row.organizer_id = auth.uid()",
    "profile.role in ('admin', 'staff')", "invited_truck.owner_id = auth.uid()",
    "public.airfnb_truck_categories", "public.airfnb_truck_availability",
    "availability.status in ('blocked', 'booked')", "), 0)::numeric",
  ]) {
    assert.ok(helper.includes(fragment), `scalar helper missing ${fragment}`);
  }
});

test("table and function ACLs are narrowed exactly", () => {
  assert.deepEqual(grantedColumns("anon"), anonColumns);
  assert.deepEqual(grantedColumns("authenticated"), authenticatedColumns);
  assert.match(
    migration,
    /revoke select on table public\.airfnb_event_requests\s+from public, anon, authenticated;/u,
  );
  assert.match(
    migration,
    /grant select on table public\.airfnb_event_requests to service_role;/u,
  );
  for (const dependency of ["airfnb_truck_categories", "airfnb_truck_availability"]) {
    assert.match(
      migration,
      new RegExp(
        `revoke select on table public\\.${dependency}\\s+from public, anon, authenticated;`,
        "u",
      ),
    );
    assert.doesNotMatch(
      migration,
      new RegExp(`grant select[^;]*public\\.${dependency}[^;]*to (?:anon|authenticated)`, "iu"),
    );
  }
  for (const pii of [
    "contact_name", "contact_email", "contact_phone", "address_line", "address_id",
  ]) {
    assert.ok(!anonColumns.includes(pii));
    assert.ok(!authenticatedColumns.includes(pii));
    assert.match(migration, new RegExp(`\\b${pii}\\b`, "u"));
  }

  for (const rpc of [
    "airfnb_match_score\\(uuid, uuid\\)",
    "airfnb_match_scores_batch\\(uuid\\[\\], uuid\\[\\]\\)",
    "airfnb_find_matching_requests\\(uuid, integer\\)",
    "airfnb_find_matching_trucks\\(uuid, integer\\)",
    "airfnb_recommend_trucks_for_request\\(uuid, integer\\)",
  ]) {
    assert.match(migration, new RegExp(`revoke execute on function public\\.${rpc}`, "u"));
    assert.match(migration, new RegExp(`grant execute on function public\\.${rpc}`, "u"));
  }
  assert.match(
    migration,
    /revoke execute on function public\.airfnb_match_category_availability_score\(uuid, uuid\)[\s\S]*?from public, anon, authenticated, service_role;/u,
  );
  assert.match(
    migration,
    /grant execute on function public\.airfnb_match_category_availability_score\(uuid, uuid\)[\s\S]*?to authenticated;/u,
  );
  assert.match(migration, /to anon, authenticated;/u);
  assert.match(migration, /to anon, authenticated, service_role;/u);
  assert.match(migration, /airfnb_private_event_requests\(uuid\)[\s\S]*to authenticated;/u);
});

test("the driver proves both predecessor states without touching its source", () => {
  for (const required of [
    "--socket", "--port", "--source-db", "source_fingerprint",
    "SOURCE_SHA256_BEFORE", "SOURCE_SHA256_AFTER", "CANDIDATE_SHA256",
    "for prestate in historical storage",
    "PRE_FIX_HISTORICAL_PII_AND_RAW_CATEGORY_EXPOSURE_REPRODUCED",
    "PRE_FIX_STORAGE_CANDIDATE_SELECT_STAR_FAILURE_REPRODUCED",
    "intentional public-request privacy rollback proof", "assert_good",
    "GOOD_APPLY_REAPPLY_VERIFIED", "SCRATCH_RESIDUE",
    "raw_categories", "raw_availability", "category_availability_helper",
  ]) {
    assert.ok(driver.includes(required), `driver missing ${required}`);
  }
  for (const role of ["anon", "unrelated", "invited", "owner", "admin", "staff", "service"]) {
    assert.match(runtime, new RegExp(role, "u"), `runtime missing ${role}`);
  }
  assert.match(runtime, /airfnb_match_scores_batch/u);
  assert.match(runtime, /airfnb_find_matching_requests/u);
  assert.match(runtime, /airfnb_find_matching_trucks/u);
  assert.match(runtime, /airfnb_recommend_trucks_for_request/u);
  assert.match(runtime, /airfnb_private_event_requests/u);
  for (const score of ["40", "30", "10", "0", "25"]) {
    assert.match(runtime, new RegExp(`helper_[a-z_]+[^\\n]*::numeric = ${score}`, "u"));
  }
  assert.match(
    runtime,
    /score_hit_available[\s\S]{0,160}-[\s\S]{0,160}score_miss_available/u,
  );
  assert.match(
    runtime,
    /score_hit_available[\s\S]{0,160}-[\s\S]{0,160}score_hit_blocked/u,
  );
  assert.match(runtime, /null_actor_helper[^\n]*::numeric = 0/u);
});

test("event-request and RPC types cover the exact catalog contract", () => {
  const rowStart = databaseTypes.indexOf("export interface AirfnbEventRequestRow");
  const rowEnd = databaseTypes.indexOf("export interface AirfnbApplicationRow", rowStart);
  const rowType = databaseTypes.slice(rowStart, rowEnd);
  const fields = [...rowType.matchAll(/^  ([a-z_]+):/gmu)].map((match) => match[1]);
  assert.equal(fields.length, 50);
  assert.equal(new Set(fields).size, 50);
  for (const pii of [
    "contact_name", "contact_email", "contact_phone", "address_line", "address_id",
  ]) {
    assert.ok(fields.includes(pii), `row type missing ${pii}`);
  }
  assert.match(rowType, /slots_needed: number \| null;/u);
  assert.match(rowType, /water_provided: string\[\];/u);
  assert.match(rowType, /wc_provided: string\[\];/u);
  assert.match(databaseTypes, /airfnb_match_scores_batch:[\s\S]*p_truck_ids: string\[\]/u);
  assert.match(
    databaseTypes,
    /airfnb_match_category_availability_score:[\s\S]*Args: \{ p_truck: string; p_request: string \};[\s\S]*Returns: number;/u,
  );
  assert.match(databaseTypes, /airfnb_private_event_requests:[\s\S]*p_request_id\?: string \| null/u);
  for (const enumName of [
    "airfnb_catering_type", "airfnb_energy_need",
    "airfnb_sanitation_level", "airfnb_selection_mode",
  ]) {
    assert.match(databaseTypes, new RegExp(`${enumName}:`, "u"));
  }
});

test("artifacts contain no checkout path, network, credential, or live command", () => {
  const joined = [migration, runtime, driver].join("\n");
  assert.doesNotMatch(joined, /\/Users\//u);
  assert.doesNotMatch(joined, /https?:\/\//iu);
  assert.doesNotMatch(joined, /\bsupabase\s+(?:link|db|migration|functions)\b/iu);
  assert.doesNotMatch(joined, /--linked\b/iu);
  assert.doesNotMatch(
    joined,
    /(?:service_role|postgres(?:ql)?:\/\/)[^\n]{0,24}(?:key|password|secret|token|@)/iu,
  );
});
