import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migrationPath = new URL(
  "../supabase/migrations/20260820152018_airfnb_runtime_function_integrity_reconciliation.sql",
  import.meta.url,
);
const runtimePath = new URL(
  "./runtime-function-integrity-reconciliation-runtime.sql",
  import.meta.url,
);
const driverPath = new URL(
  "../scripts/test-runtime-function-integrity-reconciliation.sh",
  import.meta.url,
);
const historicalReferralPath = new URL(
  "../supabase/migrations/20260525020000_airfnb_30_referrals_newsletter.sql",
  import.meta.url,
);
const historicalSecurityFixPath = new URL(
  "../supabase/migrations/20260524132230_airfnb_06_fix_rls_and_function_security.sql",
  import.meta.url,
);
const historicalHardeningPath = new URL(
  "../supabase/migrations/20260818192940_runtime_function_integrity.sql",
  import.meta.url,
);

const [
  migration,
  runtime,
  driver,
  historicalReferral,
  historicalSecurityFix,
  historicalHardening,
] = await Promise.all([
    readFile(migrationPath, "utf8"),
    readFile(runtimePath, "utf8"),
    readFile(driverPath, "utf8"),
    readFile(historicalReferralPath, "utf8"),
    readFile(historicalSecurityFixPath, "utf8"),
    readFile(historicalHardeningPath, "utf8"),
  ]);

function migrationTaggedBody(tag) {
  const delimiter = `$${tag}$`;
  const start = migration.indexOf(delimiter);
  assert.notEqual(start, -1, `missing migration body ${tag}`);
  const end = migration.indexOf(delimiter, start + delimiter.length);
  assert.notEqual(end, -1, `unterminated migration body ${tag}`);
  return migration.slice(start + delimiter.length, end);
}

function historicalFunctionBody(functionName) {
  const signature = `create or replace function public.${functionName}()`;
  const functionStart = historicalReferral.indexOf(signature);
  assert.notEqual(functionStart, -1, `missing historical function ${functionName}`);
  const bodyStart = historicalReferral.indexOf("as $$", functionStart);
  const bodyEnd = historicalReferral.indexOf("$$;", bodyStart + 5);
  assert.notEqual(bodyStart, -1, `missing body start for ${functionName}`);
  assert.notEqual(bodyEnd, -1, `missing body end for ${functionName}`);
  return historicalReferral.slice(bodyStart + 5, bodyEnd);
}

test("migration is one bounded atomic forward-only reconciliation", () => {
  assert.equal((migration.match(/^begin;$/gmu) ?? []).length, 1);
  assert.equal((migration.match(/^commit;$/gmu) ?? []).length, 1);
  assert.match(migration, /set local lock_timeout = '5s';/u);
  assert.match(migration, /set local statement_timeout = '30s';/u);
  assert.match(
    migration,
    /set local idle_in_transaction_session_timeout = '60s';/u,
  );
  assert.doesNotMatch(migration, /\bdrop\s+(?:function|trigger)\b/iu);
  assert.doesNotMatch(migration, /\bowner\s+to\b/iu);
  assert.equal(
    (
      migration.match(
        /create or replace function public\.airfnb_(?:generate|assign)_referral_code\(\)/giu,
      ) ?? []
    ).length,
    2,
  );
  assert.doesNotMatch(
    migration,
    /create or replace function public\.airfnb_handle_new_user\(\)/iu,
  );
});

test("historical retry and signup contracts are pinned and restored exactly", () => {
  assert.match(
    historicalReferral,
    /if v_attempts > 10 then raise exception 'could not generate unique referral code'; end if;/u,
  );
  assert.match(historicalHardening, /if v_attempts >= 10 then/u);
  assert.match(
    historicalHardening,
    /could not generate unique referral code after % attempts/u,
  );
  assert.equal(
    migrationTaggedBody("historical_202605_generator"),
    historicalFunctionBody("airfnb_generate_referral_code"),
  );
  assert.equal(
    migrationTaggedBody("historical_202605_assignment"),
    historicalFunctionBody("airfnb_assign_referral_code"),
  );
  assert.match(migration, /if v_attempts > 10 then/gu);
  assert.match(
    migration,
    /raise exception 'could not generate unique referral code';/gu,
  );
  const executableSection = migration.slice(
    migration.indexOf(
      "create or replace function public.airfnb_generate_referral_code()",
    ),
  );
  assert.doesNotMatch(executableSection, /if v_attempts >= 10 then/u);
  assert.doesNotMatch(
    executableSection,
    /could not generate unique referral code after % attempts/u,
  );
  assert.match(
    migration,
    /alter function public\.airfnb_handle_new_user\(\)[\s\S]*set search_path = pg_catalog, public;/u,
  );
  assert.match(
    migration,
    /values \(new\.id, new\.raw_user_meta_data->>'full_name', coalesce\(new\.raw_user_meta_data->>'locale','pt-PT'\)\)/u,
  );
});

