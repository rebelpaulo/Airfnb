import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const page = read("app/dashboard/truck/lock/[id]/page.tsx");
const checkoutRoute = read("app/api/stripe/checkout/route.ts");
const devRoute = read("app/api/dev/mark-paid/route.ts");
const service = read("lib/payments/lock-fee.server.ts");

test("lock-fee mutations share a server-only boundary without forwarding credentials", () => {
  assert.match(service, /^import "server-only";/);
  assert.match(service, /normalizeAppOrigin\(configuredAppUrl\)/);
  assert.doesNotMatch(service, /console\.(?:log|warn|error)/);

  assert.doesNotMatch(page, /\bfetch\s*\(/);
  assert.doesNotMatch(page, /\bcookies\s*\(|cookieHeader|authorization/i);
  assert.equal((page.match(/await supa\.auth\.getUser\(\)/g) ?? []).length, 3);
  assert.match(page, /createLockFeeCheckout\(\{ applicationId: id, user, supplier: supa \}\)/);
  assert.match(page, /markLockFeePaidDev\(\{ applicationId: id, supplier: supa \}\)/);
  assert.match(
    page,
    /const showDev =\s*process\.env\.NODE_ENV !== "production" &&\s*!process\.env\.STRIPE_SECRET_KEY &&/,
  );

  for (const route of [checkoutRoute, devRoute]) {
    assert.match(route, /const sb = await supabaseServer\(\);/);
    assert.match(route, /await sb\.auth\.getUser\(\)/);
    assert.match(route, /\{ error: "unauthenticated" \}, \{ status: 401 \}/);
    assert.doesNotMatch(route, /cookieHeader|authorization/i);
  }
  assert.match(checkoutRoute, /createLockFeeCheckout\(\{ applicationId, user, supplier: sb \}\)/);
  assert.match(devRoute, /markLockFeePaidDev\(\{ applicationId, supplier: sb \}\)/);
});

test("routes authenticate before revealing non-production request details", () => {
  const checkoutAuth = checkoutRoute.indexOf("await sb.auth.getUser()");
  assert.ok(checkoutAuth >= 0);
  assert.ok(checkoutAuth < checkoutRoute.indexOf("process.env.STRIPE_SECRET_KEY"));
  assert.ok(checkoutAuth < checkoutRoute.indexOf("await req.json()"));

  const productionGate = devRoute.indexOf('process.env.NODE_ENV === "production"');
  const devAuth = devRoute.indexOf("await sb.auth.getUser()");
  assert.ok(productionGate >= 0 && productionGate < devAuth);
  assert.ok(devAuth < devRoute.indexOf("process.env.SUPABASE_SERVICE_ROLE_KEY"));
  assert.ok(devAuth < devRoute.indexOf("await req.json()"));
});

test("the dev service rejects production before every database boundary", () => {
  const devStart = service.indexOf("export async function markLockFeePaidDev");
  const devSource = service.slice(devStart);
  const productionGate = devSource.indexOf('process.env.NODE_ENV === "production"');
  const supplierRpc = devSource.indexOf('"airfnb_supplier_lock_fee"');
  const adminClient = devSource.indexOf("supabaseAdmin()");

  assert.ok(devStart >= 0);
  assert.ok(productionGate >= 0 && productionGate < supplierRpc);
  assert.ok(productionGate < adminClient);
  assert.match(devSource, /return failure\(404, "not found"\)/);
});

test("dev reconciliation preserves validated PostgreSQL microseconds", () => {
  const postgresTimestamp = "2026-08-21T12:34:56.123456+00:00";
  assert.equal(Date.parse(postgresTimestamp), Date.parse("2026-08-21T12:34:56.123Z"));
  assert.equal(new Date(postgresTimestamp).toISOString(), "2026-08-21T12:34:56.123Z");
  assert.notEqual(postgresTimestamp, new Date(postgresTimestamp).toISOString());

  const devStart = service.indexOf("export async function markLockFeePaidDev");
  const devSource = service.slice(devStart);
  assert.match(
    devSource,
    /const eventCreatedAt = typeof booking\.created_at === "string" \? booking\.created_at : "";/,
  );
  assert.match(devSource, /const createdAt = Date\.parse\(eventCreatedAt\);/);
  assert.match(devSource, /!Number\.isFinite\(createdAt\)/);
  assert.match(devSource, /p_event_created_at: eventCreatedAt,/);
  assert.doesNotMatch(devSource, /p_event_created_at: new Date\([^)]*\)\.toISOString\(\)/);
});
