import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const migration = read("supabase/migrations/20260821121634_shared_project_auth_boundary.sql");
const baseline = read("scripts/migrations/apply/20260821124724_indigo_shared_project_baseline.sql");
const runtime = read("tests/shared-project-auth-boundary-runtime.sql");
const driver = read("scripts/test-shared-project-auth-boundary.sh");
const types = read("types/database.ts");

function functionBlock(name) {
  const match = migration.match(new RegExp(
    `create or replace function public\\.${name}\\([\\s\\S]*?\\n\\$function\\$;`, "iu",
  ));
  assert.ok(match, `missing ${name}`);
  return match[0];
}

function sharedFunctionBody(name) {
  const block = functionBlock(name);
  return block.slice(block.indexOf("as $function$") + "as $function$".length, block.lastIndexOf("$function$;"));
}

function baselineFunctionBody(name) {
  const start = baseline.indexOf(`CREATE FUNCTION public.${name}`);
  assert.notEqual(start, -1, `baseline missing ${name}`);
  const bodyStart = baseline.indexOf("AS $$", start) + "AS $$".length;
  const bodyEnd = baseline.indexOf("$$;", bodyStart);
  assert.ok(bodyStart > "AS $$".length && bodyEnd > bodyStart, `baseline body missing ${name}`);
  return baseline.slice(bodyStart, bodyEnd);
}

test("migration removes the global Auth hook and accepts only predecessor or final state", () => {
  assert.match(migration, /drop trigger if exists airfnb_trg_auth_new_user on auth\.users;/u);
  assert.match(migration, /drop function if exists public\.airfnb_handle_new_user\(\);/u);
  assert.match(migration, /v_predecessor[\s\S]*v_final[\s\S]*if not v_predecessor and not v_final/u);
  for (const bodyHash of [
    "30225c87def1bebf86c9a443ffead831",
    "9b03c272bb453651123bac3a77a9f938",
    "2755fff7e06bdad768d499ff6305c10f",
    "db8fec4890616074250a98f9d8b35d6d",
    "8d2849ef2dc3fbfbc59c6d6d7fe2aeaf",
    "ff72982e6ade07065de6d385f79997a1",
  ]) assert.match(migration, new RegExp(bodyHash, "u"));
  assert.doesNotMatch(migration, /c22c990f37a14fe8ea7dfb0638d37ef7/u);
  assert.match(migration, /global signup hook remains/u);
  assert.match(migration, /alter column role drop default;[\s\S]*alter column role drop not null;/u);
  assert.match(migration, /profile role is not nullable without default/u);
  assert.equal((migration.match(/^begin;$/gmu) ?? []).length, 1);
  assert.equal((migration.match(/^commit;$/gmu) ?? []).length, 1);
});

test("bootstrap is actor-scoped, validated, idempotent and metadata-free", () => {
  const block = functionBlock("airfnb_ensure_profile");
  assert.match(block, /p_full_name text default null/u);
  assert.match(block, /p_locale text default 'pt-PT'/u);
  assert.match(block, /returns public\.airfnb_profiles/u);
  assert.match(block, /security definer[\s\S]*set search_path = ''/u);
  assert.match(block, /v_actor uuid := auth\.uid\(\)/u);
  assert.match(block, /char_length\(v_name\) < 2[\s\S]*char_length\(v_name\) > 120/u);
  assert.match(block, /p_locale not in \('pt-PT', 'en'\)/u);
  assert.match(block, /insert into public\.airfnb_profiles \(id, role, full_name, locale\)[\s\S]*values \(v_actor, null, v_name, p_locale\)[\s\S]*on conflict \(id\) do nothing/u);
  assert.match(block, /pg_advisory_xact_lock\(1095122502, pg_catalog\.hashtext\(v_actor::text\)\)/u);
  assert.match(block, /airfnb_membership_tombstones[\s\S]*F&B membership was deleted/u);
  assert.doesNotMatch(block, /(?:raw_user_meta_data|raw_app_meta_data|user_metadata|app_metadata)/iu);
  assert.doesNotMatch(block, /\bexecute\b/iu);
});

