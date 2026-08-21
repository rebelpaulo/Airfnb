import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");

const migration = read("supabase/migrations/20260820154054_messaging_reviews_reconciliation.sql");
const conversation = read("app/dashboard/conversa/[id]/page.tsx");
const organizerReview = read("app/dashboard/organizer/avaliar/[bookingId]/page.tsx");
const truckReview = read("app/dashboard/truck/avaliar/[bookingId]/page.tsx");
const types = read("types/database.ts");
const runtime = read("tests/messaging-reviews-reconciliation-runtime.sql");
const driver = read("scripts/test-messaging-reviews-reconciliation.sh");

test("migration is one bounded, fail-closed transaction", () => {
  assert.equal((migration.match(/^begin;$/gmu) ?? []).length, 1);
  assert.equal((migration.match(/^commit;$/gmu) ?? []).length, 1);
  assert.match(migration, /set local lock_timeout = '5s';/u);
  assert.match(migration, /set local statement_timeout = '60s';/u);
  assert.match(migration, /lock table[\s\S]+in access exclusive mode;/u);
  assert.match(migration, /auth\.uid identity contract differs/u);
  assert.match(migration, /table owner\/RLS precondition differs/u);
  assert.match(migration, /source messaging\/review data precondition differs/u);
  assert.match(migration, /predecessor policy catalog differs/u);
  assert.match(migration, /predecessor API ACL differs/u);
  assert.match(migration, /review trigger catalog differs/u);
  assert.match(migration, /explicit service_role table ACL changed/u);
  assert.doesNotMatch(migration, /\/private\/tmp|fb-tailor-pgsocket/u);
});

test("payment-aware accept body is altered but never replaced", () => {
  assert.match(
    migration,
    /alter function public\.airfnb_accept_application\(uuid\)\s+set search_path = pg_catalog, public;/u,
  );
  assert.doesNotMatch(
    migration,
    /create\s+or\s+replace\s+function\s+public\.airfnb_accept_application/iu,
  );
  assert.match(migration, /md5\(p\.prosrc\) = 'b7c875f8b312e246e2f4621f5748b0a1'/u);
  assert.match(migration, /p\.prosrc like '%platform_fee%'/u);
  assert.match(migration, /p\.prosrc like '%organizer_share%'/u);
  assert.match(migration, /accept-application body\/ACL\/owner changed/u);
});

