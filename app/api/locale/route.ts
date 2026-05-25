// POST /api/locale with form body lang=pt|en sets the airfnb_locale cookie
// and redirects back to the referrer. The header's <LangToggle> uses this.
import { NextResponse, type NextRequest } from "next/server";

export const runtime = "nodejs";
const SUPPORTED = new Set(["pt", "en"]);

export async function POST(req: NextRequest) {
  const ct = req.headers.get("content-type") ?? "";
  let lang = "pt";
  if (ct.includes("application/x-www-form-urlencoded") || ct.includes("multipart/form-data")) {
    const fd = await req.formData();
    lang = String(fd.get("lang") ?? "pt");
  }
  if (!SUPPORTED.has(lang)) lang = "pt";

  // Redirect back to where the user came from, but only when the Referer
  // is same-origin. Otherwise we'd have an open-redirect primitive — an
  // attacker could send a victim a POST with a crafted Referer pointing
  // off-site and we'd happily 303 them away.
  const ref = req.headers.get("referer");
  const here = new URL(req.url);
  let back = "/";
  if (ref) {
    try {
      const u = new URL(ref);
      if (u.origin === here.origin) back = u.pathname + u.search;
    } catch { /* malformed Referer — ignore */ }
  }
  const res = NextResponse.redirect(new URL(back, here.origin), 303);
  res.cookies.set("airfnb_locale", lang, {
    path: "/",
    maxAge: 60 * 60 * 24 * 365,   // 1 year
    sameSite: "lax",
    httpOnly: false,              // safe to read client-side; no security data
  });
  return res;
}
