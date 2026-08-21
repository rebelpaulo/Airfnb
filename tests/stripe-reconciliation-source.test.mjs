import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const checkout = read("app/api/stripe/checkout/route.ts");
const lockFeeService = read("lib/payments/lock-fee.server.ts");
const nextWebhook = read("app/api/stripe/webhook/route.ts");
const edgeWebhook = read("supabase/functions/stripe-webhook/index.ts");
const devPay = read("app/api/dev/mark-paid/route.ts");

const expectedRpcKeys = [
  "p_event_id",
  "p_event_type",
  "p_event_created_at",
  "p_application_id",
  "p_lock_fee_id",
  "p_booking_id",
  "p_payment_intent",
  "p_amount_minor",
  "p_currency",
  "p_payment_status",
  "p_refunded_amount_minor",
];

function rpcKeysForEvent(source, eventType) {
  const escaped = eventType.replaceAll(".", "\\.");
  const match = source.match(
    new RegExp(`if \\(event\\.type === "${escaped}"\\) \\{[\\s\\S]*?return \\{([\\s\\S]*?)\\n    \\};`),
  );
  assert.ok(match, `missing ${eventType} mapping`);
  return [...match[1].matchAll(/^      (p_[a-z_]+):/gm)].map((item) => item[1]);
}

function rpcEntriesForEvent(source, eventType) {
  const escaped = eventType.replaceAll(".", "\\.");
  const match = source.match(
    new RegExp(`if \\(event\\.type === "${escaped}"\\) \\{[\\s\\S]*?return \\{([\\s\\S]*?)\\n    \\};`),
  );
  assert.ok(match, `missing ${eventType} mapping`);
  return [...match[1].matchAll(/^      (p_[a-z_]+): (.+),$/gm)]
    .map((item) => [item[1], item[2]]);
}

test("Checkout binds one accepted, pending and unexpired marketplace payment", () => {
  assert.match(lockFeeService, /application\.status !== "accepted"/);
  assert.match(lockFeeService, /lockFee\.status !== "pending"/);
  assert.match(lockFeeService, /booking\.status !== "pending_lock_fee"/);
  assert.match(lockFeeService, /lockFee\.application_id !== applicationId/);
  assert.match(lockFeeService, /booking\.application_id !== applicationId/);
  assert.match(lockFeeService, /dueSeconds < nowSeconds \+ 31 \* 60/);
  assert.match(lockFeeService, /customExpiresAt = dueSeconds <= nowSeconds \+ 24 \* 60 \* 60/);
  assert.match(lockFeeService, /customExpiresAt \? \{ expires_at: customExpiresAt \}/);
  assert.match(lockFeeService, /\.rpc\(\s*"airfnb_supplier_lock_fee"/);
});

test("Checkout emits immutable metadata on both objects and a stable key", () => {
  for (const key of ["application_id", "lock_fee_id", "booking_id"]) {
    assert.match(lockFeeService, new RegExp(`${key}:`));
  }
  assert.match(lockFeeService, /metadata,\s*\n\s*payment_intent_data: \{ metadata \}/);
  assert.match(lockFeeService, /idempotencyKey: `airfnb-lock-fee-\$\{lockFee\.id\}`/);
  assert.match(lockFeeService, /client_reference_id: applicationId/);
});

test("Both signed webhook entrypoints implement identical RPC contracts", () => {
  for (const eventType of ["checkout.session.completed", "charge.refunded"]) {
    assert.deepEqual(
      rpcEntriesForEvent(nextWebhook, eventType),
      rpcEntriesForEvent(edgeWebhook, eventType),
    );
  }
  for (const source of [nextWebhook, edgeWebhook]) {
    assert.deepEqual(rpcKeysForEvent(source, "checkout.session.completed"), expectedRpcKeys);
    assert.deepEqual(rpcKeysForEvent(source, "charge.refunded"), expectedRpcKeys);
    assert.match(source, /event\.type !== "checkout\.session\.completed" && event\.type !== "charge\.refunded"/);
    assert.equal((source.match(/\.rpc\(\s*"airfnb_reconcile_stripe_event"/g) ?? []).length, 1);
    assert.doesNotMatch(source, /\.from\("airfnb_(payments|lock_fees|bookings|stripe_events)"\)/);
    assert.equal((source.match(/paymentIntents\.retrieve\(intentId\)/g) ?? []).length, 2);
    assert.doesNotMatch(source, /hasCompleteMetadata|\? undefined\s*:\s*\(await stripe\.paymentIntents\.retrieve/);
    assert.equal((source.match(/const intentMetadata = \(await stripe\.paymentIntents\.retrieve\(intentId\)\)\.metadata/g) ?? []).length, 2);
    assert.match(source, /resolveMetadata\(session\.metadata, intentMetadata\)/);
    assert.match(source, /resolveMetadata\(charge\.metadata, intentMetadata\)/);
    assert.match(source, /direct && inherited && direct !== inherited/);
    assert.match(source, /throw new Error\("conflicting reconciliation metadata"\)/);
    assert.match(source, /p_amount_minor: session\.amount_total/);
    assert.match(source, /p_amount_minor: charge\.amount/);
    assert.match(source, /p_refunded_amount_minor: charge\.amount_refunded/);
    assert.match(source, /return .*received: false.*500/s);
    assert.doesNotMatch(source, /console\.(?:log|warn|error)\([^\n]*(?:raw|secret|customer)/i);
  }

  assert.match(nextWebhook, /const raw = await req\.text\(\)/);
  assert.match(nextWebhook, /constructEvent\(raw, signature, signingSecret\)/);
  assert.match(edgeWebhook, /const raw = await req\.text\(\)/);
  assert.match(edgeWebhook, /constructEventAsync\(\s*raw,/);
});

test("The dev simulator is absent in production and uses only reconciliation", () => {
  const productionGate = devPay.indexOf('process.env.NODE_ENV === "production"');
  const bodyRead = devPay.indexOf("await req.json()");
  assert.ok(productionGate >= 0 && productionGate < bodyRead);
  assert.match(devPay, /return new NextResponse\(null, \{ status: 404 \}\)/);
  assert.doesNotMatch(devPay, /ENABLE_DEV_PAY|DEV_PAY_TOKEN/);
  const serviceProductionGate = lockFeeService.indexOf('process.env.NODE_ENV === "production"');
  const firstServiceRpc = lockFeeService.indexOf('.rpc(\n    "airfnb_supplier_lock_fee"', serviceProductionGate);
  assert.ok(serviceProductionGate >= 0 && serviceProductionGate < firstServiceRpc);
  assert.equal((lockFeeService.match(/\.rpc\(\s*"airfnb_reconcile_stripe_event"/g) ?? []).length, 1);
  assert.doesNotMatch(lockFeeService, /\.from\("airfnb_(payments|lock_fees|bookings)"\)[\s\S]{0,180}\.(?:insert|update|upsert|delete)\(/);
  for (const key of expectedRpcKeys) assert.match(lockFeeService, new RegExp(`${key}:`));
});
