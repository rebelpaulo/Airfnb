import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const sha256 = (value) => createHash("sha256").update(value).digest("hex");

const MIGRATION_NAME = "20260820230518_supplier_acl_caller_reconciliation.sql";
const MIGRATION_PATH = `supabase/migrations/${MIGRATION_NAME}`;
const STRIPE_MIGRATION_PATH =
  "supabase/migrations/20260820155322_stripe_canonical_reconciliation.sql";
const STRIPE_MIGRATION_SHA256 =
  "5c244501a3f2e7b9d5aef6fa9d40b48a101b3efe0221401e9c6207d03f927591";
const STRIPE_BODY_MD5 = "296b93ed41a788acf9ecb099e78695ff";

const migration = read(MIGRATION_PATH);
const stripeMigration = read(STRIPE_MIGRATION_PATH);
const types = read("types/database.ts");

const rpcContracts = [
  {
    name: "airfnb_supplier_services",
    signature: "uuid",
    volatility: "stable",
    grantees: ["authenticated"],
  },
  {
    name: "airfnb_public_service_detail",
    signature: "text",
    volatility: "stable",
    grantees: ["anon", "authenticated"],
  },
  {
    name: "airfnb_invitation_candidates",
    signature: "uuid",
    volatility: "stable",
    grantees: ["authenticated"],
  },
  {
    name: "airfnb_invite_request_services",
    signature: "uuid, uuid[]",
    volatility: "volatile",
    grantees: ["authenticated"],
  },
  {
    name: "airfnb_booking_service_context",
    signature: "uuid",
    volatility: "stable",
    grantees: ["authenticated"],
  },
  {
    name: "airfnb_request_application_service_context",
    signature: "uuid",
    volatility: "stable",
    grantees: ["authenticated"],
  },
  {
    name: "airfnb_supplier_export_data",
    signature: "",
    volatility: "stable",
    grantees: ["authenticated"],
  },
];

const stripeOwnedPaths = [
  {
    path: "app/api/stripe/checkout/route.ts",
    sha256: "1d4bc67a26cd22c88c913bd7045cc3bc946c9302ce4d0dd60f134f590ddec14b",
    marker: /createLockFeeCheckout\(\{ applicationId, user, supplier: sb \}\)/,
  },
  {
    path: "app/api/dev/mark-paid/route.ts",
    sha256: "c1c4bf17e1918130d2d2f4a1d7508861ac1ac9d589a2c94f45bfad6edaf082db",
    marker: /markLockFeePaidDev\(\{ applicationId, supplier: sb \}\)/,
  },
];
const lockFeeService = read("lib/payments/lock-fee.server.ts");
const LOCK_FEE_SERVICE_SHA256 = "489d7e05e840f90dfa2a0fa359eea2959f6a0f07fa61256b6262a9540327bd41";

