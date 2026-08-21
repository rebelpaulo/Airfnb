#!/usr/bin/env node

import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import { chmodSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { spawnSync } from "node:child_process";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DB_RE = /^fb_tailor_e2e_[a-z0-9_]+$/;
const PORT_RE = /^(?:[1-9][0-9]{0,4})$/;
const EMAIL_RE = /^[a-z0-9][a-z0-9._+-]{0,80}@example\.invalid$/i;
const LOOPBACK = new Set(["127.0.0.1", "localhost", "::1"]);

function fail(message) {
  process.stderr.write(`local fixture refused: ${message}\n`);
  process.exit(64);
}

function parseArgs(argv) {
  const out = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith("--") || value == null) fail("malformed arguments");
    out[key.slice(2)] = value;
  }
  const required = ["socket", "port", "database", "listen-port", "app-origin", "credentials-file", "request-log"];
  for (const key of required) if (!out[key]) fail(`missing --${key}`);
  if (!DB_RE.test(out.database)) fail("unsafe database name");
  if (!PORT_RE.test(out.port) || !PORT_RE.test(out["listen-port"])) fail("invalid port");
  const app = new URL(out["app-origin"]);
  if (app.protocol !== "http:" || !LOOPBACK.has(app.hostname)) fail("app origin must be loopback HTTP");
  return { ...out, appOrigin: app.origin };
}

const args = parseArgs(process.argv.slice(2));
const PSQL = "/opt/homebrew/bin/psql";
const jwtSecret = randomBytes(48).toString("base64url");
const commonPassword = `${randomBytes(18).toString("base64url")}aA9!`;
const signupEmail = `signup-e2e-${process.pid}@example.invalid`;

const ACTORS = new Map([
  ["organizer-e2e@example.invalid", { id: "f2700000-0000-4000-8000-000000000001", role: "organizer", label: "organizer", name: "Organizador E2E" }],
  ["supplier-a-e2e@example.invalid", { id: "f2700000-0000-4000-8000-000000000002", role: "owner", label: "supplier_a", name: "Fornecedor A E2E" }],
  ["supplier-b-e2e@example.invalid", { id: "f2700000-0000-4000-8000-000000000003", role: "owner", label: "supplier_b", name: "Fornecedor B E2E" }],
  ["admin-e2e@example.invalid", { id: "f2700000-0000-4000-8000-000000000004", role: "admin", label: "admin", name: "Admin E2E" }],
]);
const ACTOR_LABELS = new Map([...ACTORS.values()].map((actor) => [actor.id, actor.label]));

function base64url(value) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

function signJwt(payload) {
  const header = base64url({ alg: "HS256", typ: "JWT" });
  const body = base64url(payload);
  const signature = createHmac("sha256", jwtSecret).update(`${header}.${body}`).digest("base64url");
  return `${header}.${body}.${signature}`;
}

const nowSeconds = () => Math.floor(Date.now() / 1000);
const anonToken = signJwt({ role: "anon", aud: "authenticated", iat: nowSeconds(), exp: nowSeconds() + 86400 });
const serviceToken = signJwt({ role: "service_role", aud: "authenticated", iat: nowSeconds(), exp: nowSeconds() + 86400 });

function userFor(email, actor) {
  return {
    id: actor.id,
    aud: "authenticated",
    role: "authenticated",
    email,
    email_confirmed_at: new Date(0).toISOString(),
    app_metadata: { provider: "email", providers: ["email"] },
    user_metadata: { full_name: actor.name },
    identities: [],
    created_at: new Date(0).toISOString(),
    updated_at: new Date(0).toISOString(),
  };
}

function sessionFor(email, actor) {
  const issued = nowSeconds();
  const access = signJwt({
    sub: actor.id,
    email,
    role: "authenticated",
    aud: "authenticated",
    app_metadata: { provider: "email", providers: ["email"] },
    user_metadata: { full_name: actor.name },
    iat: issued,
    exp: issued + 3600,
  });
  const refresh = signJwt({ sub: actor.id, role: "refresh_token", iat: issued, exp: issued + 86400 });
  return { access_token: access, refresh_token: refresh, expires_in: 3600, expires_at: issued + 3600, token_type: "bearer", user: userFor(email, actor) };
}

function verifyJwt(token, expectedRole) {
  if (typeof token !== "string" || token.length > 4096) return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const expected = createHmac("sha256", jwtSecret).update(`${parts[0]}.${parts[1]}`).digest();
  let supplied;
  try { supplied = Buffer.from(parts[2], "base64url"); } catch { return null; }
  if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) return null;
  let payload;
  try { payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8")); } catch { return null; }
  if (!payload || payload.exp < nowSeconds() || (expectedRole && payload.role !== expectedRole)) return null;
  return payload;
}

