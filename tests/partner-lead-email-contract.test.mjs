import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { registerHooks } from "node:module";
import path from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

const TEST_FILE = fileURLToPath(import.meta.url);
const ROOT = path.resolve(path.dirname(TEST_FILE), "..");

const calls = [];
let insertError = null;
let settingError = null;

function dataModule(source) {
  return `data:text/javascript,${encodeURIComponent(source)}`;
}

const stubs = new Map([
  ["next/headers", dataModule(`
    export async function headers() {
      return { get: (name) => name === "x-forwarded-for" ? "203.0.113.9" : null };
    }
  `)],
  ["@/lib/supabase/server", dataModule(`
    export function supabaseAdmin() {
      return {
        from(table) {
          return {
            async insert(row) {
              globalThis.__partnerLeadTestCalls.push({ type: "insert", table, row });
              return { error: globalThis.__partnerLeadInsertError };
            },
          };
        },
      };
    }
  `)],
  ["@/lib/settings", dataModule(`
    export async function getSetting() {
      globalThis.__partnerLeadTestCalls.push({ type: "setting" });
      if (globalThis.__partnerLeadSettingError) throw globalThis.__partnerLeadSettingError;
      return "ops@example.invalid";
    }
  `)],
  ["@/lib/public-rate-limit", dataModule(`
    export class PublicRateLimitError extends Error {
      constructor(code) { super(code); this.code = code; }
    }
    export async function assertPublicRateLimit() {
      globalThis.__partnerLeadTestCalls.push({ type: "rate-limit" });
    }
    export function publicClientIp() { return "203.0.113.9"; }
  `)],
]);

registerHooks({
  resolve(specifier, context, nextResolve) {
    const stub = stubs.get(specifier);
    if (stub) return { url: stub, shortCircuit: true };
    return nextResolve(specifier, context);
  },
});

globalThis.__partnerLeadTestCalls = calls;
Object.defineProperty(globalThis, "__partnerLeadInsertError", {
  get: () => insertError,
});
Object.defineProperty(globalThis, "__partnerLeadSettingError", {
  get: () => settingError,
});

const partnerLeadUrl = `${pathToFileURL(path.join(ROOT, "lib/partner-leads.ts")).href}?email-contract-test`;
const { submitPartnerLead } = await import(partnerLeadUrl);

function leadForm() {
  const form = new FormData();
  form.set("website", "");
  form.set("name", "  Maria   <Organizadora>  ");
  form.set("email", "MARIA@EXAMPLE.COM");
  form.set("phone", "+351 912 345 678");
  form.set("event_type", "Casamento <script>alert(1)</script>");
  form.append("services", "DJ");
  form.append("services", "Som e luz");
  form.set("kind", "campo de controlo");
  form.set("subject", "campo de controlo");
  form.set("reply_to", "attacker@example.invalid");
  return form;
}

function reset() {
  calls.length = 0;
  insertError = null;
  settingError = null;
}

test("persists first and sends a bounded plain-text summary with replyTo", async () => {
  reset();
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    calls.push({ type: "fetch", url, init });
    return { ok: true };
  };

  try {
    const result = await submitPartnerLead("music", leadForm());
    assert.deepEqual(result, { ok: true });

    const insertIndex = calls.findIndex((call) => call.type === "insert");
    const fetchIndex = calls.findIndex((call) => call.type === "fetch");
    assert.ok(insertIndex >= 0 && fetchIndex > insertIndex, "insert must precede email dispatch");

    const request = calls[fetchIndex];
    const body = JSON.parse(request.init.body);
    assert.equal(body.template, "contact_reply");
    assert.equal(body.replyTo, "maria@example.com");
    assert.equal(typeof body.data.message, "string");
    assert.ok(body.data.message.length > 0 && body.data.message.length <= 9_000);
    assert.match(body.data.message, /Serviço: Música e animação/);
    assert.match(body.data.message, /Nome: Maria <Organizadora>/);
    assert.match(body.data.message, /event type: Casamento <script>alert\(1\)<\/script>/);
    assert.match(body.data.message, /services: DJ, Som e luz/);
    assert.doesNotMatch(body.data.message, /campo de controlo|attacker@example\.invalid|website/i);
    assert.ok(
      body.data.message.indexOf("event type:") < body.data.message.indexOf("services:"),
      "payload keys must be deterministic and sorted",
    );
    assert.equal(body.data.message.includes("<br"), false, "summary must not inject HTML");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("provider and configuration failures remain generic and non-blocking", async () => {
  reset();
  const originalFetch = globalThis.fetch;
  const originalWarn = console.warn;
  const warnings = [];
  globalThis.fetch = async () => ({ ok: false });
  console.warn = (...args) => warnings.push(args);

  try {
    const providerFailure = await submitPartnerLead("venues", leadForm());
    assert.deepEqual(providerFailure, { ok: true });
    assert.deepEqual(warnings, [["partner-lead email dispatch failed"]]);
    assert.equal(calls.filter((call) => call.type === "insert").length, 1);

    reset();
    warnings.length = 0;
    settingError = new Error("provider details and PII must not escape");
    const configurationFailure = await submitPartnerLead("venues", leadForm());
    assert.deepEqual(configurationFailure, { ok: true });
    assert.deepEqual(warnings, [["partner-lead email dispatch failed"]]);
    assert.equal(calls.filter((call) => call.type === "insert").length, 1);
    assert.equal(calls.some((call) => call.type === "fetch"), false);
  } finally {
    globalThis.fetch = originalFetch;
    console.warn = originalWarn;
  }
});

test("contact_reply template escapes the plain-text message", async () => {
  const source = await readFile(path.join(ROOT, "supabase/functions/send-email/index.ts"), "utf8");
  assert.match(source, /contact_reply:\s*\(d\)[\s\S]*?escape\(d\.message\)/);
});

test("test fixture contains no checkout-specific absolute path", async () => {
  const source = await readFile(TEST_FILE, "utf8");
  assert.doesNotMatch(source, /file:\/{2,3}Users\//);
  assert.doesNotMatch(source, /["']\/Users\//);
});
