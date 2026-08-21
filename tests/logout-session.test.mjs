import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { safeRedirectUrl } from "../app/logout/safe-redirect.ts";

const read = (path) =>
  readFileSync(new URL(`../${path}`, import.meta.url), "utf8");

const route = read("app/logout/route.ts");

test("logout runs in a mutation-capable Route Handler and forwards Supabase cookie removals", () => {
  assert.match(route, /export async function POST\(request: NextRequest\)/);
  assert.doesNotMatch(route, /export async function GET\(/);
  assert.match(route, /request\.headers\.get\(["']origin["']\)/);
  assert.match(route, /requestOrigin !== request\.nextUrl\.origin/);
  assert.match(route, /fetchSite !== ["']same-origin["']/);
  assert.match(route, /status: 403/);
  assert.match(route, /NextResponse\.redirect\(redirectUrl, 303\)/);
  assert.match(route, /createServerClient<AirfnbDatabase>/);
  assert.match(route, /getAll:\s*\(\)\s*=>\s*request\.cookies\.getAll\(\)/);
  assert.match(route, /pendingCookies\.push\(\.\.\.cookies\)/);
  assert.match(route, /response\.cookies\.set\(name, value, options\)/);
  assert.match(
    route,
    /const \{ error \} = await supabase\.auth\.signOut\(\{\s*scope:\s*["']local["']\s*\}\)/,
  );
  assert.match(route, /if \(error\) \{[\s\S]*status: 502[\s\S]*["']Cache-Control["']:\s*["']no-store["']/);
  assert.match(route, /return response/);
  assert.doesNotMatch(route, /from ["']@\/lib\/supabase\/server["']/);

  const originGuard = route.indexOf("requestOrigin !== request.nextUrl.origin");
  const signOut = route.indexOf("await supabase.auth.signOut");
  assert.ok(originGuard >= 0 && originGuard < signOut, "origin guard must run before signOut");

  const errorGuard = route.indexOf("if (error)", signOut);
  const successResponse = route.indexOf("const response = NextResponse.redirect");
  const cookieCommit = route.indexOf("response.cookies.set");
  assert.ok(
    signOut < errorGuard && errorGuard < successResponse && successResponse < cookieCommit,
    "redirect and cookie removals must only be committed after signOut succeeds",
  );
});

test("the wrong-account CTA submits a same-origin logout POST", () => {
  const source = read("components/WrongAccountType.tsx");
  assert.match(source, /<form action=\{`\/logout\?next=\$\{encodeURIComponent\(cta\.next\)\}`\} method=["']post["']>/);
  assert.match(source, /<button type=["']submit["'] className=["']btn-pill["']>/);
  assert.doesNotMatch(source, /href=\{cta\.href/);
});

test("logout only redirects to same-origin relative paths", () => {
  assert.match(route, /let redirectUrl = safeRedirectUrl\(/);
  assert.match(route, /redirectUrl\.origin !== request\.nextUrl\.origin/);
  assert.match(route, /NextResponse\.redirect\(redirectUrl, 303\)/);
  assert.doesNotMatch(route, /new URL\(redirectUrl\.pathname/);
});

test("redirect validation rejects normalized authority and separator attacks", () => {
  const origin = "https://fb-tailor.example";
  const attacks = [
    "/%2e%2e//evil.example",
    "/foo/%2e%2e//evil.example",
    "/.//evil.example",
    "/foo/%5cevil.example",
    "/foo/%5C%5Cevil.example",
    "/foo\\evil.example",
    "//evil.example/path",
    "https://evil.example/path",
    "https://user@evil.example/path",
    "javascript:alert(1)",
  ];

  for (const attack of attacks) {
    assert.equal(safeRedirectUrl(attack, origin).href, `${origin}/`, attack);
  }
});

test("redirect validation preserves legitimate same-origin path, query and hash", () => {
  const origin = "https://fb-tailor.example";
  assert.equal(
    safeRedirectUrl("/signup?as=truck&next=%2Fcatalogo#conta", origin).href,
    `${origin}/signup?as=truck&next=%2Fcatalogo#conta`,
  );
  assert.equal(safeRedirectUrl("/", origin).href, `${origin}/`);
  assert.equal(safeRedirectUrl(null, origin).href, `${origin}/`);
});