const credentials = {
  app_origin: args.appOrigin,
  fixture_origin: `http://127.0.0.1:${args["listen-port"]}`,
  anon_key: anonToken,
  service_role_key: serviceToken,
  password: commonPassword,
  signup_email: signupEmail,
  actors: Object.fromEntries([...ACTORS].map(([email, actor]) => [actor.role === "owner" ? (email.includes("supplier-a") ? "supplier_a" : "supplier_b") : actor.role, { email, id: actor.id }])),
};
writeFileSync(args["credentials-file"], `${JSON.stringify(credentials)}\n`, { mode: 0o600 });
chmodSync(args["credentials-file"], 0o600);

const SQL = Object.freeze({
  profile: `select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) from (
    select id, role, full_name, display_name, avatar_url, locale, company_name,
           onboarding_completed, organizer_rating_avg, organizer_rating_count
      from public.airfnb_profiles where id = auth.uid()
  ) q`,
  truck_cards: `select coalesce(jsonb_agg(to_jsonb(q) order by q.rating_avg desc, q.id), '[]'::jsonb) from (
    select id, slug, name, tagline, base_city, capacity, base_price, price_per_pax,
           min_event_pax, max_event_pax, service_radius_km, cuisine_types, dietary_options,
           catering_type, serves, setup_minutes, teardown_minutes, power_required_kw,
           sanitation_required, compatible_event_kinds, rating_avg, rating_count, featured,
           status, cover_url, gallery_urls, category_slugs, service_type
      from public.airfnb_v_truck_card
     where (:'slug' = '' or slug = :'slug')
       and (:'featured' = '' or featured = nullif(:'featured', '')::boolean)
     order by rating_avg desc, id limit 60
  ) q`,
  categories: `select coalesce(jsonb_agg(to_jsonb(q) order by q.name_pt), '[]'::jsonb) from (
    select id, slug, name_pt, name_en, icon from public.airfnb_categories
  ) q`,
  event_requests: `select coalesce(jsonb_agg(to_jsonb(q) order by q.start_at), '[]'::jsonb) from (
    select id, organizer_id, title, kind, description, start_at, end_at, city, locality,
           expected_pax, slots_needed, budget_min, budget_max, applications_deadline,
           status, visibility, discovery_mode, accepted_deal_types, min_fixed_fee,
           min_revenue_share_pct, notes, desired_cuisines, dietary_requirements,
           energy_need, power_available, energy_assistance, sanitation_level, setup_minutes,
           created_at
      from public.airfnb_event_requests
     where (:'id' = '' or id = nullif(:'id', '')::uuid)
       and (:'organizer' = '' or organizer_id = nullif(:'organizer', '')::uuid)
       and (:'status' = '' or status::text = :'status')
       and (:'visibility' = '' or visibility::text = :'visibility')
     order by start_at limit 80
  ) q`,
  event_requests_public: `select coalesce(jsonb_agg(to_jsonb(q) order by q.start_at), '[]'::jsonb) from (
    select id, title, kind, description, start_at, city, expected_pax, slots_needed,
           budget_min, budget_max, status, visibility, accepted_deal_types,
           min_fixed_fee, min_revenue_share_pct
      from public.airfnb_event_requests
     where (:'id' = '' or id = nullif(:'id', '')::uuid)
       and (:'status' = '' or status::text = :'status')
       and (:'visibility' = '' or visibility::text = :'visibility')
     order by start_at limit 80
  ) q`,
  applications: `select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc), '[]'::jsonb) from (
    select application.id, application.request_id, application.truck_id,
           application.proposed_price, application.cover_message, application.estimated_servings,
           application.available_confirmed, application.status, application.deal_type,
           application.proposed_fixed_to_organizer, application.proposed_revenue_share_pct,
           application.created_at, application.updated_at,
           jsonb_build_object('id', request_row.id, 'title', request_row.title,
             'start_at', request_row.start_at, 'city', request_row.city,
             'status', request_row.status) as airfnb_event_requests
      from public.airfnb_applications application
      join public.airfnb_event_requests request_row on request_row.id = application.request_id
     where (:'request' = '' or application.request_id = nullif(:'request', '')::uuid)
       and (:'truck' = '' or application.truck_id = nullif(:'truck', '')::uuid)
       and (:'trucks' = '' or application.truck_id = any(string_to_array(nullif(:'trucks', ''), ',')::uuid[]))
       and (:'ids' = '' or application.id = any(string_to_array(nullif(:'ids', ''), ',')::uuid[]))
  ) q`,
  favorites: `select coalesce(jsonb_agg(jsonb_build_object('truck_id', truck_id)), '[]'::jsonb)
    from public.airfnb_favorites where user_id = auth.uid()`,
  truck_images: `select coalesce(jsonb_agg(to_jsonb(q) order by q.sort_order), '[]'::jsonb) from (
    select id, truck_id, url, alt, sort_order, is_cover, kind
      from public.airfnb_truck_images
     where (:'truck' = '' or truck_id = nullif(:'truck', '')::uuid)
       and (:'trucks' = '' or truck_id = any(string_to_array(nullif(:'trucks', ''), ',')::uuid[]))
  ) q`,
  reviews: `select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc), '[]'::jsonb) from (
    select review.id, review.rating_overall, review.body, review.reply_body, review.reply_at,
           review.is_verified, review.created_at,
           jsonb_build_object('display_name', null, 'full_name', null) as reviewer
      from public.airfnb_reviews review
     where review.truck_id = (:'truck')::uuid limit 6
  ) q`,
  invitations: `select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) from (
    select request_id, truck_id, responded, invited_at from public.airfnb_request_invitations
     where request_id = (:'request')::uuid
  ) q`,
  conversations: `select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) from (
    select id, application_id from public.airfnb_conversations
     where (:'ids' = '' or application_id = any(string_to_array(nullif(:'ids', ''), ',')::uuid[]))
  ) q`,
  bookings: `select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) from (
    select id, application_id, status, ics_token, currency, created_at from public.airfnb_bookings
     where (:'application' = '' or application_id = nullif(:'application', '')::uuid)
       and (:'ids' = '' or application_id = any(string_to_array(nullif(:'ids', ''), ',')::uuid[])) limit 2
  ) q`,
  insert_application: `with inserted as (
    insert into public.airfnb_applications(request_id, truck_id, proposed_price, cover_message, estimated_servings)
    values ((:'request')::uuid, (:'truck')::uuid, (:'price')::numeric, :'message', nullif(:'servings','')::integer)
    returning id, request_id, truck_id, status
  ) select coalesce(jsonb_agg(to_jsonb(inserted)), '[]'::jsonb) from inserted`,
  signup_user: `with created as (
    insert into auth.users(id, email, raw_user_meta_data)
    values ((:'id')::uuid, :'email', jsonb_build_object('full_name', :'name'))
    returning id
  ), updated as (
    update public.airfnb_profiles set role = (:'role')::public.airfnb_user_role,
      full_name = :'name', display_name = :'name', onboarding_completed = false
    where id = (select id from created) returning id
  ) select jsonb_build_object('ok', exists(select 1 from updated))`,
  update_signup_profile: `with updated as (
    update public.airfnb_profiles
       set role = (:'role')::public.airfnb_user_role,
           full_name = :'name', display_name = :'name'
     where id = auth.uid() and id = (:'id')::uuid
    returning id
  ) select coalesce(jsonb_agg(to_jsonb(updated)), '[]'::jsonb) from updated`,
});

