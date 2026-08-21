import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

async function source(relativePath) {
  return readFile(path.join(ROOT, relativePath), "utf8");
}

async function sourceFiles(directory) {
  const root = path.join(ROOT, directory);
  const files = [];

  async function visit(current) {
    for (const entry of await readdir(current, { withFileTypes: true })) {
      if (entry.name === "node_modules" || entry.name === ".next" || entry.name === ".git") continue;
      const absolute = path.join(current, entry.name);
      if (entry.isDirectory()) {
        await visit(absolute);
      } else if (/\.(?:js|mjs|cjs|ts|tsx)$/.test(entry.name)) {
        files.push(absolute);
      }
    }
  }

  await visit(root);
  return files.sort();
}

test("application sources contain no stale production origin or embedded JWT-shaped key", async () => {
  const files = (
    await Promise.all(["app", "components", "lib", "scripts", "supabase/functions"].map(sourceFiles))
  ).flat();
  const staleOrigin = ["airfnb", "vercel", "app"].join(".");
  const jwtPattern = /\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\b/;
  const violations = [];

  for (const absolute of files) {
    const contents = await readFile(absolute, "utf8");
    const relative = path.relative(ROOT, absolute);
    if (contents.toLowerCase().includes(staleOrigin)) violations.push(`${relative}: stale origin`);
    if (jwtPattern.test(contents)) violations.push(`${relative}: embedded JWT-shaped key`);
  }

  assert.deepEqual(violations, []);
});

test("manifest does not advertise a wide wordmark as a square PWA icon", async () => {
  const manifest = await source("app/manifest.ts");

  assert.doesNotMatch(manifest, /^\s*icons\s*:/m);
  assert.doesNotMatch(manifest, /logo-fb-tailor-(?:white|black)\.png/);
  assert.match(manifest, /name:\s*["']F&B Tailor["']/);
  assert.match(manifest, /description:\s*["']Food Trucks, Catering e Bares para Eventos["']/);
});

test("public supplier avatars use the constrained Next image proxy", async () => {
  const catalogue = await source("app/catalogo/[slug]/page.tsx");
  const config = await source("next.config.mjs");

  assert.match(catalogue, /import Image from ["']next\/image["']/);
  assert.match(catalogue, /publicAvatarUrl\([\s\S]*truck\.owner\?\.avatar_url[\s\S]*NEXT_PUBLIC_SUPABASE_URL/);
  assert.match(catalogue, /<Image[\s\S]*src=\{ownerAvatarUrl\}[\s\S]*referrerPolicy=["']no-referrer["']/);
  assert.doesNotMatch(catalogue, /<img[^>]+src=\{truck\.owner\.avatar_url\}/);
  assert.match(config, /pathname:\s*["']\/storage\/v1\/object\/public\/\*\*["']/);
  assert.match(config, /if \(supabasePattern\) imageRemotePatterns\.push\(supabasePattern\)/);
});

test("global response headers enforce the production security baseline", async () => {
  const configUrl = `${pathToFileURL(path.join(ROOT, "next.config.mjs")).href}?quality-test`;
  const { default: config } = await import(configUrl);
  const previousNodeEnv = process.env.NODE_ENV;

  try {
    process.env.NODE_ENV = "production";
    const rules = await config.headers();
    assert.equal(config.poweredByHeader, false);
    assert.equal(rules.length, 1);
    assert.equal(rules[0].source, "/:path*");

    const headers = Object.fromEntries(rules[0].headers.map(({ key, value }) => [key, value]));
    assert.deepEqual(headers, {
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
      "Referrer-Policy": "strict-origin-when-cross-origin",
      "Permissions-Policy": "camera=(), microphone=(), geolocation=(), browsing-topics=()",
      "X-DNS-Prefetch-Control": "off",
      "Strict-Transport-Security": "max-age=31536000",
    });
  } finally {
    if (previousNodeEnv === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = previousNodeEnv;
  }
});

test("public contacts fail closed to an internal help route", async () => {
  const contacts = await source("lib/public-contact.ts");
  const publicMailboxLiterals = contacts.match(/[A-Z0-9.!%&'*+/=_~-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi) ?? [];

  assert.deepEqual(publicMailboxLiterals, []);
  assert.match(contacts, /PUBLIC_CONTACT_FALLBACK_PATH\s*=\s*["']\/ajuda["']/);
  assert.match(contacts, /const support\s*=\s*validatePublicEmail\(process\.env\.SUPPORT_EMAIL\)/);
  assert.match(contacts, /email\s*\?\s*`mailto:\$\{email\}`\s*:\s*PUBLIC_CONTACT_FALLBACK_PATH/);
  assert.match(contacts, /domain\.endsWith\(["']\.invalid["']\)/);
});

test("email delivery has no fallback sender and rejects incomplete configuration", async () => {
  const emailFunction = await source("supabase/functions/send-email/index.ts");
  const configurationGuard = emailFunction.indexOf("!isValidSender(FROM_EMAIL)");
  const providerCall = emailFunction.indexOf('fetch("https://api.resend.com/emails"');

  assert.ok(configurationGuard >= 0, "sender validation must be part of the configuration guard");
  assert.ok(providerCall > configurationGuard, "configuration must be rejected before provider delivery");
  assert.match(emailFunction, /const FROM_EMAIL\s*=\s*Deno\.env\.get\(["']FROM_EMAIL["']\)\?\.trim\(\)/);
  assert.match(emailFunction, /!RESEND_API_KEY[\s\S]*!isValidSender\(FROM_EMAIL\)[\s\S]*!ALLOWED\.length[\s\S]*!SUPABASE_URL[\s\S]*!SUPABASE_SERVICE_ROLE_KEY/);
  assert.doesNotMatch(emailFunction, /const FROM_EMAIL\s*=.*(?:\?\?|\|\|)\s*["'`]/);
  assert.match(emailFunction, /domain\.endsWith\(["']\.invalid["']\)/);
});

test("health response is dynamic, private and excluded from indexing", async () => {
  const health = await source("app/api/health/route.ts");

  assert.match(health, /export const dynamic\s*=\s*["']force-dynamic["']/);
  assert.match(health, /["']Cache-Control["']\s*:\s*["']no-store, max-age=0["']/);
  assert.match(health, /["']X-Robots-Tag["']\s*:\s*["']noindex, nofollow["']/);
  assert.doesNotMatch(health, /process\.env\.(?:SUPABASE|STRIPE|RESEND|VERCEL_TOKEN)/);
});