// This is the ticket's pinned 20-path follower map. Markers document the
// intentional disposition of every caller and make omissions visible.
const followerPaths = [
  ["app/onboarding/truck/page.tsx", /\.rpc\(\s*"airfnb_supplier_services"/],
  ["app/registar/page.tsx", /\.rpc\(\s*"airfnb_supplier_services"/],
  ["app/dashboard/truck/page.tsx", /\.rpc\(\s*"airfnb_supplier_services"/],
  ["app/dashboard/truck/[id]/page.tsx", /\.rpc\(\s*"airfnb_supplier_services"/],
  ["app/dashboard/truck/perfil/page.tsx", /\.rpc\(\s*"airfnb_supplier_services"/],
  ["app/dashboard/truck/oportunidades/page.tsx", /\.rpc\(\s*"airfnb_supplier_services"/],
  [
    "app/dashboard/truck/oportunidades/[id]/page.tsx",
    /\.rpc\(\s*"airfnb_can_submit_application"/,
  ],
  ["app/dashboard/truck/aplicacoes/page.tsx", /\.rpc\(\s*"airfnb_supplier_services"/],
  ["app/catalogo/page.tsx", /\.from\(\s*"airfnb_categories"\s*\)/],
  ["app/catalogo/[slug]/page.tsx", /\.rpc\(\s*"airfnb_public_service_detail"/],
  ["app/dashboard/truck/novo/page.tsx", /\.from\(\s*"airfnb_categories"\s*\)/],
  ["app/publicar/page.tsx", /\.from\(\s*"airfnb_categories"\s*\)/],
  ["components/TruckPhotoUpload.tsx", /\.from\(\s*"airfnb_truck_images"\s*\)/],
  [
    "app/dashboard/organizer/eventos/page.tsx",
    /\.rpc\(\s*"airfnb_booking_service_context"/,
  ],
  [
    "app/dashboard/organizer/avaliar/[bookingId]/page.tsx",
    /\.rpc\(\s*"airfnb_booking_service_context"/,
  ],
  [
    "app/dashboard/organizer/pedidos/[id]/page.tsx",
    /\.rpc\(\s*"airfnb_request_application_service_context"/,
  ],
  [
    "app/dashboard/organizer/pedidos/[id]/convidar/page.tsx",
    /\.rpc\(\s*"airfnb_invitation_candidates"/,
  ],
  ["app/dashboard/conversas/page.tsx", /\.rpc\(\s*"airfnb_conversation_summaries"/],
  [
    "app/dashboard/truck/avaliar/[bookingId]/page.tsx",
    /\.rpc\(\s*"airfnb_booking_service_context"/,
  ],
  ["app/api/me/export/route.ts", /\.rpc\(\s*"airfnb_supplier_export_data"/],
];

function functionBlock(name) {
  const match = migration.match(
    new RegExp(
      `create or replace function public\\.${name}\\([\\s\\S]*?\\n\\$function\\$;`,
      "i",
    ),
  );
  assert.ok(match, `missing function body for ${name}`);
  return match[0];
}

function compact(source) {
  return source
    .replaceAll(/\/\*[\s\S]*?\*\//g, " ")
    .replaceAll(/\/\/[^\n]*/g, " ")
    .replaceAll(/\s+/g, " ");
}

function escapeRegex(value) {
  return value.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function applicationInsertCallers(directory = "app") {
  const callers = [];

  for (const entry of readdirSync(new URL(`../${directory}/`, import.meta.url), {
    withFileTypes: true,
  })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      callers.push(...applicationInsertCallers(path));
      continue;
    }
    if (!/\.[cm]?[jt]sx?$/.test(entry.name)) continue;

    const source = read(path);
    const inserts = [
      ...source.matchAll(
        /\.from\(\s*["']airfnb_applications["']\s*\)\s*\.insert\(\s*\{([\s\S]*?)\}\s*\)/g,
      ),
    ];
    for (const insert of inserts) callers.push({ path, source, body: insert[1] });
  }

  return callers;
}

test("the one CLI migration follows the exact independently verified Stripe predecessor", () => {
  const matching = readdirSync(new URL("../supabase/migrations", import.meta.url))
    .filter((name) => name.endsWith("_supplier_acl_caller_reconciliation.sql"));
  assert.deepEqual(matching, [MIGRATION_NAME]);
  assert.ok(Number(MIGRATION_NAME.slice(0, 14)) > 20260820155322);
  assert.equal(sha256(stripeMigration), STRIPE_MIGRATION_SHA256);

  assert.match(migration, /^--[\s\S]*\nbegin;/);
  assert.match(migration, /\ncommit;\s*$/);
  assert.equal((migration.match(/\nbegin;/g) ?? []).length, 1);
  assert.equal((migration.match(/\ncommit;/g) ?? []).length, 1);
  assert.match(migration, /airfnb_reconcile_stripe_event\(text,text,timestamptz,uuid,uuid,uuid,text,bigint,text,text,bigint\)/);
  assert.match(migration, new RegExp(STRIPE_BODY_MD5));
  assert.match(migration, /Stripe predecessor drifted/);
  assert.match(migration, /Stripe function changed/);
});

test("the migration defines exactly seven narrow SECURITY DEFINER contracts", () => {
  const definitions = [
    ...migration.matchAll(/create or replace function public\.(airfnb_[a-z_]+)\s*\(/g),
  ].map((match) => match[1]);
  assert.deepEqual(definitions.sort(), rpcContracts.map(({ name }) => name).sort());

  for (const contract of rpcContracts) {
    const block = functionBlock(contract.name);
    assert.match(block, /security definer/i, `${contract.name} must be SECURITY DEFINER`);
    assert.match(block, /set search_path = ''/i, `${contract.name} must clear search_path`);
    assert.match(block, new RegExp(`\\n${contract.volatility}\\n`, "i"));
    assert.doesNotMatch(block, /\bexecute\b/i, `${contract.name} must not use dynamic SQL`);
    assert.doesNotMatch(block, /returns\s+setof\b/i, `${contract.name} must not return base rows`);
    assert.doesNotMatch(block, /\bselect\s+(?:[a-z_]+\.)?\*/i, `${contract.name} must project fields explicitly`);

    const signature = contract.signature
      .split(/\s+/)
      .map(escapeRegex)
      .join("\\s*");
    assert.match(
      migration,
      new RegExp(
        `revoke all on function public\\.${contract.name}\\(${signature}\\)\\s+from public, anon, authenticated, service_role;`,
        "i",
      ),
    );
    const grantees = contract.grantees.join(",\\s*");
    assert.match(
      migration,
      new RegExp(
        `grant execute on function public\\.${contract.name}\\(${signature}\\)\\s+to ${grantees};`,
        "i",
      ),
    );
  }

  assert.match(migration, /p\.proowner <> v_owner/);
  assert.match(migration, /p\.proconfig is distinct from array\['search_path=""'\]::text\[\]/);
  assert.match(migration, /pg_catalog\.aclexplode/);
  assert.match(migration, /privilege\.grantee = 0/);
  assert.match(migration, /privilege\.is_grantable/);
});

test("private contracts authenticate, reject service_role and keep the public detail singular", () => {
  for (const { name } of rpcContracts.filter(({ name }) => name !== "airfnb_public_service_detail")) {
    const block = functionBlock(name);
    assert.match(block, /auth\.uid\(\)/i, `${name} must evaluate auth.uid()`);
    assert.match(block, /\bis (?:not )?null\b/i, `${name} must reject an absent caller`);
    assert.match(block, /request\.jwt\.claim\.role/);
    assert.match(block, /service_role/);
  }

  const publicDetail = functionBlock("airfnb_public_service_detail");
  assert.match(publicDetail, /truck\.status = 'active'/);
  assert.match(publicDetail, /return v_payload/);
  assert.doesNotMatch(publicDetail, /'owner_id'|'email'|'phone'|'storage_path'|'review_notes'/i);
  assert.doesNotMatch(publicDetail, /'homologation_expires_at'|'insurance_expires_at'/i);
  for (const limit of [12, 100, 50, 8]) {
    assert.match(publicDetail, new RegExp(`limit ${limit}\\b`));
  }
});

test("base-table SELECT remains closed except for the two pinned column grants", () => {
  assert.match(
    migration,
    /foreach v_role in array array\['anon'::name, 'authenticated'::name, 'service_role'::name\]/,
  );
  assert.match(
    migration,
    /has_column_privilege\(v_role, 'public\.airfnb_trucks', 'owner_id', 'SELECT'\)/,
  );
  for (const table of [
    "airfnb_trucks",
    "airfnb_truck_images",
    "airfnb_truck_categories",
    "airfnb_categories",
  ]) {
    assert.doesNotMatch(migration, new RegExp(`grant select on table public\\.${table}\\b`, "i"));
  }
  assert.doesNotMatch(migration, /grant select\s*\([^)]*owner_id/i);
  assert.match(
    migration,
    /grant select \(name_pt, name_en, icon\)\s+on table public\.airfnb_categories\s+to anon, authenticated, service_role;/i,
  );
  assert.match(
    migration,
    /grant select \(id\)\s+on table public\.airfnb_truck_images\s+to authenticated;/i,
  );
  assert.match(migration, /not pg_catalog\.has_column_privilege\('authenticated', 'public\.airfnb_truck_images', 'id', 'SELECT'\)/);
  assert.match(migration, /pg_catalog\.has_column_privilege\('anon', 'public\.airfnb_truck_images', 'id', 'SELECT'\)/);
  assert.match(migration, /pg_catalog\.has_column_privilege\('service_role', 'public\.airfnb_truck_images', 'id', 'SELECT'\)/);
});

test("the review insert policy is narrowly rebound to the pinned ownership helper", () => {
  assert.match(migration, /ownership helper drifted/);
  assert.match(migration, /982caee25d35d0ac9dfe1d3a343ab0a5/);
  assert.match(migration, /eb6ed73b9db344da97e1be5244cefd54/);
  assert.match(migration, /64f6778971e136463d322c17b734dc76/);
  assert.match(
    migration,
    /alter policy airfnb_org_reviews_participant_insert[\s\S]*?public\.airfnb_can_manage_truck\(truck_id::text\)/,
  );
  assert.doesNotMatch(
    migration,
    /grant select\s*\([^)]*owner_id/i,
  );
  assert.match(migration, /policy\.polroles = array\['authenticated'::regrole::oid\]/);
});

test("the atomic invitation contract locks, validates and notifies only returned inserts", () => {
  const invite = functionBlock("airfnb_invite_request_services");
  const requestLock = invite.indexOf("for update;");
  const serviceLock = invite.indexOf("for share;");
  const eligibility = invite.indexOf("if v_expected <>");
  const invitationInsert = invite.indexOf("insert into public.airfnb_request_invitations");
  const notificationInsert = invite.indexOf("insert into public.airfnb_notifications");
  assert.ok(requestLock >= 0 && requestLock < serviceLock);
  assert.ok(serviceLock < eligibility && eligibility < invitationInsert);
  assert.ok(invitationInsert < notificationInsert);
  assert.match(invite, /select distinct item as truck_id/);
  assert.match(invite, /array_agg\(input\.truck_id order by input\.truck_id\)/);
  assert.match(invite, /cardinality\(v_trucks\) > 80/);
  assert.match(invite, /on conflict on constraint airfnb_request_invitations_pkey do nothing/i);
  assert.match(invite, /returning airfnb_request_invitations\.truck_id/i);
  assert.match(invite, /for v_inserted in[\s\S]*insert into public\.airfnb_notifications/i);
  assert.match(invite, /errcode = '22023'/);
  assert.match(invite, /errcode = '42501'/);

  for (const path of [
    "app/catalogo/[slug]/page.tsx",
    "app/dashboard/organizer/pedidos/[id]/convidar/page.tsx",
  ]) {
    const source = compact(read(path));
    assert.match(source, /\.rpc\(\s*"airfnb_invite_request_services"/);
    assert.doesNotMatch(source, /\.from\(\s*"airfnb_notifications"\s*\)/);
    assert.doesNotMatch(
      source,
      /\.from\(\s*"airfnb_request_invitations"\s*\)\s*\.(?:insert|upsert|update|delete)\(/,
    );
  }
});

test("the pinned 22-path caller map has two preserved Stripe paths and 20 dispositions", () => {
  assert.equal(stripeOwnedPaths.length, 2);
  assert.equal(followerPaths.length, 20);
  assert.equal(new Set([...stripeOwnedPaths.map(({ path }) => path), ...followerPaths.map(([path]) => path)]).size, 22);

  for (const dependency of stripeOwnedPaths) {
    const source = read(dependency.path);
    assert.equal(sha256(source), dependency.sha256, `${dependency.path} changed outside its ticket`);
    assert.match(source, dependency.marker);
    assert.doesNotMatch(source, /airfnb_trucks!inner\s*\(\s*owner_id\s*\)/);
    assert.doesNotMatch(source, /\.select\([^)]*owner_id/);
  }
  assert.equal(sha256(lockFeeService), LOCK_FEE_SERVICE_SHA256);
  assert.equal((lockFeeService.match(/\.rpc\(\s*"airfnb_supplier_lock_fee"/g) ?? []).length, 2);
  assert.doesNotMatch(lockFeeService, /airfnb_trucks!inner\s*\(\s*owner_id\s*\)/);
  assert.doesNotMatch(lockFeeService, /\.select\([^)]*owner_id/);

  const baseTables = [
    "airfnb_trucks",
    "airfnb_truck_images",
    "airfnb_truck_categories",
    "airfnb_categories",
  ];
  for (const [path, disposition] of followerPaths) {
    const source = read(path);
    const normalized = compact(source);
    assert.match(source, disposition, `${path} is missing its assigned interface/disposition`);
    assert.doesNotMatch(normalized, /\.eq\(\s*["']owner_id["']\s*,/);
    assert.doesNotMatch(normalized, /airfnb_trucks!inner\s*\([^)]*owner_id/);
    assert.doesNotMatch(
      normalized,
      /\.select\(\s*(?:`[^`]*owner_id[^`]*`|"[^"]*owner_id[^"]*"|'[^']*owner_id[^']*')\s*\)/,
    );
    for (const table of baseTables) {
      assert.doesNotMatch(
        normalized,
        new RegExp(`\\.from\\(\\s*["']${table}["']\\s*\\)\\s*\\.select\\(\\s*["']\\*["']\\s*\\)`),
        `${path} must not use select('*') on ${table}`,
      );
    }
  }

  assert.match(read("app/catalogo/[slug]/page.tsx"), /\.rpc\(\s*"airfnb_invite_request_services"/);
  assert.match(read("app/dashboard/organizer/pedidos/[id]/convidar/page.tsx"), /\.rpc\(\s*"airfnb_invite_request_services"/);
});

test("application inserts leave status to the database while preserving legitimate fields and re-resolution", () => {
  const callers = applicationInsertCallers();
  assert.deepEqual(
    callers.map(({ path }) => path).sort(),
    [
      "app/dashboard/truck/oportunidades/[id]/page.tsx",
      "app/pedidos/[id]/aplicar/page.tsx",
    ],
  );

  for (const { path, source, body } of callers) {
    assert.doesNotMatch(body, /\bstatus\s*:/, `${path} must not control application status`);
    for (const field of ["request_id", "truck_id", "proposed_price", "cover_message"]) {
      assert.match(body, new RegExp(`\\b${field}\\s*:`), `${path} must preserve ${field}`);
    }

    const action = source.slice(source.indexOf('"use server"'));
    const auth = action.indexOf(".auth.getUser()");
    const ownership = action.search(
      path.includes("/pedidos/")
        ? /\.rpc\(\s*"airfnb_own_application_truck"/
        : /\.rpc\(\s*"airfnb_supplier_services"/,
    );
    const eligibility = action.search(/\.rpc\(\s*"airfnb_can_submit_application"/);
    const insert = action.search(/\.from\(\s*"airfnb_applications"\s*\)\.insert/);
    assert.ok(auth >= 0 && auth < ownership, `${path} must authenticate before ownership resolution`);
    assert.ok(ownership < eligibility, `${path} must resolve ownership before eligibility`);
    assert.ok(eligibility < insert, `${path} must recheck eligibility before insert`);
  }

  const dashboardInsert = callers.find(({ path }) => path.includes("/dashboard/truck/"));
  assert.ok(dashboardInsert);
  assert.match(dashboardInsert.body, /\bestimated_servings\s*:/);
});

test("database types expose every exact new RPC", () => {
  for (const { name } of rpcContracts) {
    assert.match(types, new RegExp(`\\b${name}: \\{`));
  }
  assert.match(types, /airfnb_supplier_services: \{\s*Args: \{ p_truck\?: string \| null \}/);
  assert.match(types, /airfnb_public_service_detail: \{\s*Args: \{ p_slug: string \};\s*Returns: Json/);
  assert.match(types, /airfnb_invitation_candidates: \{\s*Args: \{ p_request: string \}/);
  assert.match(types, /airfnb_invite_request_services: \{\s*Args: \{ p_request: string; p_trucks: string\[\] \}/);
  assert.match(types, /airfnb_booking_service_context: \{\s*Args: \{ p_booking\?: string \| null \}/);
  assert.match(types, /airfnb_request_application_service_context: \{\s*Args: \{ p_request: string \}/);
  assert.match(types, /airfnb_supplier_export_data: \{\s*Args: never;\s*Returns: Json/);
});
