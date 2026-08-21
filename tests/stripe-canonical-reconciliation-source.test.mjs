import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const sha256 = (value) => createHash("sha256").update(value).digest("hex");

const migration = read("supabase/migrations/20260820155322_stripe_canonical_reconciliation.sql");
const marketplace = read("supabase/migrations/20260820154358_marketplace_workflow_reconciliation.sql");
const checkout = read("app/api/stripe/checkout/route.ts");
const lockFeeService = read("lib/payments/lock-fee.server.ts");
const nextWebhook = read("app/api/stripe/webhook/route.ts");
const edgeWebhook = read("supabase/functions/stripe-webhook/index.ts");
const devPay = read("app/api/dev/mark-paid/route.ts");
const packageJson = JSON.parse(read("package.json"));
const lockfile = read("pnpm-lock.yaml");
const types = read("types/database.ts");
const runtime = read("tests/stripe-canonical-reconciliation-runtime.sql");
const driver = read("scripts/test-stripe-canonical-reconciliation.sh");

const rpcKeys = [
  "p_event_id", "p_event_type", "p_event_created_at", "p_application_id",
  "p_lock_fee_id", "p_booking_id", "p_payment_intent", "p_amount_minor",
  "p_currency", "p_payment_status", "p_refunded_amount_minor",
];

function eventArgs(source, eventType) {
  const escaped = eventType.replaceAll(".", "\\.");
  const match = source.match(
    new RegExp(`if \\(event\\.type === "${escaped}"\\) \\{[\\s\\S]*?return \\{([\\s\\S]*?)\\n    \\};`),
  );
  assert.ok(match, `missing ${eventType} mapping`);
  return [...match[1].matchAll(/^      (p_[a-z_]+): (.+),$/gm)]
    .map((entry) => [entry[1], entry[2]]);
}

test("the exact independently verified Marketplace migration is the predecessor", () => {
  assert.equal(
    sha256(marketplace),
    "07e6692f05aad35a9256ab514b73a446ee49c3d7c794b909c62240256ec1147d",
  );
  assert.match(migration, /airfnb_supplier_lock_fee\(uuid\)/);
  assert.match(migration, /e73cb472f9bcc4eff83ced6b3357b47d/);
  assert.match(migration, /c96f49df5f1b05fabea73bfdbf534a74/);
});

test("Stripe library and API versions are exact and currency is EUR-only", () => {
  assert.equal(packageJson.dependencies.stripe, "17.7.0");
  assert.match(lockfile, /stripe:\n\s+specifier: 17\.7\.0\n\s+version: 17\.7\.0/);
  assert.match(edgeWebhook, /stripe@17\.7\.0\?target=denonext/);
  for (const source of [lockFeeService, nextWebhook, edgeWebhook]) {
    assert.match(source, /apiVersion: "2025-02-24\.acacia"/);
  }
  assert.match(lockFeeService, /currency !== "EUR"/);
  assert.match(lockFeeService, /currency: "eur"/);
  assert.match(lockFeeService, /p_currency: "EUR"/);
  assert.match(migration, /stripe currency must be EUR/);
  assert.doesNotMatch(migration, /\^\[A-Za-z\]\{3\}\$/);
});

