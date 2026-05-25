// Public newsletter signup endpoint. RLS already allows anonymous INSERT
// on airfnb_newsletter_subs; this route adds basic validation + a redirect
// so the Footer can keep using a plain <form action="/api/newsletter">
// without client-side JS.
import { NextResponse, type NextRequest } from "next/server";
import { supabaseAdmin } from "@/lib/supabase/server";

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

  if (ct.includes("application/x-www-form-urlencoded") || ct.includes("multipart/form-data")) {
    const fd = await req.formData();
    email  = String(fd.get("email") ?? "").trim().toLowerCase();
    source = String(fd.get("source") ?? "footer").slice(0, 32);
  } else {
    const body = await req.json().catch(() => null) as { email?: string; source?: string } | null;
    email  = (body?.email ?? "").trim().toLowerCase();
    source = (body?.source ?? "footer").slice(0, 32);
  }

  // Cheap RFC-5322-ish email check — server-side, not relying on the input type
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) {
    return done(req, "err", "email_invalid");
  }

  // service_role bypasses RLS — needed for the upsert path because the
  // anonymous insert policy doesn't permit a returning-select+update flow.
  // We're not leaking auth here; the only write is the user-supplied email.
  const supa = supabaseAdmin();
  const { error } = await (supa as any).from("airfnb_newsletter_subs")
    .upsert({ email, source }, { onConflict: "email" });
  if (error) {
    // Don't log the raw email — anonymise to local-part length + domain so
    // operators can still spot patterns (e.g. one big provider hitting the
    // form) without leaking subscriber PII into log aggregators.
    const at = email.indexOf("@");
    const safeEmail = at > 0 ? `(${at} chars)@${email.slice(at + 1)}` : "(invalid)";
    console.error("newsletter upsert failed", { email: safeEmail, error: error.message });
    return done(req, "err", "upsert_failed");
  }

  return done(req, "ok");
}
