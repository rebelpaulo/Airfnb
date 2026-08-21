import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

const repositoryRoot = process.cwd();
const migrationName = "20260819094823_airfnb_identity_reconciliation.sql";
const migrationPath = path.join(
  repositoryRoot,
  "supabase",
  "migrations",
  migrationName,
);
const runbookPath = path.join(
  repositoryRoot,
  "supabase",
  "IDENTITY_RECONCILIATION_RUNBOOK.md",
);
const runtimePath = path.join(
  repositoryRoot,
  "tests",
  "identity-reconciliation-runtime.sql",
);
const driverPath = path.join(
  repositoryRoot,
  "scripts",
  "test-identity-reconciliation.sh",
);

const [migration, runbook, runtime, driver] = await Promise.all([
  readFile(migrationPath, "utf8"),
  readFile(runbookPath, "utf8"),
  readFile(runtimePath, "utf8"),
  readFile(driverPath, "utf8"),
]);

const retiredUuid = "11111111-1111-1111-1111-111111111111";
const retiredEmail = "seed@airfnb.local";
const capturedRemoteHead = "20260815142342";
const forwardVersion = migrationName.slice(0, 14);

const serviceSlugs = [
  "bbq-kings",
  "creperia-pt",
  "divine-burguers",
  "el-mexicano",
  "gypsy-kitchen",
  "la-dolce-vita",
  "pizza-vesuvio",
  "portuguese-tradition",
  "sushi-zen",
  "taco-fiesta",
  "turkish-delights",
  "wok-and-roll",
];

const postSlugs = [
  "casamentos-food-trucks-5-dicas",
  "como-organizar-evento-perfeito-food-trucks",
  "festivais-2025-o-que-ai-vem",
  "quanto-custa-catering-50-pessoas",
  "tendencias-gastronomicas-2025",
];

const requiredRelations = [
  "auth.identities",
  "auth.mfa_factors",
  "auth.refresh_tokens",
  "auth.sessions",
  "auth.users",
  "public.airfnb_addresses",
  "public.airfnb_blog_authors",
  "public.airfnb_blog_posts",
  "public.airfnb_bookings",
  "public.airfnb_contact_requests",
  "public.airfnb_conversation_participants",
  "public.airfnb_event_requests",
  "public.airfnb_events",
  "public.airfnb_favorites",
  "public.airfnb_messages",
  "public.airfnb_notifications",
  "public.airfnb_organizer_reviews",
  "public.airfnb_partner_leads",
  "public.airfnb_platform_settings",
  "public.airfnb_profiles",
  "public.airfnb_proposals",
  "public.airfnb_request_invitations",
  "public.airfnb_reviews",
  "public.airfnb_trucks",
];

test("migration is a new atomic forward-only reconciliation", () => {
  assert.equal(requiredRelations.length, 24);
  assert.ok(BigInt(forwardVersion) > BigInt(capturedRemoteHead));
  assert.match(migration, /^-- Forward-only/i);
  assert.deepEqual(
    migration.match(/^\s*(?:begin|commit)\s*;/gim)?.map((statement) =>
      statement.trim().toLowerCase()
    ),
    ["begin;", "commit;"],
  );
  assert.match(migration, /\ncommit;\s*$/i);
  assert.match(
    migration,
    /^--[\s\S]*?\nbegin;\nset local statement_timeout = '30s';\nset local lock_timeout = '5s';\n\ndo /i,
  );
  assert.ok(
    migration.indexOf("set local statement_timeout")
      < migration.indexOf("do $schema_preconditions$"),
    "statement timeout must precede candidate work",
  );
  assert.ok(
    migration.indexOf("set local lock_timeout")
      < migration.indexOf("do $schema_preconditions$"),
    "lock timeout must precede candidate work",
  );
  assert.match(
    migration,
    /do \$identity_reconciliation\$[\s\S]*delete from auth\.users[\s\S]*\$identity_reconciliation\$;/i,
  );
  assert.doesNotMatch(migration, /\binsert\s+into\s+auth\.users\b/i);
  assert.doesNotMatch(migration, /encrypted_password|changeme/i);

  for (const value of [retiredUuid, retiredEmail]) {
    assert.ok(migration.includes(value), `migration must pin ${value}`);
  }
  for (const relation of requiredRelations) {
    assert.ok(migration.includes(`'${relation}'`), `missing ${relation}`);
  }
});

test("migration fails closed on schema and exact preservation baseline", () => {
  assert.match(migration, /required relations missing or not tables/i);
  assert.match(migration, /expected column type\/nullability drift/i);
  assert.match(migration, /direct profile reference drift/i);
  assert.match(migration, /retired UUID\/email pairing drifted/i);
  assert.match(migration, /expected exactly one retired profile/i);
  assert.match(migration, /expected exactly one retired blog author/i);
  assert.match(migration, /expected exactly the 12 observed catalogue services/i);
  assert.match(migration, /expected exactly the 5 observed published articles/i);

  for (const slug of [...serviceSlugs, ...postSlugs]) {
    assert.ok(migration.includes(`'${slug}'`), `missing baseline slug ${slug}`);
  }
});