function pgOptions(role, actorId) {
  if (role === "postgres") return "-c statement_timeout=5000 -c lock_timeout=2000";
  const parts = [`-c role=${role}`, "-c statement_timeout=5000", "-c lock_timeout=2000", `-c request.jwt.claim.role=${role}`];
  if (actorId) parts.push(`-c request.jwt.claim.sub=${actorId}`);
  return parts.join(" ");
}

function query(statement, role, actorId, variables = {}) {
  const sql = SQL[statement] ?? statement;
  const command = ["-X", "--no-psqlrc", `--host=${args.socket}`, `--port=${args.port}`, `--dbname=${args.database}`, "--set=ON_ERROR_STOP=1", "--set=VERBOSITY=verbose", "--quiet", "--tuples-only", "--no-align"];
  for (const [key, value] of Object.entries(variables)) command.push(`--set=${key}=${value ?? ""}`);
  const result = spawnSync(PSQL, command, {
    encoding: "utf8",
    timeout: 8_000,
    input: `begin;\n${sql};\ncommit;\n`,
    env: { LANG: "C", LC_ALL: "C", PGOPTIONS: pgOptions(role, actorId) },
  });
  if (result.status !== 0) {
    const error = new Error(`database statement failed: ${statement}`);
    error.statement = statement;
    error.code = (result.stderr.match(/SQL state: ([0-9A-Z]{5})/)?.[1] ?? result.stderr.match(/ERROR:\s+([0-9A-Z]{5})/)?.[1] ?? "PGRST000");
    const reason = [
      ["stripe event predates marketplace binding", "event_predates_binding"],
      ["stripe amount or currency mismatch", "amount_currency_mismatch"],
      ["invalid stripe event time", "invalid_event_time"],
      ["stripe amount is invalid", "invalid_amount"],
      ["stripe currency must be EUR", "invalid_currency"],
      ["checkout session is not a paid, non-refund event", "invalid_checkout_state"],
      ["lock fee payment arrived after due time", "payment_after_due"],
    ].find(([message]) => result.stderr.includes(message));
    error.reason = reason?.[1] ?? null;
    throw error;
  }
  const output = result.stdout.trim();
  return output === "" ? null : JSON.parse(output);
}

