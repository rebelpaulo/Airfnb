// OAuth + magic-link callback. Exchanges the code in the URL for a session
// cookie, then routes the user based on their profile state.
import { NextResponse, type NextRequest } from "next/server";
import { supabaseServer } from "@/lib/supabase/server";
import {
  ensureFbMembership,
  ensureFbProfile,
  parseFbSelfServiceRole,
} from "@/lib/auth/fb-membership";

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
  const asRole = parseFbSelfServiceRole(url.searchParams.get("as"));

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

  // Enter the F&B application explicitly. Only the two self-service roles
  // accepted by parseFbSelfServiceRole can reach the one-time claim RPC;
  // arbitrary query values and auth metadata never authorize a role.
  try {
    if (asRole) {
      await ensureFbMembership(supa, { role: asRole });
    } else {
      await ensureFbProfile(supa);
    }
  } catch (membershipError) {
    const reason = membershipError instanceof Error
      ? membershipError.message
      : String(membershipError);
    const params = new URLSearchParams({ err: "membership_bootstrap_failed", reason });
    return NextResponse.redirect(new URL(`/login?${params.toString()}`, req.url));
  }

  // Capture ?ref=CODE referral attribution. The RPC ignores self-referrals,
  // unknown codes, and re-attribution attempts (the user already has a
  // referred_by). Failure is silent — we don't want to block the signup
  // round-trip over a marketing nice-to-have.
  const refCode = url.searchParams.get("ref");
  if (refCode) {
    await (supa as any).rpc("airfnb_apply_referral", { p_code: refCode });
  }

  // Route based on onboarding state
  const { data: profile, error: profileError } = await (supa as any)
    .from("airfnb_profiles")
    .select("role, onboarding_completed, full_name")
    .eq("id", user.id)
    .maybeSingle();
  if (profileError || !profile) {
    const params = new URLSearchParams({ err: "profile_read_failed" });
    return NextResponse.redirect(new URL(`/login?${params.toString()}`, req.url));
  }

  // First-time user → route to the matching onboarding wizard
  if (!profile.onboarding_completed) {
    if (profile.role === null) {
      return NextResponse.redirect(new URL("/registar", req.url));
    }
    const target = profile.role === "owner" ? "/onboarding/truck" : "/onboarding/organizer";
    return NextResponse.redirect(new URL(target, req.url));
  }

  return NextResponse.redirect(new URL(next, req.url));
}
