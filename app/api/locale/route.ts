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

  // Redirect back to the page the user came from, falling back to /
  const back = req.headers.get("referer") ?? "/";
  const res = NextResponse.redirect(back, 303);
  res.cookies.set("airfnb_locale", lang, {
    path: "/",
    maxAge: 60 * 60 * 24 * 365,   // 1 year
    sameSite: "lax",
    httpOnly: false,              // safe to read client-side; no security data
  });
  return res;
}