function appendLog(entry) {
  const safeCode = typeof entry.code === "string" && /^[0-9A-Z]{5,8}$/.test(entry.code) ? entry.code : null;
  const safeReason = typeof entry.reason === "string" && /^[a-z_]{3,40}$/.test(entry.reason) ? entry.reason : null;
  const safe = { at: new Date().toISOString(), method: entry.method, path: entry.path, status: entry.status, actor: entry.actor ?? "anon", statement: entry.statement ?? null, rows: Number.isInteger(entry.rows) ? entry.rows : null, code: safeCode, reason: safeReason };
  writeFileSync(args["request-log"], `${JSON.stringify(safe)}\n`, { flag: "a", mode: 0o600 });
}

function json(res, status, value, extraHeaders = {}) {
  const body = value == null ? "" : JSON.stringify(value);
  res.writeHead(status, { "content-type": "application/json", "cache-control": "no-store", "content-length": Buffer.byteLength(body), "access-control-allow-origin": args.appOrigin, "access-control-expose-headers": "content-range", ...extraHeaders });
  res.end(body);
}

async function readJson(req, max = 32_768) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > max) throw new Error("body too large");
    chunks.push(chunk);
  }
  const raw = Buffer.concat(chunks).toString("utf8");
  return raw ? JSON.parse(raw) : {};
}

function bearer(req) {
  const value = req.headers.authorization ?? "";
  return value.startsWith("Bearer ") ? value.slice(7) : "";
}

function context(req) {
  const token = bearer(req);
  const authPayload = verifyJwt(token, "authenticated");
  if (authPayload?.sub && UUID_RE.test(authPayload.sub)) return { role: "authenticated", actorId: authPayload.sub, actor: ACTOR_LABELS.get(authPayload.sub) ?? "signup" };
  if (token === serviceToken) return { role: "service_role", actorId: null, actor: "service_role" };
  return { role: "anon", actorId: null, actor: "anon" };
}

function eq(search, name, validator = () => true) {
  const raw = search.get(name) ?? "";
  if (!raw) return "";
  if (!raw.startsWith("eq.")) throw new Error(`unsupported ${name} filter`);
  const value = raw.slice(3);
  if (!validator(value)) throw new Error(`invalid ${name} filter`);
  return value;
}

function inValues(search, name) {
  const raw = search.get(name) ?? "";
  if (!raw) return "";
  const match = raw.match(/^in\.\(([^)]*)\)$/);
  if (!match) throw new Error(`unsupported ${name} filter`);
  const values = match[1].split(",").filter(Boolean);
  if (values.length > 80 || values.some((value) => !UUID_RE.test(value))) throw new Error(`invalid ${name} filter`);
  return values.join(",");
}

function eqOrIn(search, name) {
  const raw = search.get(name) ?? "";
  if (!raw) return { one: "", many: "" };
  if (raw.startsWith("eq.")) {
    const one = raw.slice(3);
    if (!UUID_RE.test(one)) throw new Error(`invalid ${name} filter`);
    return { one, many: "" };
  }
  return { one: "", many: inValues(search, name) };
}

function validateSearch(search, allowed) {
  const harmless = new Set(["select", "order", "limit", "offset"]);
  for (const key of search.keys()) if (!allowed.has(key) && !harmless.has(key)) throw new Error(`unsupported query key ${key}`);
}

