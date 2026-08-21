import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import test from "node:test";

const root = resolve(import.meta.dirname, "..");
const read = (path) => readFileSync(resolve(root, path), "utf8");
const sha256 = (path) => createHash("sha256").update(read(path)).digest("hex");

const gateway = read("scripts/local-e2e-supabase-fixture.mjs");
const driver = read("scripts/test-local-e2e-go-live.sh");
const seed = read("tests/fixtures/local-e2e-seed.sql");

test("pins the independently verified predecessor chain", () => {
  assert.equal(
    sha256("supabase/migrations/20260820155322_stripe_canonical_reconciliation.sql"),
    "5c244501a3f2e7b9d5aef6fa9d40b48a101b3efe0221401e9c6207d03f927591",
  );
  assert.equal(
    sha256("supabase/migrations/20260820230518_supplier_acl_caller_reconciliation.sql"),
    "2fdd44ad5d0da55119a867b0aafc124cd3ffa5b963904656363cccd26c366e92",
  );
  assert.match(driver, /65559343e7ffdf3795e1267425c5c6693ea79be56ef0d45ac43c39233e8b99dd/);
});

test("binds every fixture surface to loopback and sanitizes the Next environment", () => {
  assert.match(gateway, /server\.listen\(Number\(args\["listen-port"\]\), "127\.0\.0\.1"/);
  assert.match(gateway, /LOOPBACK = new Set\(\["127\.0\.0\.1", "localhost", "::1"\]\)/);
  assert.match(driver, /env -i/);
  assert.match(driver, /app-root/);
  assert.match(driver, /cp -R "\$repository_root\/\$project_path"/);
  assert.match(driver, /ln -s "\$repository_root\/node_modules"/);
  assert.match(driver, /NEXT_PUBLIC_SUPABASE_URL="\$fixture_origin"/);
  assert.match(driver, /NEXT_PUBLIC_OAUTH_PROVIDERS=''/);
  assert.match(driver, /next" dev -H 127\.0\.0\.1/);
  assert.match(driver, /next" start -H 127\.0\.0\.1/);
  assert.match(driver, /LOCAL_E2E_PRODUCTION_SERVER_PASS/);
  assert.match(driver, /LOCAL_E2E_PRODUCTION_BROWSER_PASS/);
  assert.match(driver, /fb-tailor-prod-public-/);
  assert.match(driver, /fb-tailor-prod-supplier-a-/);
  assert.match(driver, /network route 'https:\/\/\*\*' --abort/);
  assert.match(driver, /\[REDACTED\]/);
  assert.match(driver, /Accept-Language.*pt-PT/);
  assert.doesNotMatch(`${gateway}\n${driver}`, /readFileSync\([^\n]*\.env\.local|source\s+[^\n]*\.env\.local|dotenv/);
  assert.doesNotMatch(`${gateway}\n${driver}`, /0\.0\.0\.0|server\.listen\([^\n]*::/);
});

test("uses ephemeral credentials and redacted logs", () => {
  assert.match(gateway, /randomBytes\(48\)/);
  assert.match(gateway, /randomBytes\(18\)/);
  assert.match(gateway, /mode: 0o600/);
  assert.match(driver, /fb-tailor-e2e-evidence-/);
  assert.match(driver, /chmod 700 "\$evidence_directory"/);
  assert.match(driver, /LOCAL_E2E_EVIDENCE_PASS/);
  assert.match(driver, /manifest\.json/);
  assert.match(gateway, /const safe = \{ at: .* method: .* path: .* status: .* actor: .* statement:/s);
  assert.match(gateway, /\^\[0-9A-Z\]\{5,8\}\$/);
  assert.match(gateway, /event_predates_binding/);
  assert.doesNotMatch(gateway, /safe = \{[^}]*authorization|safe = \{[^}]*password|safe = \{[^}]*cookie/s);
  assert.doesNotMatch(seed, /encrypted_password|changeme|service_role_key|jwt_secret/i);
});

test("keeps REST and RPC access on explicit allowlists", () => {
  for (const table of [
    "airfnb_profiles", "airfnb_v_truck_card", "airfnb_categories",
    "airfnb_event_requests", "airfnb_applications", "airfnb_favorites",
    "airfnb_truck_images", "airfnb_reviews", "airfnb_request_invitations",
    "airfnb_conversations", "airfnb_bookings",
  ]) assert.match(gateway, new RegExp(`name === "${table}"`));
  for (const rpc of [
    "airfnb_public_service_detail", "airfnb_supplier_services",
    "airfnb_find_matching_requests", "airfnb_match_scores_batch",
    "airfnb_own_application_truck", "airfnb_can_submit_application",
    "airfnb_private_event_requests", "airfnb_request_application_service_context",
    "airfnb_admin_metrics", "airfnb_admin_pending_trucks",
    "airfnb_accept_application", "airfnb_supplier_lock_fee",
    "airfnb_reconcile_stripe_event",
  ]) assert.match(gateway, new RegExp(`name === "${rpc}"`));
  assert.match(gateway, /throw new Error\(`table refused:/);
  assert.match(gateway, /throw new Error\(`RPC refused:/);
  assert.match(gateway, /spawnSync\(PSQL/);
  assert.match(gateway, /input: `begin;\\n\$\{sql\};\\ncommit;\\n`/);
  assert.doesNotMatch(gateway, /shell\s*:\s*true|\beval\s*\(|new Function|child_process\.exec\(/);
});

test("guards the scratch seed and cleanup lifecycle", () => {
  assert.match(seed, /current_database\(\) !~ '\^fb_tailor_e2e_/);
  assert.match(seed, /f2700000-0000-4000-8000-/);
  assert.match(driver, /trap cleanup EXIT INT TERM/);
  assert.match(driver, /rm -f -- "\$credentials_file"/);
  assert.match(driver, /pg_terminate_backend/);
  assert.match(driver, /datname like 'fb_tailor_e2e_%'/);
  assert.match(driver, /SOURCE_FINGERPRINT_PASS/);
  assert.match(driver, /ZERO_SCRATCH_RESIDUE_PASS/);
});

test("requires real browser interaction, tenant denial and local payment reconciliation", () => {
  assert.match(driver, /1440x900/);
  assert.match(driver, /390x844/);
  assert.match(driver, /SUPPLIER_CROSS_TENANT_BROWSER_DENIAL_PASS/);
  assert.match(driver, /MARKETPLACE_BROWSER_TRANSITION_PASS/);
  assert.match(driver, /LOCAL_DEV_PAYMENT_BROWSER_PASS/);
  assert.match(driver, /LOCAL_ONLY_NETWORK_PASS/);
  assert.match(driver, /LOCAL_E2E_PNPM_CHECK_PASS/);
  assert.match(driver, /LOCAL_E2E_LOOPBACK_BUILD_PASS/);
  assert.match(driver, /ZERO_CHILD_PIDS_PASS/);
  assert.match(driver, /document\.documentElement\.scrollWidth/);
  assert.match(driver, /DASHBOARD_GEOMETRY_PASS/);
  assert.match(driver, /viewport === 390/);
  assert.match(driver, /mainRect\.width > 320/);
  assert.match(driver, /keyRect\.width > 160/);
  assert.match(driver, /mobileNav\.scrollWidth <= mobileNav\.clientWidth \+ 1/);
  assert.match(driver, /desktopDisplay === 'none' && mobileDisplay !== 'none'/);
  assert.match(driver, /Math\.abs\(firstColumn - 260\) <= 1/);
  assert.match(driver, /Math\.abs\(sidebarRect\.width - 260\) <= 1/);
  assert.match(driver, /desktopDisplay !== 'none' && mobileDisplay === 'none'/);
  assert.equal((driver.match(/assert_dashboard_geometry "\$supplier_session" 'mobile'/g) ?? []).length, 1);
  assert.equal((driver.match(/assert_dashboard_geometry "\$prod_supplier_session" 'mobile'/g) ?? []).length, 1);
  assert.match(driver, /document\.querySelector\("main, \[role=main\], h1"\)/);
  assert.match(driver, /console --json/);
  assert.match(driver, /assert_browser_diagnostics/);
  assert.match(driver, /errorsEnvelope\.data\.errors\.length !== 0/);
  assert.match(driver, /type === "error"/);
  assert.match(driver, /scroll-behavior: smooth/);
  assert.match(driver, /Largest Contentful Paint/);
  assert.doesNotMatch(driver, /console --json[^\n]*\|\| true|errors --json[^\n]*\|\| true/);
  assert.match(driver, /production dev payment CTA exposed/);
  assert.match(driver, /data-nextjs-dialog/);
});

test("logout E2E uses native same-origin POST navigation", () => {
  assert.match(driver, /submit_same_origin_logout\(\) \{/);
  assert.match(driver, /form\.method = ["']post["']/);
  assert.match(driver, /form\.action = `\$\{window\.location\.origin\}\/logout`/);
  assert.match(driver, /Origin[\s\S]*Sec-Fetch-Site: same-origin[\s\S]*Set-Cookie[\s\S]*303/);
  assert.equal((driver.match(/submit_same_origin_logout "\$(?:organizer_session|prod_organizer_session)"/g) ?? []).length, 2);
  assert.doesNotMatch(driver, /open "\$app_origin\/logout"/);
});