test("messaging contracts are participant/admin isolated and narrow", () => {
  assert.match(migration, /create policy "airfnb_convs_select_participant"[\s\S]+to authenticated/u);
  assert.match(migration, /create policy "airfnb_cp_select_participant"[\s\S]+to authenticated/u);
  assert.match(migration, /create policy "airfnb_msg_select_participant"[\s\S]+to authenticated/u);
  assert.match(migration, /create policy "airfnb_msg_insert_participant"[\s\S]+sender_id = \(select auth\.uid\(\)\)/u);
  assert.match(
    migration,
    /grant insert \(conversation_id, sender_id, body, attachments\)\s+on table public\.airfnb_messages to authenticated;/u,
  );
  assert.match(migration, /create or replace function public\.airfnb_mark_conversation_read\(p_conversation uuid\)/u);
  assert.match(migration, /greatest\([\s\S]+statement_timestamp\(\)/u);
  assert.match(migration, /raise exception using errcode = '42501', message = 'conversation access denied'/u);
  assert.match(migration, /revoke all on function public\.airfnb_mark_conversation_read\(uuid\)[\s\S]+service_role/u);
  assert.match(conversation, /\.rpc\("airfnb_mark_conversation_read", \{\s*p_conversation: id/u);
  assert.doesNotMatch(conversation, /last_read_at:\s*new Date/u);
  assert.doesNotMatch(conversation, /from\("airfnb_conversation_participants"\)\s*\.update/u);
});

test("review inserts expose inputs only and triggers derive trusted fields", () => {
  assert.match(
    migration,
    /grant insert \(booking_id, truck_id, rating_food, rating_service, rating_value, body\)\s+on table public\.airfnb_reviews to authenticated;/u,
  );
  assert.match(
    migration,
    /grant insert \(booking_id, truck_id, rating_reliability, rating_communication, rating_payment, body\)\s+on table public\.airfnb_organizer_reviews to authenticated;/u,
  );
  for (const controlled of ["organizer_id", "rating_overall", "is_verified", "created_at", "reply_body", "reply_at"]) {
    assert.match(migration, new RegExp(`new\\.${controlled} :=`, "u"));
  }
  assert.match(migration, /new\.rating_food not between 1 and 5/u);
  assert.match(migration, /new\.rating_reliability not between 1 and 5/u);
  assert.match(migration, /b\.status[\s\S]+not in \('confirmed', 'completed'\)/u);
  assert.match(migration, /airfnb_booking_trucks bt/u);
  assert.doesNotMatch(organizerReview, /organizer_id\s*:/u);
  assert.doesNotMatch(organizerReview, /rating_overall\s*:/u);
  assert.doesNotMatch(organizerReview, /is_verified\s*:/u);
  assert.doesNotMatch(truckReview, /organizer_id\s*:/u);
  assert.doesNotMatch(truckReview, /rating_overall\s*:/u);
  assert.doesNotMatch(truckReview, /is_verified\s*:/u);
});

test("replies and aggregate maintenance have the narrow complete behavior", () => {
  assert.match(migration, /v_reply text := nullif\(btrim\(p_reply\), ''\)/u);
  assert.match(migration, /char_length\(v_reply\) > 2000/u);
  assert.match(migration, /errcode = '22023'/u);
  assert.match(migration, /errcode = '42501'/u);
  assert.match(migration, /after insert or delete or update of truck_id, rating_overall/u);
  assert.match(migration, /after insert or delete or update of organizer_id, rating_overall/u);
  assert.match(migration, /case when tg_op <> 'INSERT' then old\.truck_id/u);
  assert.match(migration, /case when tg_op <> 'DELETE' then new\.truck_id/u);
  assert.match(migration, /case when tg_op <> 'INSERT' then old\.organizer_id/u);
  assert.match(migration, /case when tg_op <> 'DELETE' then new\.organizer_id/u);
  assert.match(migration, /organizer overall helper is not orphaned/u);
  assert.match(migration, /drop function if exists public\.airfnb_organizer_review_overall\(\);/u);
});

test("generated database types include the reconciled tables and RPCs", () => {
  assert.match(types, /airfnb_conversations: \{[\s\S]+application_id: string \| null/u);
  assert.match(types, /airfnb_organizer_reviews: \{[\s\S]+rating_reliability: number \| null/u);
  assert.match(types, /airfnb_mark_conversation_read: \{\s*Args: \{ p_conversation: string \};\s*Returns: void;/u);
  assert.match(types, /airfnb_reply_to_organizer_review: \{\s*Args: \{ p_reply: string; p_review: string \};/u);
  assert.match(types, /airfnb_reply_to_truck_review: \{\s*Args: \{ p_reply: string; p_review: string \};/u);
  assert.match(types, /export type OrganizerReviews =/u);
});

test("runtime proof covers legitimate and adversarial paths", () => {
  for (const proof of [
    "forged sender unexpectedly succeeded",
    "forged message key unexpectedly succeeded",
    "future read marker unexpectedly succeeded",
    "outsider mark-read unexpectedly succeeded",
    "wrong-actor truck review unexpectedly succeeded",
    "duplicate truck review unexpectedly succeeded",
    "direct truck review update unexpectedly succeeded",
    "direct organizer review delete unexpectedly succeeded",
    "blank supplier reply unexpectedly succeeded",
    "oversized organizer reply unexpectedly succeeded",
    "truck old/new aggregate rebind failed",
    "organizer old/new aggregate rebind failed",
  ]) {
    assert.match(runtime, new RegExp(proof, "u"));
  }
  assert.match(runtime, /rollback;\s*\\echo 'messaging-reviews runtime: PASS'/u);
});

test("driver owns, validates, fingerprints and cleans only its scratch clone", () => {
  assert.match(driver, /scratch="fb_tailor_mr_\$\{\$\}_\$\{RANDOM\}"/u);
  assert.match(driver, /fb-tailor-messaging-reconciliation:/u);
  assert.match(driver, /validate_scratch/u);
  assert.match(driver, /Refusing to drop unvalidated scratch database/u);
  assert.match(driver, /source_schema_fingerprint/u);
  assert.match(driver, /source_state_fingerprint/u);
  assert.match(driver, /grant select, update on table public\.airfnb_conversations to service_role/u);
  assert.match(driver, /Explicit service_role table ACL changed/u);
  assert.match(driver, /psql "\$\{connection\[@\]\}" -d "\$scratch" -f "\$migration"/u);
  assert.match(driver, /Expected fail-closed migration failure did not occur/u);
  assert.match(driver, /Failed migration did not roll back cleanly/u);
  assert.match(driver, /scratch cleanup: PASS/u);
  assert.doesNotMatch(driver, /\/private\/tmp\/fb-tailor-pgsocket/u);
  assert.doesNotMatch(driver, /supabase\s+(link|db push)|curl|https?:\/\//u);
});
