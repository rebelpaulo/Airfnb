import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const read = (path) =>
  readFileSync(new URL(`../${path}`, import.meta.url), "utf8");

const normalLogoutSources = [
  ["route logout", read("app/logout/route.ts")],
  ["account menu logout", read("components/AccountMenu.tsx")],
  ["mobile drawer logout", read("components/Header.tsx")],
];

test("every normal logout is scoped to the current session", () => {
  for (const [label, source] of normalLogoutSources) {
    assert.match(
      source,
      /\.auth\.signOut\(\{\s*scope:\s*["']local["']\s*\}\)/,
      label,
    );
    assert.doesNotMatch(source, /\.auth\.signOut\(\s*\)/, label);
    assert.doesNotMatch(
      source,
      /\.auth\.signOut\(\{\s*scope:\s*["']global["']\s*\}\)/,
      label,
    );
  }
});

test("route logout still forwards cookie removals and protects redirects", () => {
  const route = normalLogoutSources[0][1];

  assert.match(route, /export async function POST\(request: NextRequest\)/);
  assert.doesNotMatch(route, /export async function GET\(/);
  assert.match(route, /requestOrigin !== request\.nextUrl\.origin/);
  assert.match(route, /fetchSite !== ["']same-origin["']/);
  assert.match(route, /NextResponse\.redirect\(redirectUrl, 303\)/);
  assert.match(route, /const \{ error \} = await supabase\.auth\.signOut/);
  assert.match(route, /if \(error\) \{[\s\S]*status: 502/);
  assert.match(route, /pendingCookies\.push\(\.\.\.cookies\)/);
  assert.match(route, /response\.cookies\.set\(name, value, options\)/);
  assert.match(route, /let redirectUrl = safeRedirectUrl\(/);
  assert.match(route, /redirectUrl\.origin !== request\.nextUrl\.origin/);
  assert.match(route, /NextResponse\.redirect\(redirectUrl, 303\)/);

  const originGuard = route.indexOf("requestOrigin !== request.nextUrl.origin");
  const signOut = route.indexOf("await supabase.auth.signOut");
  assert.ok(originGuard >= 0 && originGuard < signOut, "origin guard must run before signOut");
  const errorGuard = route.indexOf("if (error)", signOut);
  const successResponse = route.indexOf("const response = NextResponse.redirect");
  assert.ok(signOut < errorGuard && errorGuard < successResponse, "failed signOut must not redirect");
});

test("client logout failures remain fail-closed", () => {
  for (const [label, source] of normalLogoutSources.slice(1)) {
    assert.match(source, /if \(error\) \{/m, label);
    assert.match(source, /alert\(`\$\{t\.logout_error_prefix\} \$\{error\.message\}`\)/, label);
    assert.match(source, /return;/, label);
    assert.match(source, /window\.location\.href = "\/";/, label);
  }
});