test("three coherent prestates are exact and mixed or unknown states fail closed", () => {
  const historicalStart = migration.indexOf("Accepted prestate 1:");
  const oldStart = migration.indexOf("Accepted prestate 2:");
  const finalStart = migration.indexOf("Accepted prestate 3:");
  const classifierEnd = migration.indexOf(
    "runtime function integrity refused: mixed or unknown prestate",
  );
  assert.ok(
    historicalStart > 0 &&
      oldStart > historicalStart &&
      finalStart > oldStart &&
      classifierEnd > finalStart,
  );

  const historicalState = migration.slice(historicalStart, oldStart);
  const oldState = migration.slice(oldStart, finalStart);
  const finalState = migration.slice(finalStart, classifierEnd);

  assert.equal((historicalState.match(/procedure\.proconfig is null/gu) ?? []).length, 2);
  assert.equal((historicalState.match(/procedure\.proacl is null/gu) ?? []).length, 2);
  assert.equal((historicalState.match(/not procedure\.prosecdef/gu) ?? []).length, 2);
  assert.match(historicalState, /array\['search_path=public'\]::text\[\]/u);
  assert.match(oldState, /if v_attempts >= 10 then/u);
  assert.match(oldState, /procedure\.proacl is not null/u);
  assert.match(oldState, /array\['search_path=pg_catalog, public'\]::text\[\]/u);
  assert.match(finalState, /if v_attempts > 10 then/u);
  assert.match(finalState, /array\['search_path=pg_catalog, public'\]::text\[\]/u);
  assert.match(
    migration,
    /v_historical_202605::integer[\s\S]*v_old_202608_hardening::integer[\s\S]*v_final_reapplied::integer[\s\S]*\) <> 1/u,
  );
  assert.match(historicalSecurityFix, /revoke execute on function public\.airfnb_handle_new_user\(\)[\s\S]*from anon, authenticated, public;/u);
  assert.doesNotMatch(
    historicalReferral,
    /revoke execute on function public\.airfnb_(?:generate|assign)_referral_code/u,
  );
});

test("qualified final bodies, exact bindings, owner, overload and ACL gates are present", () => {
  assert.match(migration, /pg_catalog\.upper\(/u);
  assert.match(migration, /pg_catalog\.substr\(/u);
  assert.match(migration, /pg_catalog\.encode\(/u);
  assert.match(migration, /extensions\.gen_random_bytes\(6\)/u);
  assert.match(migration, /pg_catalog\.regexp_replace\(/u);
  assert.match(migration, /from public\.airfnb_profiles/u);
  assert.match(migration, /count\(distinct procedure\.proowner\)/u);
  assert.match(migration, /owner_role\.rolbypassrls/u);
  assert.match(migration, /missing or overloaded target function/u);
  assert.match(migration, /signup ACL drifted/u);
  assert.match(migration, /unexpected trigger binding count/u);
  assert.match(migration, /trigger_row\.tgenabled = 'O'/u);
  assert.match(migration, /trigger_row\.tgtype = 7/u);
  assert.match(migration, /trigger_row\.tgtype = 5/u);
  assert.match(migration, /from public, anon, authenticated, service_role/u);
});

test("driver is local, disposable, fingerprinted and exercises every runtime proof", () => {
  for (const required of [
    "--socket",
    "--port",
    "--source-db",
    "SOURCE_SHA256_BEFORE",
    "SOURCE_SHA256_AFTER",
    "CANDIDATE_SHA256",
    "intentional runtime-function-integrity rollback proof",
    "runtime-function-integrity-reconciliation-runtime.sql",
    "assert_direct_call_denied",
    'run_complete_matrix "OLD_CANDIDATE"',
    'run_complete_matrix "HISTORICAL_REMOTE"',
    'assert_prestate_rejected "MIXED_PRESTATE"',
    'assert_prestate_rejected "UNKNOWN_PRESTATE"',
    'echo "SCRATCH_RESIDUE=$SCRATCH_RESIDUE"',
  ]) {
    assert.ok(driver.includes(required), `driver missing ${required}`);
  }
  assert.match(runtime, /create schema rfi_hostile/u);
  assert.match(runtime, /request\.jwt\.claim\.sub/u);
  assert.match(runtime, /v_calls <> 11/u);
  assert.match(runtime, /could not generate unique referral code/u);
  assert.match(runtime, /rollback;/u);
});

test("the four artifacts contain no checkout path, live command or credential", () => {
  const joined = [migration, runtime, driver].join("\n");
  assert.doesNotMatch(joined, /\/Users\//u);
  assert.doesNotMatch(joined, /\bsupabase\s+(?:link|db|migration|functions)\b/iu);
  assert.doesNotMatch(joined, /--linked\b/iu);
  assert.doesNotMatch(joined, /https?:\/\//iu);
  assert.doesNotMatch(
    joined,
    /(?:service_role|postgres(?:ql)?:\/\/)[^\n]{0,24}(?:key|password|secret|token|@)/iu,
  );
});
