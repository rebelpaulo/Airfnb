// Public newsletter signup endpoint. Writes are service-role only; this route
// validates and rate-limits before preserving the existing redirect flow
// so the Footer can keep using a plain <form action="/api/newsletter">
// without client-side JS.
import { NextResponse, type NextRequest } from "next/server";
import { supabaseAdmin } from "@/lib/supabase/server";
import {
  assertPublicRateLimit,
  PublicRateLimitError,
  publicClientIp,
} from "@/lib/public-rate-limit";

export const runtime = "nodejs";

function done(req: NextRequest, status: "ok" | "err", msg?: string) {
  const url = new URL("/", req.url);
  url.searchParams.set("newsletter", status);
  if (msg) url.searchParams.set("nlmsg", msg);
  return NextResponse.redirect(url, 303); // 303 → GET after POST
}

export async function POST(req: NextRequest) {
  let email = "";
  let source = "footer";
  const ct = req.headers.get("content-type") ?? "";
  const contentLength = Number(req.headers.get("content-length") ?? "0");

  if (!Number.isFinite(contentLength) || contentLength < 0 || contentLength > 4_096) {
    return done(req, "err", "payload_too_large");
  }

  const rawBody = await req.text().catch(() => "");
  if (!rawBody || rawBody.length > 4_096) {
    return done(req, "err", "payload_invalid");
  }

  if (ct.includes("application/x-www-form-urlencoded")) {
    const body = new URLSearchParams(rawBody);
    email = (body.get("email") ?? "").trim().toLowerCase();
    source = (body.get("source") ?? "footer").trim();
  } else if (ct.includes("application/json")) {
    const body = (() => {
      try {
        return JSON.parse(rawBody) as { email?: unknown; source?: unknown };
      } catch {
        return null;
      }
    })();
    if (!body || typeof body.email !== "string" || (body.source !== undefined && typeof body.source !== "string")) {
      return done(req, "err", "payload_invalid");
    }
    email = body.email.trim().toLowerCase();
    source = (body.source ?? "footer").trim();
  } else {
    return done(req, "err", "content_type_unsupported");
  }

  // Cheap RFC-5322-ish email check — server-side, not relying on the input type
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) {
    return done(req, "err", "email_invalid");
  }
  if (!/^[a-z0-9_-]{1,32}$/i.test(source)) {
    return done(req, "err", "source_invalid");
  }

  try {
    await assertPublicRateLimit({
      action: "newsletter_signup_email",
      identifierKind: "email",
      identifier: email,
      limit: 5,
      windowSeconds: 3_600,
    });

    const ip = publicClientIp(req.headers);
    if (ip) {
      await assertPublicRateLimit({
        action: "newsletter_signup_ip",
        identifierKind: "ip",
        identifier: ip,
        limit: 30,
        windowSeconds: 3_600,
      });
    }
  } catch (error) {
    if (error instanceof PublicRateLimitError && error.code === "rate_limited") {
      return done(req, "err", "rate_limited");
    }
    return done(req, "err", "rate_limit_unavailable");
  }

  // Direct client INSERT is revoked. This trusted route owns the bounded
  // upsert and never exposes its service-role credential to the browser.
  const supa = supabaseAdmin();
  const { error } = await supa.from("airfnb_newsletter_subs")
    .upsert({ email, source }, { onConflict: "email" });
  if (error) {
    // Error details may echo a constrained value, so only the code is logged.
    console.error("newsletter upsert failed", { code: error.code ?? "unknown" });
    return done(req, "err", "upsert_failed");
  }

  return done(req, "ok");
}