function tableRequest(name, search, ctx) {
  if (name === "airfnb_profiles") {
    validateSearch(search, new Set(["id"]));
    if (ctx.role !== "authenticated") return { statement: "profile", variables: {}, data: [] };
    const requested = eq(search, "id", (v) => UUID_RE.test(v));
    if (requested && requested !== ctx.actorId) throw new Error("foreign profile refused");
    return { statement: "profile", variables: {} };
  }
  if (name === "airfnb_v_truck_card") {
    validateSearch(search, new Set(["slug", "featured"]));
    return { statement: "truck_cards", variables: { slug: eq(search, "slug", (v) => /^[a-z0-9-]{1,200}$/.test(v)), featured: eq(search, "featured", (v) => /^(true|false)$/.test(v)) } };
  }
  if (name === "airfnb_categories") {
    validateSearch(search, new Set());
    return { statement: "categories", variables: {} };
  }
  if (name === "airfnb_event_requests") {
    validateSearch(search, new Set(["id", "organizer_id", "status", "visibility", "assistance_requested"]));
    return { statement: ctx.role === "anon" ? "event_requests_public" : "event_requests", variables: {
      id: eq(search, "id", (v) => UUID_RE.test(v)), organizer: eq(search, "organizer_id", (v) => UUID_RE.test(v)),
      status: eq(search, "status", (v) => /^[a-z_]{1,32}$/.test(v)), visibility: eq(search, "visibility", (v) => /^(public|invite_only)$/.test(v)),
    } };
  }
  if (name === "airfnb_applications") {
    validateSearch(search, new Set(["id", "request_id", "truck_id"]));
    const truckFilter = eqOrIn(search, "truck_id");
    return { statement: "applications", variables: {
      request: eq(search, "request_id", (v) => UUID_RE.test(v)), truck: truckFilter.one,
      trucks: truckFilter.many, ids: inValues(search, "id"),
    } };
  }
  if (name === "airfnb_favorites") {
    validateSearch(search, new Set(["user_id", "truck_id"]));
    return { statement: "favorites", variables: {} };
  }
  if (name === "airfnb_truck_images") {
    validateSearch(search, new Set(["truck_id"]));
    const truckFilter = eqOrIn(search, "truck_id");
    return { statement: "truck_images", variables: { truck: truckFilter.one, trucks: truckFilter.many } };
  }
  if (name === "airfnb_reviews") {
    validateSearch(search, new Set(["truck_id"]));
    const truck = eq(search, "truck_id", (v) => UUID_RE.test(v));
    if (!truck) throw new Error("truck_id required");
    return { statement: "reviews", variables: { truck } };
  }
  if (name === "airfnb_request_invitations") {
    validateSearch(search, new Set(["request_id"]));
    const request = eq(search, "request_id", (v) => UUID_RE.test(v));
    if (!request) throw new Error("request_id required");
    return { statement: "invitations", variables: { request } };
  }
  if (name === "airfnb_conversations") {
    validateSearch(search, new Set(["application_id"]));
    return { statement: "conversations", variables: { ids: inValues(search, "application_id") } };
  }
  if (name === "airfnb_bookings") {
    validateSearch(search, new Set(["application_id", "status"]));
    const applicationFilter = eqOrIn(search, "application_id");
    return { statement: "bookings", variables: { application: applicationFilter.one, ids: applicationFilter.many } };
  }
  throw new Error(`table refused: ${name}`);
}

function exactKeys(body, allowed) {
  if (!body || Array.isArray(body) || typeof body !== "object") throw new Error("object body required");
  const actual = Object.keys(body).sort();
  const expected = [...allowed].sort();
  if (actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) throw new Error("body keys refused");
}

function uuid(value, nullable = false) {
  if (nullable && value === null) return "";
  if (typeof value !== "string" || !UUID_RE.test(value)) throw new Error("valid UUID required");
  return value;
}

function uuidList(value, max = 80) {
  if (!Array.isArray(value) || value.length === 0 || value.length > max || value.some((item) => typeof item !== "string" || !UUID_RE.test(item))) {
    throw new Error("valid UUID array required");
  }
  return value.join(",");
}

function integer(value, min, max) {
  if (!Number.isInteger(value) || value < min || value > max) throw new Error("integer out of range");
  return String(value);
}