test("role claim is one-time and cannot self-elevate", () => {
  const block = functionBlock("airfnb_claim_role");
  assert.match(block, /p_role not in \([\s\S]*'organizer'[\s\S]*'owner'/u);
  assert.match(block, /where profile\.id = v_actor[\s\S]*for update/u);
  assert.match(block, /if v_profile\.role is null then[\s\S]*update public\.airfnb_profiles set role = p_role/u);
  assert.match(block, /elsif v_profile\.role is distinct from p_role then[\s\S]*profile role cannot be changed after claim/u);
  assert.match(block, /pg_advisory_xact_lock\(1095122502, pg_catalog\.hashtext\(v_actor::text\)\)/u);
  assert.match(block, /airfnb_membership_tombstones[\s\S]*F&B membership was deleted/u);
  assert.doesNotMatch(block, /(?:raw_user_meta_data|raw_app_meta_data|user_metadata|app_metadata)/iu);
});

test("membership RPCs have exact authenticated-only ACL and generated types", () => {
  for (const signature of [
    "airfnb_ensure_profile\\(text,text\\)",
    "airfnb_claim_role\\(public\\.airfnb_user_role\\)",
    "airfnb_apply_referral\\(text\\)",
    "airfnb_self_delete\\(\\)",
    "airfnb_self_delete_storage_prefixes\\(\\)",
  ]) {
    assert.match(migration, new RegExp(`revoke all on function public\\.${signature}\\s+from public, anon, authenticated, service_role;`, "iu"));
    assert.match(migration, new RegExp(`grant execute on function public\\.${signature}\\s+to authenticated;`, "iu"));
  }
  assert.match(types, /role: Database\["public"\]\["Enums"\]\["airfnb_user_role"\] \| null/u);
  assert.match(types, /airfnb_ensure_profile:[\s\S]*p_full_name\?: string \| null[\s\S]*p_locale\?: string/u);
  assert.match(types, /airfnb_claim_role:[\s\S]*p_role: AirfnbDatabase\["public"\]\["Enums"\]\["airfnb_user_role"\]/u);
  assert.match(types, /airfnb_self_delete:[\s\S]*Args: never;[\s\S]*Returns: undefined;/u);
  assert.match(types, /airfnb_self_delete_storage_prefixes:[\s\S]*Args: never;[\s\S]*Returns: string\[\];/u);
});

test("dedicated tombstones are opaque, durable and gate every membership lifecycle", () => {
  assert.match(migration, /create table if not exists public\.airfnb_membership_tombstones \([\s\S]*user_id uuid primary key[\s\S]*deleted_at timestamptz not null[\s\S]*storage_truck_ids uuid\[\] not null/u);
  assert.match(migration, /alter table public\.airfnb_membership_tombstones enable row level security/u);
  assert.match(migration, /revoke all on table public\.airfnb_membership_tombstones from public, anon, authenticated, service_role/u);
  assert.doesNotMatch(migration, /airfnb_membership_tombstones[\s\S]{0,180}references auth\.users/iu);
  for (const name of ["airfnb_ensure_profile", "airfnb_claim_role", "airfnb_self_delete"]) {
    assert.match(functionBlock(name), /pg_advisory_xact_lock\(1095122502, pg_catalog\.hashtext\(v_actor::text\)\)/u);
  }
});

test("self-delete preserves shared Auth and permanently blocks reputation reset", () => {
  const block = functionBlock("airfnb_self_delete");
  assert.match(block, /returns void[\s\S]*insert into public\.airfnb_membership_tombstones \(user_id, storage_truck_ids\)/u);
  const prefixes = functionBlock("airfnb_self_delete_storage_prefixes");
  assert.match(prefixes, /returns uuid\[\][\s\S]*where user_id = v_actor[\s\S]*return v_storage_truck_ids/u);
  assert.match(block, /delete from public\.airfnb_organizer_reviews where organizer_id = v_actor/u);
  assert.match(block, /delete from public\.airfnb_profiles where id = v_actor/u);
  assert.match(block, /not exists \([\s\S]*select 1 from auth\.users where id = v_actor/u);
  assert.doesNotMatch(block, /delete from auth\.users|auth\.admin|supabase_auth_admin/iu);
  const referral = functionBlock("airfnb_apply_referral");
  assert.match(referral, /tombstone\.user_id = v_actor/u);
  assert.match(referral, /tombstone\.user_id = profile\.id/u);
});

test("profile writes use a user-editable column allowlist and never expose role", () => {
  assert.match(migration, /revoke insert, update, delete on table public\.airfnb_profiles from authenticated/u);
  assert.match(migration, /revoke update \([\s\S]*\brole\b[\s\S]*\breferrals_count\b[\s\S]*\) on table public\.airfnb_profiles from authenticated/u);
  assert.match(migration, /grant update \([\s\S]*\bfull_name\b[\s\S]*\bavatar_url\b[\s\S]*\bbilling_address_line\b[\s\S]*\) on table public\.airfnb_profiles to authenticated/u);
  assert.doesNotMatch(migration, /grant update \([^)]*\brole\b[^)]*\) on table public\.airfnb_profiles to authenticated/iu);
});

test("Indigo baseline duplicates the sealed membership contract exactly", () => {
  for (const name of [
    "airfnb_guard_profile_role",
    "airfnb_ensure_profile",
    "airfnb_claim_role",
    "airfnb_apply_referral",
    "airfnb_self_delete",
    "airfnb_self_delete_storage_prefixes",
  ]) {
    assert.equal(baselineFunctionBody(name), sharedFunctionBody(name), `${name} differs between authoritative migrations`);
  }
  assert.match(baseline, /CREATE TABLE public\.airfnb_membership_tombstones \([\s\S]*user_id uuid NOT NULL[\s\S]*deleted_at timestamp with time zone DEFAULT statement_timestamp\(\) NOT NULL[\s\S]*storage_truck_ids uuid\[\] DEFAULT '\{\}'::uuid\[\] NOT NULL/u);
  assert.match(baseline, /v_public_relations <> 169/u);
  assert.match(baseline, /c\.relkind='r'\) <> 43/u);
});

test("runtime and driver cover isolation, deletion, rollback, reapply and residue", () => {
  for (const marker of ["foreign_app", "anonymous", "service_role", "cross_user", "metadata", "admin", "staff", "owner", "organizer", "idempotent", "tombstone", "self_delete", "rejoin", "auth_preserved"]) {
    assert.match(runtime, new RegExp(marker, "iu"), `runtime missing ${marker}`);
  }
  for (const marker of ["tamper", "reapply", "source_fingerprint", "zero residue", "shared_auth_boundary"]) {
    assert.match(driver, new RegExp(marker, "iu"), `driver missing ${marker}`);
  }
  assert.doesNotMatch(migration + runtime + driver, /https?:\/\/|supabase\.co|postgres(?:ql)?:\/\//iu);
  assert.match(driver, /identity_runtime_phase=setup_drift[\s\S]*identity_runtime_phase=assert_failed_atomicity_and_prepare_good[\s\S]*identity_runtime_phase=assert_good/u);
  assert.match(driver, /apply_predecessors\(\)[\s\S]*ebd2f85a1bacb5eceaca6a1c3cec5731/u);
  assert.ok(driver.indexOf("apply_predecessors\n") < driver.indexOf("tamper_before="));
});
