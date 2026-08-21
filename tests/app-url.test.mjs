import assert from "node:assert/strict";
import test from "node:test";

import { normalizeAppOrigin, resolveAppOrigin } from "../lib/app-url.mjs";

test("normalizeAppOrigin accepts only credential-free HTTP(S) origins", () => {
  assert.equal(normalizeAppOrigin(" https://events.example/path?q=1 "), "https://events.example");
  assert.equal(normalizeAppOrigin("http://localhost:3001/catalogo"), "http://localhost:3001");
  assert.equal(normalizeAppOrigin("javascript:alert(1)"), null);
  assert.equal(normalizeAppOrigin("https://user:password@events.example"), null);
  assert.equal(normalizeAppOrigin("events.example"), null);
  assert.equal(normalizeAppOrigin(""), null);
  assert.equal(normalizeAppOrigin(undefined), null);
});

test("normalizeAppOrigin promotes only Vercel hostname candidates to HTTPS", () => {
  assert.equal(
    normalizeAppOrigin("preview-123.vercel.app", { vercelHostname: true }),
    "https://preview-123.vercel.app",
  );
  assert.equal(normalizeAppOrigin("preview-123.vercel.app"), null);
});

test("resolveAppOrigin follows the documented precedence", () => {
  assert.equal(
    resolveAppOrigin({
      APP_URL: "https://app.example/path",
      NEXT_PUBLIC_APP_URL: "https://public.example",
      VERCEL_PROJECT_PRODUCTION_URL: "production.vercel.app",
      VERCEL_URL: "preview.vercel.app",
    }),
    "https://app.example",
  );

  assert.equal(
    resolveAppOrigin({
      APP_URL: "not-a-url",
      NEXT_PUBLIC_APP_URL: "https://public.example/path",
      VERCEL_PROJECT_PRODUCTION_URL: "production.vercel.app",
      VERCEL_URL: "preview.vercel.app",
    }),
    "https://public.example",
  );

  assert.equal(
    resolveAppOrigin({
      APP_URL: "ftp://invalid.example",
      NEXT_PUBLIC_APP_URL: "invalid.example",
      VERCEL_PROJECT_PRODUCTION_URL: "production.vercel.app",
      VERCEL_URL: "preview.vercel.app",
    }),
    "https://production.vercel.app",
  );

  assert.equal(
    resolveAppOrigin({ VERCEL_URL: "preview.vercel.app" }),
    "https://preview.vercel.app",
  );
});

test("resolveAppOrigin has a deterministic local fallback", () => {
  assert.equal(resolveAppOrigin({}), "http://localhost:3001");
  assert.equal(
    resolveAppOrigin({
      APP_URL: "mailto:hello@example.com",
      NEXT_PUBLIC_APP_URL: "//invalid.example",
      VERCEL_PROJECT_PRODUCTION_URL: "https://user:password@example.com",
      VERCEL_URL: " ",
    }),
    "http://localhost:3001",
  );
});