function rpcRequest(name, body, search) {
  if (name === "airfnb_public_service_detail") {
    exactKeys(body, ["p_slug"]);
    if (typeof body.p_slug !== "string" || !/^[a-z0-9-]{1,200}$/.test(body.p_slug)) throw new Error("slug refused");
    return { label: name, shape: "scalar", sql: `select coalesce(public.airfnb_public_service_detail(:'slug'), 'null'::jsonb)`, variables: { slug: body.p_slug } };
  }
  if (name === "airfnb_supplier_services") {
    exactKeys(body, ["p_truck"]);
    const status = eq(search, "status", (value) => /^(active|draft|pending_review|paused|archived)$/.test(value));
    validateSearch(search, new Set(["status"]));
    return { label: name, shape: "rows", sql: `select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at, q.id), '[]'::jsonb) from (
      select * from public.airfnb_supplier_services(nullif(:'truck','')::uuid)
       where (:'status' = '' or status::text = :'status')
    ) q`, variables: { truck: uuid(body.p_truck, true), status } };
  }
  if (name === "airfnb_find_matching_requests") {
    exactKeys(body, ["p_limit", "p_truck"]);
    validateSearch(search, new Set());
    return { label: name, shape: "rows", sql: `select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) from public.airfnb_find_matching_requests((:'truck')::uuid, (:'limit')::integer) q`, variables: { truck: uuid(body.p_truck), limit: integer(body.p_limit, 1, 80) } };
  }
  if (name === "airfnb_match_scores_batch") {
    exactKeys(body, ["p_request_ids", "p_truck_ids"]);
    validateSearch(search, new Set());
    return { label: name, shape: "rows", sql: `select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) from public.airfnb_match_scores_batch(string_to_array(:'trucks', ',')::uuid[], string_to_array(:'requests', ',')::uuid[]) q`, variables: { trucks: uuidList(body.p_truck_ids), requests: uuidList(body.p_request_ids) } };
  }
  if (name === "airfnb_own_application_truck") {
    exactKeys(body, []);
    validateSearch(search, new Set());
    return { label: name, shape: "rows", sql: `select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) from public.airfnb_own_application_truck() q`, variables: {} };
  }
  if (name === "airfnb_can_submit_application") {
    exactKeys(body, ["p_request", "p_truck"]);
    validateSearch(search, new Set());
    return { label: name, shape: "scalar", sql: `select to_jsonb(public.airfnb_can_submit_application((:'request')::uuid, (:'truck')::uuid))`, variables: { request: uuid(body.p_request), truck: uuid(body.p_truck) } };
  }
  if (name === "airfnb_private_event_requests") {
    exactKeys(body, ["p_request_id"]);
    validateSearch(search, new Set());
    return { label: name, shape: "rows", sql: `select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) from public.airfnb_private_event_requests(nullif(:'request','')::uuid) q`, variables: { request: uuid(body.p_request_id, true) } };
  }
  if (name === "airfnb_request_application_service_context") {
    exactKeys(body, ["p_request"]);
    validateSearch(search, new Set());
    return { label: name, shape: "rows", sql: `select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) from public.airfnb_request_application_service_context((:'request')::uuid) q`, variables: { request: uuid(body.p_request) } };
  }
  if (name === "airfnb_admin_metrics") {
    exactKeys(body, []);
    validateSearch(search, new Set());
    return { label: name, shape: "rows", sql: `select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) from public.airfnb_admin_metrics() q`, variables: {} };
  }
  if (name === "airfnb_admin_pending_trucks") {
    exactKeys(body, ["p_limit"]);
    validateSearch(search, new Set());
    return { label: name, shape: "rows", sql: `select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) from public.airfnb_admin_pending_trucks((:'limit')::integer) q`, variables: { limit: integer(body.p_limit, 1, 80) } };
  }
  if (name === "airfnb_accept_application") {
    exactKeys(body, ["p_application"]);
    validateSearch(search, new Set());
    return { label: name, shape: "scalar", sql: `select public.airfnb_accept_application((:'application')::uuid)`, variables: { application: uuid(body.p_application) } };
  }
  if (name === "airfnb_supplier_lock_fee") {
    exactKeys(body, ["p_application"]);
    validateSearch(search, new Set());
    return { label: name, shape: "rows", sql: `select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) from public.airfnb_supplier_lock_fee((:'application')::uuid) q`, variables: { application: uuid(body.p_application) } };
  }
  if (name === "airfnb_reconcile_stripe_event") {
    const keys = ["p_application_id", "p_amount_minor", "p_booking_id", "p_currency", "p_event_created_at", "p_event_id", "p_event_type", "p_lock_fee_id", "p_payment_intent", "p_payment_status", "p_refunded_amount_minor"];
    exactKeys(body, keys);
    if (typeof body.p_event_id !== "string" || !/^dev-lock-fee-[0-9a-f-]{36}$/.test(body.p_event_id)) throw new Error("event id refused");
    if (body.p_payment_intent !== body.p_event_id || body.p_event_type !== "checkout.session.completed" || body.p_currency !== "EUR" || body.p_payment_status !== "paid") throw new Error("dev payment contract refused");
    if (typeof body.p_event_created_at !== "string" || !Number.isFinite(Date.parse(body.p_event_created_at))) throw new Error("event time refused");
    return { label: name, shape: "scalar", sql: `select public.airfnb_reconcile_stripe_event(
      :'event_id', :'event_type', (:'event_at')::timestamptz, (:'application')::uuid,
      (:'lock_fee')::uuid, (:'booking')::uuid, :'payment_intent', (:'amount')::bigint,
      :'currency', :'payment_status', (:'refunded')::bigint
    )`, variables: {
      event_id: body.p_event_id, event_type: body.p_event_type, event_at: body.p_event_created_at,
      application: uuid(body.p_application_id), lock_fee: uuid(body.p_lock_fee_id), booking: uuid(body.p_booking_id),
      payment_intent: body.p_payment_intent, amount: integer(body.p_amount_minor, 1, 100_000_000),
      currency: body.p_currency, payment_status: body.p_payment_status,
      refunded: integer(body.p_refunded_amount_minor, 0, 100_000_000),
    } };
  }
  throw new Error(`RPC refused: ${name}`);
}

