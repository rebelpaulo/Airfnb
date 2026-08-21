import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");

const migration = read("supabase/migrations/20260820154358_marketplace_workflow_reconciliation.sql");
const organizer = read("app/dashboard/organizer/pedidos/[id]/page.tsx");
const supplierLock = read("app/dashboard/truck/lock/[id]/page.tsx");
const requestDetail = read("app/pedidos/[id]/page.tsx");
const application = read("app/pedidos/[id]/aplicar/page.tsx");
const types = read("types/database.ts");
const runtime = read("tests/marketplace-workflow-reconciliation-runtime.sql");
const driver = read("scripts/test-marketplace-workflow-reconciliation.sh");

test("migration is one bounded fail-closed transaction", () => {
  assert.equal((migration.match(/^begin;$/gmu) ?? []).length, 1);
  assert.equal((migration.match(/^commit;$/gmu) ?? []).length, 1);
  assert.match(migration, /set local lock_timeout = '5s';/u);
  assert.match(migration, /lock table[\s\S]+in access exclusive mode;/u);
  assert.match(migration, /privacy, fee or catalog helper drifted/u);
  assert.match(migration, /messaging accept predecessor drifted/u);
  assert.match(migration, /application policy catalog drifted/u);
  assert.match(migration, /existing workflow data is ambiguous/u);
  assert.match(migration, /predecessor contract changed/u);
  assert.doesNotMatch(migration, /\/private\/tmp|fb-tailor-pgsocket|supabase\s+(link|db push)/u);
});