test("guard blocks retired/profile privilege attacks and preserves trusted paths", () => {
  assert.match(
    migration,
    /create or replace function public\.airfnb_guard_profile_role\(\)[\s\S]*security definer[\s\S]*set search_path = pg_catalog, public/i,
  );
  assert.match(
    migration,
    /revoke all on function public\.airfnb_guard_profile_role\(\)\s+from public, anon, authenticated;/i,
  );
  assert.match(
    migration,
    /before insert or update on public\.airfnb_profiles/i,
  );
  assert.match(migration, /retired demo identity cannot create or update a profile/i);
  assert.match(
    migration,
    /only an existing admin or staff member can assign a privileged role/i,
  );
  assert.match(migration, /new\.role is not distinct from old\.role/i);
  assert.match(
    migration,
    /new\.role not in \([\s\S]*'admin'::public\.airfnb_user_role,[\s\S]*'staff'::public\.airfnb_user_role/i,
  );
  assert.match(migration, /if v_actor is null then\s+return new;/i);
  assert.doesNotMatch(migration, /raw_user_meta_data|user_metadata/i);
});

test("cleanup detaches every mutable identity edge and has second-run postconditions", () => {
  const detachments = [
    ["airfnb_trucks", "owner_id"],
    ["airfnb_blog_posts", "author_id"],
    ["airfnb_bookings", "organizer_id"],
    ["airfnb_messages", "sender_id"],
    ["airfnb_reviews", "organizer_id"],
    ["airfnb_proposals", "prepared_by"],
    ["airfnb_contact_requests", "handled_by"],
    ["airfnb_request_invitations", "invited_by"],
    ["airfnb_partner_leads", "handled_by"],
    ["airfnb_platform_settings", "updated_by"],
    ["airfnb_profiles", "referred_by"],
  ];

  for (const [table, column] of detachments) {
    assert.match(
      migration,
      new RegExp(
        `update\\s+public\\.${table}\\s+set\\s+${column}\\s*=\\s*null`,
        "i",
      ),
    );
  }

  assert.match(
    migration,
    /delete from public\.airfnb_conversation_participants\s+where user_id = v_seed_id/i,
  );
  assert.match(
    migration,
    /delete from auth\.users\s+where id = v_seed_id\s+and email = v_seed_email/i,
  );
  assert.match(migration, /v_first_run := false/i);
  assert.match(migration, /First-run and second-run postconditions are identical/i);
  assert.match(migration, /retired auth dependency remains in auth\.%/i);
});

test("postcondition scans every public UUID column with escaped identifiers", () => {
  assert.match(
    migration,
    /from pg_catalog\.pg_attribute as attribute[\s\S]*join pg_catalog\.pg_class as relation[\s\S]*join pg_catalog\.pg_namespace as namespace/i,
  );
  assert.match(migration, /namespace\.nspname = 'public'/i);
  assert.match(migration, /relation\.relkind in \('r', 'p'\)/i);
  assert.match(
    migration,
    /attribute\.atttypid = 'uuid'::pg_catalog\.regtype/i,
  );
  assert.match(
    migration,
    /'select count\(\*\) from %I\.%I where %I = \$1'/i,
  );
  assert.match(
    migration,
    /retired UUID remains in %\.%.%/i,
  );
});

test("runbook isolates history and permits only migration up without broad replay", () => {
  for (const value of [capturedRemoteHead, forwardVersion, retiredUuid, retiredEmail]) {
    assert.ok(runbook.includes(value), `runbook must pin ${value}`);
  }

  assert.match(runbook, /reported-unverified/i);
  assert.match(runbook, /Point-in-Time Recovery/i);
  assert.match(runbook, /already-issued JWT[\s\S]*until expiry/i);
  assert.match(
    runbook,
    /45 local-only versions and 242 remote-only\s+versions/i,
  );
  assert.match(runbook, /deployment bundle[\s\S]*disposable/i);
  assert.match(
    runbook,
    /only\s+local-only version above it is `20260819094823`/i,
  );

  const mutatingCommands = runbook.match(/supabase migration up/g) ?? [];
  assert.equal(mutatingCommands.length, 1);
  assert.match(
    runbook,
    /supabase migration up \\\n\s+--linked --project-ref "\$PROJECT_REF"/,
  );
  assert.match(runbook, /Do not use `db push`, `migration repair`, or `--include-all`/i);
  assert.match(runbook, /Do not add any flags/i);
  assert.match(runbook, /Never recreate, remap, or\s+restore the retired UUID\/email credential/i);
});

test("runbook defines exact prechecks, postchecks, and recovery", () => {
  assert.match(runbook, /exact_identity=1/i);
  assert.match(runbook, /required_relations=24/i);
  assert.match(runbook, /nullable_history_columns=6/i);
  assert.match(runbook, /remote head must now be exactly\s+`20260819094823`/i);
  assert.match(runbook, /detached_services/i);
  assert.match(runbook, /detached_articles/i);
  assert.match(runbook, /authenticated_execute_revoked/i);
  assert.match(runbook, /same fail-closed UUID sweep used by the migration/i);
  assert.match(
    runbook,
    /'select count\(\*\) from %I\.%I where %I=\$1'/i,
  );
  assert.match(runbook, /recover[\s\S]*recorded PITR point/i);
  assert.match(runbook, /new legitimate identity/i);
});

test("runtime harness is scratch-only and cannot mask candidate atomicity", () => {
  assert.match(
    runtime,
    /current_database\(\) = :'identity_runtime_database'[\s\S]*\^fb_tailor_identity_runtime_\[0-9\]\+_\[0-9\]\+\$/i,
  );
  assert.deepEqual(
    runtime.match(/^\s*(?:begin|commit)\s*;/gim) ?? [],
    [],
    "runtime harness must not wrap or commit the migration candidate",
  );
  assert.doesNotMatch(runtime, /\\i[r]?\s+.*identity_reconciliation/i);
  assert.match(runtime, /SETUP_11_OF_12_DRIFT/i);
  assert.match(runtime, /candidate reaches guard DDL[\s\S]*exact twelve-service precondition/i);
  assert.match(runtime, /FAILED_APPLY_ROLLED_BACK/i);
  assert.match(runtime, /GOOD_APPLY_PASS/i);
  assert.match(runtime, /ROLE_PATHS_PASS/i);
  assert.match(runtime, /runtime role attack unexpectedly succeeded/i);
  assert.match(runtime, /has_function_privilege\('anon'/i);
  assert.match(runtime, /has_function_privilege\('authenticated'/i);
});

test("driver clones one exact local source and proves failure, apply, and reapply", () => {
  assert.match(driver, /--socket SOCKET_DIRECTORY --port PORT --source-db SOURCE_DATABASE/);
  assert.match(driver, /-S "\$socket_directory\/\.s\.PGSQL\.\$postgres_port"/);
  assert.match(driver, /\^fb_tailor_identity_runtime_\[0-9\]\+_\[0-9\]\+\$/);
  assert.match(driver, /refusing pre-existing scratch database/i);
  assert.match(driver, /--template="\$source_database"/);
  assert.match(driver, /scratch_created=1/);
  assert.match(driver, /if \(\(scratch_created == 1\)\)/);
  assert.match(driver, /dropdb[\s\S]*-- "\$scratch_database"/);
  assert.doesNotMatch(driver, /-- "\$source_database"/);

  assert.match(driver, /run_runtime_phase setup_drift/);
  assert.match(driver, /INTENTIONAL_FAILURE_OBSERVED/);
  assert.match(driver, /run_runtime_phase assert_failed_atomicity_and_prepare_good/);
  assert.match(driver, /GOOD_APPLY_VERIFIED/);
  assert.match(driver, /GOOD_REAPPLY_VERIFIED/);
  assert.equal(
    (driver.match(/--file="\$migration_file"/g) ?? []).length,
    3,
    "driver must run one intentional failure, one apply, and one reapply",
  );
  assert.doesNotMatch(driver, /--single-transaction|(?:^|\s)-1(?:\s|$)/m);
  assert.match(driver, /SOURCE_AUDIT_BEFORE/);
  assert.match(driver, /SOURCE_AUDIT_AFTER/);
  assert.match(driver, /SOURCE_FINGERPRINT_AND_ZERO_FIXTURE_PASS/);
  assert.match(driver, /SCRATCH_CLEANUP_PASS/);

  for (const forbidden of ["/private/tmp/", "/Users/", "supabase db push", "--include-all"]) {
    assert.ok(!driver.includes(forbidden), `driver must remain portable: ${forbidden}`);
  }
});

test("runbook documents explicit atomicity and the portable two-run proof", () => {
  assert.match(runbook, /Supabase CLI 2\.115\.0/i);
  assert.match(runbook, /per-file session[\s\S]*does not supply an outer transaction/i);
  assert.match(runbook, /exactly one explicit `BEGIN`[\s\S]*terminal `COMMIT`/i);
  assert.match(runbook, /statement_timeout[\s\S]*lock_timeout/i);
  assert.match(runbook, /run the command twice/i);
  assert.match(runbook, /test-identity-reconciliation\.sh/i);
  assert.match(runbook, /source fingerprint[\s\S]*zero-fixture/i);
  assert.match(runbook, /intentional 11-of-12 drift/i);
  assert.match(runbook, /good apply and reapply/i);
  assert.match(runbook, /runtime harness\s+contains no `COMMIT`/i);
});