function apiKeyAllowed(req) {
  const key = req.headers.apikey;
  return key === anonToken || key === serviceToken;
}

async function handleAuth(req, res, url) {
  if (req.method === "POST" && url.pathname === "/auth/v1/token") {
    const grant = url.searchParams.get("grant_type");
    const body = await readJson(req);
    if (grant === "password") {
      exactKeys(body, ["email", "password", "gotrue_meta_security"]);
      const email = typeof body.email === "string" ? body.email.toLowerCase() : "";
      const actor = ACTORS.get(email);
      if (!actor || body.password !== commonPassword) return json(res, 400, { code: "invalid_credentials", message: "Invalid login credentials" });
      return json(res, 200, sessionFor(email, actor));
    }
    if (grant === "refresh_token") {
      if (!body || typeof body.refresh_token !== "string") return json(res, 400, { message: "refresh token required" });
      const payload = verifyJwt(body.refresh_token, "refresh_token");
      const actorEntry = [...ACTORS].find(([, actor]) => actor.id === payload?.sub);
      if (!actorEntry) return json(res, 400, { message: "invalid refresh token" });
      return json(res, 200, sessionFor(actorEntry[0], actorEntry[1]));
    }
    return json(res, 400, { message: "grant refused" });
  }
  if (req.method === "POST" && url.pathname === "/auth/v1/signup") {
    const body = await readJson(req);
    if (!body || typeof body !== "object" || body.email !== signupEmail || body.password !== commonPassword) return json(res, 400, { message: "signup fixture identity refused" });
    const name = typeof body.data?.full_name === "string" ? body.data.full_name.trim().slice(0, 80) : "Novo Organizador E2E";
    const role = body.data?.role === "owner" ? "owner" : "organizer";
    const actor = { id: "f2700000-0000-4000-8000-000000000005", role, name };
    if (!ACTORS.has(signupEmail)) {
      query("signup_user", "postgres", null, { id: actor.id, email: signupEmail, name, role });
      ACTORS.set(signupEmail, actor);
      ACTOR_LABELS.set(actor.id, "signup");
    }
    return json(res, 200, sessionFor(signupEmail, actor));
  }
  if (req.method === "GET" && url.pathname === "/auth/v1/user") {
    const payload = verifyJwt(bearer(req), "authenticated");
    const entry = [...ACTORS].find(([, actor]) => actor.id === payload?.sub);
    if (!entry) return json(res, 401, { message: "invalid token" });
    return json(res, 200, userFor(entry[0], entry[1]));
  }
  if (req.method === "POST" && url.pathname === "/auth/v1/logout") return json(res, 204, null);
  return json(res, 404, { message: "auth endpoint refused" });
}

