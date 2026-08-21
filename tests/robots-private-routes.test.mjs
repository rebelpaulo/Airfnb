import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const PRIVATE_ROUTES = [
  "/admin",
  "/api/",
  "/auth/",
  "/dashboard/",
  "/login",
  "/signup",
  "/forgot-password",
  "/reset-password",
  "/onboarding/",
  "/logout",
];

test("robots metadata keeps public crawling and excludes the exact private route set", async () => {
  const source = await readFile(path.join(ROOT, "app/robots.ts"), "utf8");
  const routeList = source.match(/const PRIVATE_ROUTES\s*=\s*(\[[\s\S]*?\])\s*as const;/);

  assert.ok(routeList, "robots.ts must declare the private route set as a constant");
  const routes = [...routeList[1].matchAll(/["']([^"']+)["']/g)].map((match) => match[1]);
  assert.deepEqual(routes, PRIVATE_ROUTES);
  assert.match(source, /export default function robots\(\): MetadataRoute\.Robots/);
  assert.match(source, /userAgent:\s*["']\*["']/);
  assert.match(source, /allow:\s*["']\/["']/);
  assert.match(source, /disallow:\s*\[\.\.\.PRIVATE_ROUTES\]/);
});

test("robots metadata preserves canonical host and sitemap resolution", async () => {
  const source = await readFile(path.join(ROOT, "app/robots.ts"), "utf8");

  assert.match(source, /import \{ resolveAppOrigin \} from ["']@\/lib\/app-url\.mjs["']/);
  assert.match(source, /const APP_URL\s*=\s*resolveAppOrigin\(\)/);
  assert.match(source, /sitemap:\s*`\$\{APP_URL\}\/sitemap\.xml`/);
  assert.match(source, /host:\s*APP_URL/);
});

test("robots metadata documents that crawler directives are not authorization", async () => {
  const source = await readFile(path.join(ROOT, "app/robots.ts"), "utf8");

  assert.match(
    source,
    /robots\.txt is advisory crawl guidance only; authorization is enforced by the application\./,
  );
});
