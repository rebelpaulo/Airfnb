// OAuth + magic-link callback. Exchanges the code in the URL for a session
// cookie, then routes the user based on their profile state.
import { NextResponse, type NextRequest } from "next/server";
import { supabaseServer, supabaseAdmin } from "@/lib/supabase/server";

export const runtime = "nodejs";

function safeNext(raw: string | null): string {
  if (!raw) return "/";
  // same-origin relative path only — prevents open-redirect
  if (raw === "/" || /^\/[^/\\]/.test(raw)) return raw;
  return "/";
}

export async function GET(req: NextRequest) {
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  const next = safeNext(url.searchParams.get("next"));
  const asRole = url.searchParams.get("as");

  if (!code) {
    return NextResponse.redirect(new URL("/login?err=missing_code", req.url));
  }

  const supa = await supabaseServer();
  const { error } = await supa.auth.exchangeCodeForSession(code);
  if (error) {
    return NextResponse.redirect(new URL(`/login?err=${encodeURIComponent(error.message)}`, req.url));
  }

  const { data: { user } } = await supa.auth.getUser();
  if (!user) {
    return NextResponse.redirect(new URL("/login?err=no_user_after_exchange", req.url));
  }

  // upgrade role if the caller requested it (e.g. signup ?as=truck)
  if (asRole === "owner" || asRole === "organizer") {
    await (supa as any).from("airfnb_profiles").update({ role: asRole }).eq("id", user.id);
  }

  // Route based on onboarding state
  const { data: profile } = await (supa as any)
    .from("airfnb_profiles")
    .select("role, onboarding_completed, full_name")
    .eq("id", user.id)
    .maybeSingle();

  // First-time user → route to the matching onboarding wizard
  if (profile && !profile.onboarding_completed) {
    const target = profile.role === "owner" ? "/onboarding/truck" : "/onboarding/organizer";
    return NextResponse.redirect(new URL(target, req.url));
  }

  return NextResponse.redirect(new URL(next, req.url));
}