test("applications and financial tables use least privilege", () => {
  const helperStart = migration.indexOf(
    "function public.airfnb_can_submit_application(",
  );
  const helperBody = migration.slice(
    helperStart,
    migration.indexOf("$function$;", helperStart) + 11,
  );
  const helperSqlStart = helperBody.indexOf("as $function$") + 13;
  const helperSqlBody = helperBody.slice(
    helperSqlStart,
    helperBody.indexOf("$function$;", helperSqlStart),
  );
  const insertPolicyStart = migration.indexOf(
    'create policy "airfnb_app_insert_guarded"',
  );
  const insertPolicy = migration.slice(
    insertPolicyStart,
    migration.indexOf("revoke all on table public.airfnb_applications", insertPolicyStart),
  );
  assert.match(migration, /create policy "airfnb_app_select_participant"[\s\S]+to authenticated/u);
  assert.match(migration, /airfnb_can_manage_truck\(airfnb_applications\.truck_id::text\)/u);
  assert.match(helperBody, /returns boolean\s+language sql\s+stable\s+security definer\s+set search_path = ''/u);
  assert.match(helperBody, /auth\.uid\(\) is not null[\s\S]+truck\.owner_id = auth\.uid\(\)/u);
  assert.match(helperBody, /truck\.status = 'active'[\s\S]+request_row\.status = 'open'/u);
  assert.match(helperBody, /request_row\.start_at > pg_catalog\.now\(\)[\s\S]+applications_deadline/u);
  assert.match(helperBody, /request_row\.visibility = 'public'[\s\S]+airfnb_request_invitations/u);
  assert.doesNotMatch(helperBody, /airfnb_is_admin|airfnb_can_manage_truck|user_metadata|app_metadata/u);
  assert.equal(
    createHash("md5").update(helperSqlBody).digest("hex"),
    "c96f49df5f1b05fabea73bfdbf534a74",
  );
  assert.equal(
    (migration.match(/c96f49df5f1b05fabea73bfdbf534a74/gu) ?? []).length,
    2,
  );
  assert.match(insertPolicy, /status = 'submitted'[\s\S]+shortlisted_at is null[\s\S]+decided_at is null[\s\S]+withdrawn_at is null/u);
  assert.match(insertPolicy, /airfnb_can_submit_application\([\s\S]+request_id,[\s\S]+truck_id/u);
  assert.doesNotMatch(insertPolicy, /from public\.|airfnb_can_manage_truck|airfnb_is_admin/u);
  assert.match(migration, /revoke all on function public\.airfnb_can_submit_application\(uuid, uuid\)[\s\S]+grant execute[\s\S]+to authenticated;/u);
  assert.match(migration, /not v_final and v_submit_helper[\s\S]+c96f49df5f1b05fabea73bfdbf534a74/u);
  assert.match(migration, /application submission helper postcondition/u);
  const ownTruckStart = migration.indexOf(
    "function public.airfnb_own_application_truck()",
  );
  const ownTruckBody = migration.slice(
    ownTruckStart,
    migration.indexOf("$function$;", ownTruckStart) + 11,
  );
  const ownTruckSqlStart = ownTruckBody.indexOf("as $function$") + 13;
  const ownTruckSqlBody = ownTruckBody.slice(
    ownTruckSqlStart,
    ownTruckBody.indexOf("$function$;", ownTruckSqlStart),
  );
  assert.match(ownTruckBody, /returns table \([\s\S]+truck_id uuid,[\s\S]+truck_name text,[\s\S]+truck_status public\.airfnb_truck_status[\s\S]+stable\s+security definer\s+set search_path = ''/u);
  assert.match(ownTruckBody, /auth\.uid\(\) is not null[\s\S]+truck\.owner_id = auth\.uid\(\)[\s\S]+order by truck\.created_at, truck\.id[\s\S]+limit 1/u);
  assert.doesNotMatch(ownTruckBody, /airfnb_is_admin|airfnb_can_manage_truck|user_metadata|app_metadata/u);
  assert.equal(
    createHash("md5").update(ownTruckSqlBody).digest("hex"),
    "f8b910f51897ceb6b4fea4e1b049d02b",
  );
  assert.equal(
    (migration.match(/f8b910f51897ceb6b4fea4e1b049d02b/gu) ?? []).length,
    2,
  );
  assert.match(migration, /revoke all on function public\.airfnb_own_application_truck\(\)[\s\S]+grant execute[\s\S]+to authenticated;/u);
  assert.match(migration, /own application truck helper postcondition/u);
  assert.match(migration, /grant insert \([\s\S]+proposed_revenue_share_pct[\s\S]+\) on table public\.airfnb_applications to authenticated;/u);
  assert.doesNotMatch(migration, /grant (?:select, )?insert, update[\s\S]+airfnb_applications to authenticated/iu);
  assert.match(migration, /grant select on table public\.airfnb_bookings to authenticated;/u);
  assert.match(migration, /grant select on table public\.airfnb_booking_trucks to authenticated;/u);
  assert.match(migration, /grant select, insert, update, delete on table public\.airfnb_lock_fees\s+to service_role;/u);
  assert.doesNotMatch(migration, /grant select on table public\.airfnb_lock_fees to authenticated/u);
});

test("decision functions lock application then request and use exact actors", () => {
  for (const name of ["airfnb_shortlist_application", "airfnb_reject_application", "airfnb_accept_application"]) {
    const start = migration.indexOf(`function public.${name}`);
    assert.notEqual(start, -1);
    const body = migration.slice(start, migration.indexOf("$function$;", start) + 11);
    assert.ok(body.indexOf("from public.airfnb_applications") < body.indexOf("from public.airfnb_event_requests"));
    assert.match(body, /from public\.airfnb_applications[\s\S]+for update;/u);
    assert.match(body, /from public\.airfnb_event_requests[\s\S]+for update;/u);
    assert.match(body, /current_setting\('request\.jwt\.claim\.role', true\)[\s\S]+service_role/u);
    assert.match(body, /auth\.uid\(\)/u);
    assert.doesNotMatch(body, /user_metadata|app_metadata|current_user\s*=\s*'service_role'/u);
  }
  assert.match(migration, /errcode = '55000',[\s\S]+message = 'application is not eligible for acceptance'/u);
  assert.match(migration, /errcode = '55000',[\s\S]+message = 'request has no remaining slots'/u);
});

test("accept is atomic, multi-slot and leaves siblings untouched", () => {
  const acceptStart = migration.indexOf("function public.airfnb_accept_application");
  const acceptBody = migration.slice(
    acceptStart,
    migration.indexOf("$function$;", acceptStart) + 11,
  );
  assert.match(migration, /create unique index if not exists airfnb_bookings_application_unique[\s\S]+where application_id is not null;/u);
  assert.match(migration, /v_fee := public\.airfnb_calculate_lock_fee\(v_application\.id\);/u);
  assert.match(migration, /v_total is distinct from v_platform \+ v_organizer/u);
  assert.match(migration, /insert into public\.airfnb_bookings/u);
  assert.match(migration, /insert into public\.airfnb_booking_trucks/u);
  assert.match(migration, /insert into public\.airfnb_lock_fees/u);
  assert.match(migration, /insert into public\.airfnb_conversations/u);
  assert.match(migration, /insert into public\.airfnb_conversation_participants/u);
  assert.match(migration, /insert into public\.airfnb_notifications/u);
  assert.match(migration, /if v_accepted = v_request\.slots_needed then[\s\S]+set status = 'awarded'/u);
  const applicationUpdates = acceptBody.match(
    /update public\.airfnb_applications[\s\S]*?;/gu,
  ) ?? [];
  assert.ok(applicationUpdates.length > 0);
  for (const statement of applicationUpdates) {
    assert.doesNotMatch(statement, /request_id\s*=|status\s*=\s*'rejected'/u);
  }
});

test("supplier lock fee projection is narrow and owner scoped", () => {
  assert.match(migration, /function public\.airfnb_supplier_lock_fee\(p_application uuid\)/u);
  assert.match(migration, /language sql\s+stable\s+security definer\s+set search_path = ''/u);
  assert.match(migration, /truck\.owner_id = auth\.uid\(\)/u);
  assert.match(migration, /current_setting\('request\.jwt\.claim\.role', true\)[\s\S]+<> 'service_role'/u);
  assert.match(migration, /grant execute on function public\.airfnb_supplier_lock_fee\(uuid\)\s+to authenticated;/u);
  assert.match(migration, /has_function_privilege\(v_service_role, 'public\.airfnb_supplier_lock_fee\(uuid\)', 'EXECUTE'\)/u);
  assert.match(supplierLock, /\.rpc\("airfnb_supplier_lock_fee", \{ p_application: id \}\)/u);
  assert.doesNotMatch(supplierLock, /from\("airfnb_lock_fees"\)|owner_id/u);
});

test("callers propagate decision errors and fee copy is settings-safe", () => {
  assert.equal((organizer.match(/if \(error\) throw new Error\(error\.message\);/gu) ?? []).length, 3);
  assert.doesNotMatch(application, /€50|€25|25 ficam/u);
  assert.match(application, /taxa de confirmação aplicável[\s\S]+mostradas antes do pagamento/u);
  assert.equal(
    (application.match(/\.rpc\("airfnb_own_application_truck"\)/gu) ?? []).length,
    2,
  );
  assert.match(requestDetail, /\.rpc\("airfnb_own_application_truck"\)/u);
  assert.match(requestDetail, /\.rpc\("airfnb_can_submit_application", \{[\s\S]+p_request: id,[\s\S]+p_truck: myTruck\.truck_id/u);
  assert.doesNotMatch(application, /from\("airfnb_trucks"\)|owner_id|name="truck_id"/u);
  assert.doesNotMatch(requestDetail, /from\("airfnb_trucks"\)|owner_id/u);
});

test("cumulative database types include booking, fee and supplier RPC fields", () => {
  assert.match(types, /airfnb_bookings: \{[\s\S]+application_id: string \| null[\s\S]+ics_token: string \| null/u);
  assert.match(types, /foreignKeyName: "airfnb_bookings_application_id_fkey"[\s\S]+referencedRelation: "airfnb_applications"/u);
  assert.match(types, /interface AirfnbLockFeeRow[\s\S]+provider_event_log: Json;/u);
  assert.match(types, /airfnb_supplier_lock_fee: \{[\s\S]+lock_fee_status:/u);
  assert.match(types, /airfnb_can_submit_application: \{[\s\S]+p_request: string[\s\S]+p_truck: string[\s\S]+Returns: boolean/u);
  assert.match(types, /airfnb_own_application_truck: \{[\s\S]+truck_id: string[\s\S]+truck_name: string[\s\S]+truck_status:/u);
  assert.match(types, /airfnb_mark_conversation_read:/u);
  assert.match(types, /airfnb_private_event_requests:/u);
  assert.match(types, /airfnb_service_type: "food_truck" \| "catering" \| "bar"/u);
});

test("runtime and driver prove actors, races, rollback and cleanup", () => {
  for (const proof of [
    "application is not eligible for acceptance",
    "request has no remaining slots",
    "same-application retry produced side effects",
    "final-slot loser changed application state",
    "non-winning sibling changed state",
    "metadata role unexpectedly authorized",
    "supplier lock fee leaked cross-tenant data",
    "oversized fee failure was not atomic",
    "application submission helper matrix",
    "own application truck projection",
  ]) assert.match(runtime, new RegExp(proof, "u"));
  assert.match(driver, /90dbaf281ea0c9209373fe16964e1aaaa34152f0272ef067fdee80f831fdc60c/u);
  assert.match(driver, /validate_scratch/u);
  assert.match(driver, /source_fingerprint/u);
  assert.match(driver, /expected fail-closed migration failure did not occur/iu);
  assert.match(driver, /scratch residue: 0/u);
  assert.doesNotMatch(driver, /\/private\/tmp\/fb-tailor-pgsocket|supabase\s+(link|db push)|curl|https?:\/\//u);
});