async function handleRest(req, res, url, ctx) {
  if (!apiKeyAllowed(req)) return json(res, 401, { code: "PGRST301", message: "invalid API key" });
  if (url.pathname.startsWith("/rest/v1/rpc/")) {
    if (req.method !== "POST") throw new Error("RPC method refused");
    const name = url.pathname.slice("/rest/v1/rpc/".length);
    const body = await readJson(req);
    const spec = rpcRequest(name, body, url.searchParams);
    const data = query(spec.sql, ctx.role, ctx.actorId, spec.variables);
    appendLog({ method: req.method, path: url.pathname, status: 200, actor: ctx.actor, statement: spec.label, rows: Array.isArray(data) ? data.length : null });
    return json(res, 200, data);
  }

  const table = url.pathname.slice("/rest/v1/".length);
  if (!/^[a-z0-9_]+$/.test(table)) throw new Error("table path refused");
  if (req.method === "GET" || req.method === "HEAD") {
    const spec = tableRequest(table, url.searchParams, ctx);
    const data = spec.data ?? query(spec.statement, ctx.role, ctx.actorId, spec.variables);
    const count = Array.isArray(data) ? data.length : 0;
    appendLog({ method: req.method, path: url.pathname, status: 200, actor: ctx.actor, statement: spec.statement });
    if (req.method === "HEAD") return json(res, 200, null, { "content-range": count ? `0-${count - 1}/${count}` : "*/0" });
    return json(res, 200, data, { "content-range": count ? `0-${count - 1}/${count}` : "*/0" });
  }
  if (req.method === "POST" && table === "airfnb_applications") {
    if (ctx.role !== "authenticated") return json(res, 401, { code: "42501", message: "authentication required" });
    const body = await readJson(req);
    exactKeys(body, ["cover_message", "estimated_servings", "proposed_price", "request_id", "truck_id"]);
    if (typeof body.cover_message !== "string" || body.cover_message.length < 30 || body.cover_message.length > 4000) throw new Error("application body refused");
    if (typeof body.proposed_price !== "number" || body.proposed_price <= 0 || body.proposed_price > 1_000_000) throw new Error("price refused");
    if (body.estimated_servings !== null && (!Number.isInteger(body.estimated_servings) || body.estimated_servings < 0 || body.estimated_servings > 100000)) throw new Error("servings refused");
    const data = query("insert_application", ctx.role, ctx.actorId, {
      request: uuid(body.request_id), truck: uuid(body.truck_id), price: String(body.proposed_price), message: body.cover_message, servings: body.estimated_servings == null ? "" : String(body.estimated_servings),
    });
    appendLog({ method: req.method, path: url.pathname, status: 201, actor: ctx.actor, statement: "insert_application" });
    const representation = (req.headers.prefer ?? "").includes("return=representation");
    return json(res, 201, representation ? data : null);
  }
  if (req.method === "PATCH" && table === "airfnb_profiles") {
    if (ctx.role !== "authenticated" || ctx.actor !== "signup") return json(res, 403, { code: "42501", message: "signup profile only" });
    validateSearch(url.searchParams, new Set(["id"]));
    const id = eq(url.searchParams, "id", (value) => UUID_RE.test(value));
    if (id !== ctx.actorId) throw new Error("foreign profile update refused");
    const body = await readJson(req);
    exactKeys(body, ["full_name", "role"]);
    if (!/^(organizer|owner)$/.test(body.role) || typeof body.full_name !== "string" || body.full_name.trim().length < 2 || body.full_name.length > 80) throw new Error("signup profile body refused");
    const data = query("update_signup_profile", ctx.role, ctx.actorId, { id, role: body.role, name: body.full_name.trim() });
    appendLog({ method: req.method, path: url.pathname, status: 200, actor: ctx.actor, statement: "update_signup_profile", rows: data.length });
    return json(res, 200, data);
  }
  throw new Error("table mutation refused");
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url ?? "/", `http://127.0.0.1:${args["listen-port"]}`);
  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "access-control-allow-origin": args.appOrigin,
      "access-control-allow-methods": "GET,HEAD,POST,PATCH,OPTIONS",
      "access-control-allow-headers": "accept-profile,authorization,apikey,content-profile,content-type,prefer,range,x-client-info,x-retry-count,x-supabase-api-version",
      "access-control-max-age": "300",
    });
    return res.end();
  }
  const origin = req.headers.origin;
  if (origin && origin !== args.appOrigin) return json(res, 403, { message: "origin refused" });
  try {
    if (url.pathname.startsWith("/auth/v1/")) {
      await handleAuth(req, res, url);
      return appendLog({ method: req.method, path: url.pathname, status: res.statusCode, actor: "auth", statement: "auth_allowlist" });
    }
    if (url.pathname.startsWith("/rest/v1/")) return await handleRest(req, res, url, context(req));
    if (req.method === "GET" && url.pathname === "/health") return json(res, 200, { status: "ok" });
    appendLog({ method: req.method, path: url.pathname, status: 404, actor: "anon", statement: "refused" });
    return json(res, 404, { message: "endpoint refused" });
  } catch (error) {
    appendLog({ method: req.method, path: url.pathname, status: 400, actor: context(req).actor, statement: error.statement ?? "refused", code: error.code, reason: error.reason });
    return json(res, 400, { code: error.code ?? "PGRST100", message: "local fixture request refused" });
  }
});

server.on("error", (error) => fail(error.message));
server.listen(Number(args["listen-port"]), "127.0.0.1", () => {
  process.stdout.write(`LOCAL_E2E_FIXTURE_READY port=${args["listen-port"]}\n`);
});

function shutdown() {
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 2_000).unref();
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
