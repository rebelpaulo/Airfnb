import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { chmodSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const repositoryRoot = resolve(import.meta.dirname, "..");
const scriptPath = join(repositoryRoot, "scripts", "supabase-production-preflight.sh");
const validRef = "abcdefghijklmnopqrst";
const otherRef = "zyxwvutsrqponmlkjihg";
const safeBits = "1111111";

let fixtureDir;
let fakeSupabase;
let invocationLog;

const migrationVersions = readdirSync(join(repositoryRoot, "supabase", "migrations"))
  .filter((name) => /^\d+_.+\.sql$/.test(name))
  .sort()
  .map((name) => basename(name).match(/^(\d+)_/)[1]);

const safeMigrationOutput = JSON.stringify({
  migrations: migrationVersions.map((version) => ({
    local: version,
    remote: version,
  })),
});

const fakeSource = String.raw`#!/usr/bin/env node
const fs = require("node:fs");

const args = process.argv.slice(2);
fs.appendFileSync(process.env.FAKE_SUPABASE_LOG, JSON.stringify({
  args,
  accessTokenPresent: Boolean(process.env.SUPABASE_ACCESS_TOKEN),
  databasePasswordPresent: Boolean(process.env.SUPABASE_DB_PASSWORD),
}) + "\n");

if (process.env.FAKE_STDERR) process.stderr.write(process.env.FAKE_STDERR);

let kind;
if (args[0] === "projects" && args[1] === "list") kind = "PROJECTS";
if (args[0] === "migration" && args[1] === "list") kind = "MIGRATIONS";
if (args[0] === "db" && args[1] === "query") kind = "QUERY";
if (!kind) process.exit(97);

const exitCode = Number(process.env["FAKE_" + kind + "_EXIT"] ?? "0");
const output = process.env["FAKE_" + kind + "_OUTPUT"] ?? "";
process.stdout.write(output);
process.exit(exitCode);
`;

before(() => {
  fixtureDir = mkdtempSync(join(tmpdir(), "airfnb-preflight-test-"));
  fakeSupabase = join(fixtureDir, "supabase-fake.cjs");
  invocationLog = join(fixtureDir, "invocations.jsonl");
  writeFileSync(fakeSupabase, fakeSource);
  chmodSync(fakeSupabase, 0o755);
});

after(() => {
  rmSync(fixtureDir, { recursive: true, force: true });
});

function runPreflight({
  projectRef = validRef,
  projectsOutput = JSON.stringify([{ id: validRef, status: "ACTIVE_HEALTHY" }]),
  migrationsOutput = safeMigrationOutput,
  queryOutput = `preflight_result\nAIRFNB_PREFLIGHT_V1:${safeBits}\n`,
  projectsExit = 0,
  migrationsExit = 0,
  queryExit = 0,
  fakeStderr = "",
} = {}) {
  writeFileSync(invocationLog, "");

  const result = spawnSync("bash", [scriptPath, projectRef], {
    cwd: repositoryRoot,
    encoding: "utf8",
    timeout: 10_000,
    env: {
      PATH: process.env.PATH,
      LANG: "C",
      LC_ALL: "C",
      SUPABASE_BIN: fakeSupabase,
      FAKE_SUPABASE_LOG: invocationLog,
      FAKE_PROJECTS_OUTPUT: projectsOutput,
      FAKE_MIGRATIONS_OUTPUT: migrationsOutput,
      FAKE_QUERY_OUTPUT: queryOutput,
      FAKE_PROJECTS_EXIT: String(projectsExit),
      FAKE_MIGRATIONS_EXIT: String(migrationsExit),
      FAKE_QUERY_EXIT: String(queryExit),
      FAKE_STDERR: fakeStderr,
    },
  });

  if (result.error) {
    throw new Error(
      `Supabase production preflight subprocess failed: ${result.error.message}`,
      { cause: result.error },
    );
  }

  const invocations = readFileSync(invocationLog, "utf8")
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((line) => JSON.parse(line));

  return { ...result, invocations };
}

test("rejects invalid refs before invoking Supabase", () => {
  for (const projectRef of ["short", "abcdefghijklmnopqrs1", "ABCDEFGHIJKLMNOPQRST"]) {
    const result = runPreflight({ projectRef });
    assert.notEqual(result.status, 0);
    assert.equal(result.invocations.length, 0);
    assert.match(result.stderr, /20 lowercase letters/);
  }
});

test("fails closed when the explicit ref does not match an accessible project", () => {
  const result = runPreflight({
    projectsOutput: JSON.stringify([{ id: otherRef, status: "ACTIVE_HEALTHY" }]),
    fakeStderr: "do-not-print-this-secret",
  });

  assert.notEqual(result.status, 0);
  assert.equal(result.invocations.length, 1);
  assert.deepEqual(result.invocations[0].args, [
    "projects",
    "list",
    "--output-format",
    "json",
  ]);
  assert.doesNotMatch(`${result.stdout}${result.stderr}`, /do-not-print-this-secret/);
  assert.doesNotMatch(`${result.stdout}${result.stderr}`, new RegExp(otherRef));
});

test("rejects divergent migration history before querying the database", () => {
  const divergent = {
    migrations: migrationVersions.map((version) => ({
      local: version,
      remote: version,
    })),
  };
  divergent.migrations.at(-1).remote = null;
  const result = runPreflight({ migrationsOutput: JSON.stringify(divergent) });

  assert.notEqual(result.status, 0);
  assert.equal(result.invocations.length, 2);
  assert.match(result.stderr, /migration histories diverged/);
});

test("rejects malformed output from every inspection stage", async (t) => {
  const cases = [
    { name: "projects", options: { projectsOutput: "not-json" }, calls: 1 },
    { name: "migrations syntax", options: { migrationsOutput: "not-json" }, calls: 2 },
    {
      name: "migrations shape",
      options: { migrationsOutput: JSON.stringify({ migrations: [] }) },
      calls: 2,
    },
    { name: "query", options: { queryOutput: "not-a-result" }, calls: 3 },
  ];

  for (const scenario of cases) {
    await t.test(scenario.name, () => {
      const result = runPreflight(scenario.options);
      assert.notEqual(result.status, 0);
      assert.equal(result.invocations.length, scenario.calls);
    });
  }
});

test("blocks every unsafe database state class", async (t) => {
  const labels = [
    "identity",
    "PII privacy",
    "rate limits",
    "service type",
    "Stripe reconciliation",
    "privacy RPC",
    "migration history",
  ];

  for (const [index, label] of labels.entries()) {
    await t.test(label, () => {
      const bits = safeBits.split("");
      bits[index] = "0";
      const result = runPreflight({
        queryOutput: `preflight_result\nAIRFNB_PREFLIGHT_V1:${bits.join("")}\n`,
      });

      assert.notEqual(result.status, 0);
      assert.equal(result.invocations.length, 3);
      assert.match(result.stderr, new RegExp(label.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
    });
  }
});

test("safe state passes using only explicit read-only Supabase operations", () => {
  const result = runPreflight();

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, "Supabase production preflight passed.\n");
  assert.equal(result.stderr, "");
  assert.equal(result.invocations.length, 3);

  const [projects, migrations, query] = result.invocations;
  assert.deepEqual(projects.args, ["projects", "list", "--output-format", "json"]);
  assert.deepEqual(migrations.args, [
    "migration",
    "list",
    "--linked",
    "--project-ref",
    validRef,
    "--output-format",
    "json",
  ]);
  assert.deepEqual(query.args.slice(0, 7), [
    "db",
    "query",
    "--linked",
    "--project-ref",
    validRef,
    "--output",
    "csv",
  ]);
  assert.equal(query.args.length, 8);

  for (const invocation of result.invocations) {
    assert.equal(invocation.accessTokenPresent, false);
    assert.equal(invocation.databasePasswordPresent, false);
  }

  const sql = query.args[7];
  assert.match(sql, /^WITH\s/i);
  assert.match(sql, /FROM auth\.users/);
  assert.match(sql, /airfnb_profiles_guard_role/);
  assert.match(sql, /has_column_privilege/);
  assert.match(sql, /relation\.relrowsecurity/);
  assert.match(sql, /airfnb_service_type/);
  assert.match(sql, /airfnb_reconcile_stripe_event/);
  assert.match(sql, /airfnb_private_event_requests/);
  assert.match(sql, /supabase_migrations\.schema_migrations/);

  const sqlWithoutStrings = sql.replace(/'(?:''|[^'])*'/g, "''");
  assert.doesNotMatch(
    sqlWithoutStrings,
    /\b(?:insert|update|delete|alter|drop|create|truncate|grant|revoke|call|do)\b/i,
  );
});
