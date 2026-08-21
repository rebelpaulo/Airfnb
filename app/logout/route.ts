import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import type { AirfnbDatabase } from "@/types/database";
import { safeRedirectUrl } from "./safe-redirect";

type SupaCookie = { name: string; value: string; options?: CookieOptions };

export async function POST(request: NextRequest) {
  const requestOrigin = request.headers.get("origin");
  const fetchSite = request.headers.get("sec-fetch-site");
  if (
    requestOrigin !== request.nextUrl.origin
    || (fetchSite !== null && fetchSite !== "same-origin")
  ) {
    return NextResponse.json({ error: "cross-origin logout refused" }, { status: 403 });
  }

  let redirectUrl = safeRedirectUrl(
    request.nextUrl.searchParams.get("next"),
    request.nextUrl.origin,
  );
  // Validate the final, already-normalized URL immediately before emitting the
  // Location header. Never parse a normalized pathname a second time.
  if (redirectUrl.origin !== request.nextUrl.origin) {
    redirectUrl = new URL("/", request.nextUrl.origin);
  }
  // Hold cookie mutations until signOut succeeds. Returning a redirect with
  // partial cookie changes after an Auth failure would report a logout that did
  // not actually complete.
  const pendingCookies: SupaCookie[] = [];
  const supabase = createServerClient<AirfnbDatabase>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll: (cookies: SupaCookie[]) => {
          pendingCookies.push(...cookies);
        },
      },
    },
  );

  // End only this browser session. The underlying Auth user is shared with
  // other Tailor products, so a global sign-out would revoke their sessions.
  // Supabase emits this session's cookie removals through setAll(). They are
  // committed to the outgoing redirect only after Auth confirms success.
  const { error } = await supabase.auth.signOut({ scope: "local" });
  if (error) {
    return NextResponse.json(
      { error: "logout failed" },
      { status: 502, headers: { "Cache-Control": "no-store" } },
    );
  }

  // 303 converts this mutation POST into a safe follow-up GET. A 307 would
  // replay the POST against the destination route.
  const response = NextResponse.redirect(redirectUrl, 303);
  pendingCookies.forEach(({ name, value, options }) => {
    response.cookies.set(name, value, options);
  });

  return response;
}
