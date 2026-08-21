import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const paths = {
  helper: "lib/auth/fb-membership.ts",
  signup: "app/(auth)/signup/page.tsx",
  login: "app/(auth)/login/page.tsx",
  callback: "app/(auth)/auth/callback/route.ts",
  publish: "app/publicar/OrganizerWizard.tsx",
  truck: "app/onboarding/truck/page.tsx",
  organizer: "app/onboarding/organizer/page.tsx",
  truckWizard: "app/dashboard/truck/novo/TruckWizard.tsx",
  account: "app/dashboard/conta/page.tsx",
  deleteAccount: "app/dashboard/conta/DeleteAccountButton.tsx",
  i18n: "lib/i18n.ts",
};

const sources = Object.fromEntries(
  await Promise.all(
    Object.entries(paths).map(async ([name, path]) => [name, await readFile(path, "utf8")]),
  ),
);

test("shared helper bootstraps before a narrowly typed self-service claim", () => {
  const source = sources.helper;
  assert.match(source, /export type FbSelfServiceRole = "owner" \| "organizer";/u);
  assert.match(source, /client\.rpc\("airfnb_ensure_profile"/u);
  assert.match(source, /await ensureFbProfile\(client, options\);[\s\S]*client\.rpc\("airfnb_claim_role"/u);
  assert.match(source, /if \(error\) throw rpcError/u);
  assert.doesNotMatch(source, /service_role|supabaseAdmin|user_id|userId/u);
});

test("immediate signup explicitly bootstraps and claims before navigation", () => {
  const source = sources.signup;
  assert.match(source, /if \(!data\.session\)[\s\S]*await ensureFbMembership\(supa, \{ role, fullName: name, locale: "pt-PT" \}\)[\s\S]*router\.push\(next\)/u);
  assert.doesNotMatch(source, /\.update\(\{[^}]*role/u);
});

test("password login bootstraps without claiming and preserves role-null routing", () => {
  const source = sources.login;
  assert.match(source, /signInWithPassword[\s\S]*await ensureFbProfile\(supa\)/u);
  assert.match(source, /profile\.role === null[\s\S]*router\.push\("\/registar"\)/u);
  assert.doesNotMatch(source, /ensureFbMembership|airfnb_claim_role/u);
});

test("callback validates the query role and never derives authorization from metadata", () => {
  const source = sources.callback;
  assert.match(source, /parseFbSelfServiceRole\(url\.searchParams\.get\("as"\)\)/u);
  assert.match(source, /if \(asRole\) \{[\s\S]*ensureFbMembership\(supa, \{ role: asRole \}\)[\s\S]*else \{[\s\S]*ensureFbProfile\(supa\)/u);
  assert.match(source, /profile\.role === null[\s\S]*"\/registar"/u);
  assert.doesNotMatch(source, /user_metadata|app_metadata|supabaseAdmin|service_role/u);
  assert.doesNotMatch(source, /\.update\(\{[^}]*role/u);
});

test("publisher and both onboarding flows use the ordered membership helper", () => {
  assert.match(sources.publish, /await ensureFbMembership\(supa, \{[\s\S]*role: "organizer"[\s\S]*\.from\("airfnb_event_requests"\)\.insert/u);
  assert.match(sources.truck, /await ensureFbMembership\(supa, \{ role: "owner", fullName: full_name, locale: "pt-PT" \}\)[\s\S]*\.from\("airfnb_profiles"\)[\s\S]*\.update/u);
  assert.match(sources.organizer, /await ensureFbMembership\(supa, \{ role: "organizer", fullName: full_name, locale: "pt-PT" \}\)[\s\S]*\.from\("airfnb_profiles"\)[\s\S]*\.update/u);
});

test("truck wizard claims owner through the guarded role RPC", () => {
  assert.match(
    sources.truckWizard,
    /\.rpc\("airfnb_claim_role",\s*\{\s*p_role:\s*"owner",?\s*\}\)/u,
  );
  assert.doesNotMatch(
    sources.truckWizard,
    /from\(["']airfnb_profiles["']\)[\s\S]{0,220}\.update\(\{[\s\S]{0,180}?\brole\s*:/u,
  );
});

test("self-delete removes only F&B membership and signs out locally", () => {
  assert.match(sources.deleteAccount, /fetch\("\/api\/me\/fb-membership"[\s\S]*method: "POST"/u);
  assert.doesNotMatch(sources.deleteAccount, /\.rpc\("airfnb_self_delete"\)/u);
  assert.match(sources.deleteAccount, /auth\.signOut\(\{ scope: "local" \}\)/u);
  assert.doesNotMatch(sources.deleteAccount, /deleteUser|auth\.admin|scope:\s*"global"/u);
  assert.match(
    sources.account,
    /\{t\.delete_body\}[\s\S]*\{t\.delete_auth_body\}[\s\S]*\{t\.delete_tombstone_body\}/u,
  );
  assert.match(sources.i18n, /delete_body:\s+"Os teus dados F&B serão apagados ou anonimizados[^"]*ficheiros carregados/u);
  assert.match(sources.i18n, /delete_auth_body:\s+"A tua conta Auth Tailor partilhada mantém-se ativa e não é apagada/u);
  assert.match(sources.i18n, /delete_tombstone_body:\s+"Para prevenir abuso[^"]*UUID[^"]*impede uma nova adesão F&B/u);
  assert.match(sources.i18n, /delete_auth_body:\s+"Your shared Tailor Auth account remains active and is not deleted/u);
  assert.match(sources.i18n, /delete_tombstone_body:\s+"To prevent abuse[^"]*UUID[^"]*blocks a new F&B membership/u);
});

test("F&B auth callers do not insert profiles or write role directly", () => {
  const callerNames = ["signup", "login", "callback", "publish", "truck", "organizer", "truckWizard"];
  for (const name of callerNames) {
    const source = sources[name];
    assert.doesNotMatch(
      source,
      /from\(["']airfnb_profiles["']\)[\s\S]{0,160}\.insert\(/u,
      `${name} must not insert airfnb_profiles directly`,
    );
    assert.doesNotMatch(
      source,
      /from\(["']airfnb_profiles["']\)[\s\S]{0,220}\.update\(\{[\s\S]{0,180}?\brole\s*:/u,
      `${name} must not write airfnb_profiles.role directly`,
    );
    assert.doesNotMatch(source, /supabaseAdmin|SUPABASE_SERVICE_ROLE_KEY|service_role/u);
  }
});