test("checkout and dev ownership use only the Marketplace supplier context RPC", () => {
  assert.equal((lockFeeService.match(/\.rpc\(\s*"airfnb_supplier_lock_fee"/g) ?? []).length, 2);
  for (const source of [lockFeeService, checkout, devPay]) {
    assert.doesNotMatch(source, /airfnb_trucks!inner\(owner_id\)/);
    assert.doesNotMatch(source, /\.select\([^\n]*owner_id/);
  }
  assert.match(checkout, /await sb\.auth\.getUser\(\)/);
  assert.match(checkout, /createLockFeeCheckout\(\{ applicationId, user, supplier: sb \}\)/);
  assert.match(devPay, /await sb\.auth\.getUser\(\)/);
  assert.match(devPay, /markLockFeePaidDev\(\{ applicationId, supplier: sb \}\)/);
  assert.match(lockFeeService, /metadata,\s*\n\s*payment_intent_data: \{ metadata \}/);
  assert.match(lockFeeService, /idempotencyKey: `airfnb-lock-fee-\$\{lockFee\.id\}`/);
});

test("Next and Edge webhooks have one identical, fail-closed eleven-argument contract", () => {
  for (const eventType of ["checkout.session.completed", "charge.refunded"]) {
    assert.deepEqual(eventArgs(nextWebhook, eventType), eventArgs(edgeWebhook, eventType));
    assert.deepEqual(eventArgs(nextWebhook, eventType).map(([key]) => key), rpcKeys);
  }
  for (const source of [nextWebhook, edgeWebhook]) {
    assert.equal((source.match(/paymentIntents\.retrieve\(intentId\)/g) ?? []).length, 2);
    assert.match(source, /direct && inherited && direct !== inherited/);
    assert.match(source, /conflicting reconciliation metadata/);
    assert.equal((source.match(/\.rpc\(\s*"airfnb_reconcile_stripe_event"/g) ?? []).length, 1);
    assert.doesNotMatch(source, /\.from\("airfnb_(payments|lock_fees|stripe_events)"\)/);
    assert.match(source, /received: false[\s\S]*status: 500|received: false[\s\S]*, 500/);
  }
  assert.match(nextWebhook, /const raw = await req\.text\(\)/);
  assert.match(nextWebhook, /constructEvent\(raw, signature, signingSecret\)/);
  assert.match(edgeWebhook, /const raw = await req\.text\(\)/);
  assert.match(edgeWebhook, /constructEventAsync\(\s*raw,/);
});

test("the migration is atomic, exact-prestate and RPC-only", () => {
  assert.match(migration, /^--[\s\S]*\nbegin;/);
  assert.match(migration, /v_legacy::integer \+ v_old::integer \+ v_final::integer/);
  assert.match(migration, /v_ledger oid := pg_catalog\.to_regclass\('public\.airfnb_stripe_events'\)/);
  assert.doesNotMatch(
    migration.slice(0, migration.indexOf("create table if not exists public.airfnb_stripe_events")),
    /'public\.airfnb_stripe_events'::pg_catalog\.regclass/,
  );
  assert.match(migration, /mixed or unknown prestate/);
  assert.match(migration, /legacy payment binding is ambiguous/);
  assert.match(migration, /non-EUR financial data exists/);
  assert.match(migration, /duplicate financial binding exists/);
  assert.match(migration, /set search_path = ''/);
  assert.match(migration, /security definer/);
  assert.match(migration, /Lock order is deliberately stable/);
  assert.match(migration, /on conflict \(event_id\) do nothing/);
  assert.ok(
    migration.indexOf("select * into v_lock_fee")
      < migration.indexOf("insert into public.airfnb_stripe_events("),
    "business-row locks must precede the ledger insert",
  );
  assert.match(migration, /stale_refund_ignored/);
  assert.match(migration, /full_refund_reconciled/);
  for (const table of ["airfnb_payments", "airfnb_lock_fees", "airfnb_stripe_events"]) {
    assert.match(migration, new RegExp(`revoke all on table public\\.${table}`));
  }
  assert.match(migration, /grant select on table public\.airfnb_payments, public\.airfnb_lock_fees,/);
  assert.match(migration, /alter table public\.airfnb_stripe_events force row level security/);
  assert.doesNotMatch(migration, /create policy[^;]+airfnb_stripe_events/is);
});

test("database types expose the canonical tables and RPC", () => {
  for (const field of [
    "application_id", "lock_fee_id", "refunded_amount", "last_provider_event_at",
  ]) assert.match(types, new RegExp(`${field}:`));
  assert.match(types, /airfnb_stripe_events: \{/);
  assert.match(types, /airfnb_reconcile_stripe_event: \{/);
  for (const key of rpcKeys) assert.match(types, new RegExp(`${key}[?:]+`));
});

test("runtime and guarded driver carry the required state and concurrency matrices", () => {
  for (const marker of [
    "INITIAL_PAYMENT_VERIFIED", "DUPLICATE_CONFLICT_VERIFIED",
    "REFUND_MONOTONICITY_VERIFIED", "INVALID_MATRIX_VERIFIED",
  ]) assert.match(runtime, new RegExp(marker));
  for (const marker of [
    "CONCURRENT_DUPLICATE_VERIFIED", "CONCURRENT_PROVIDER_BINDING_VERIFIED",
    "PAYMENT_SWEEPER_SERIALIZATION_VERIFIED", "CONCURRENT_REFUND_VERIFIED",
    "SOURCE_SHA256_UNCHANGED", "SCRATCH_RESIDUE=0",
  ]) assert.match(driver, new RegExp(marker));
});
