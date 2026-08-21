/**
 * Build the narrow Next image allowlist entry for public Supabase objects.
 * The configured value must be an origin; malformed, credentialed or
 * non-HTTP(S) values are omitted instead of broadening the allowlist.
 *
 * @param {string | undefined} value
 * @returns {{ protocol: "http" | "https", hostname: string, port: string, pathname: string, search: string } | null}
 */
function supabaseImageRemotePattern(value) {
  if (!value?.trim()) return null;

  try {
    const url = new URL(value.trim());
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    if (url.username || url.password || !url.hostname || url.hostname.includes("*")) return null;
    if (url.pathname !== "/" || url.search || url.hash) return null;

    return {
      protocol: url.protocol === "https:" ? "https" : "http",
      hostname: url.hostname,
      port: url.port,
      pathname: "/storage/v1/object/public/**",
      search: "",
    };
  } catch {
    return null;
  }
}

/** @type {Array<{ protocol: "http" | "https", hostname: string, port: string, pathname: string, search?: string }>} */
const imageRemotePatterns = [
  { protocol: "https", hostname: "images.unsplash.com", port: "", pathname: "/**" },
];

const supabasePattern = supabaseImageRemotePattern(process.env.NEXT_PUBLIC_SUPABASE_URL);
if (supabasePattern) imageRemotePatterns.push(supabasePattern);

/** @type {import('next').NextConfig} */
const config = {
  poweredByHeader: false,
  // Keep Next's server trace scoped to this application even when a separate
  // lockfile exists in a parent workspace on a developer machine.
  outputFileTracingRoot: process.cwd(),
  async headers() {
    const securityHeaders = [
      { key: "X-Content-Type-Options", value: "nosniff" },
      { key: "X-Frame-Options", value: "DENY" },
      { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
      { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=(), browsing-topics=()" },
      { key: "X-DNS-Prefetch-Control", value: "off" },
    ];

    if (process.env.NODE_ENV === "production") {
      securityHeaders.push({
        key: "Strict-Transport-Security",
        value: "max-age=31536000",
      });
    }

    return [{ source: "/:path*", headers: securityHeaders }];
  },
  images: {
    remotePatterns: imageRemotePatterns,
    // Allow the bundled /truck-placeholder.svg through next/image. The
    // sandboxed CSP keeps SVGs script-free so even if an attacker
    // swaps the file they can't run JS in the user's session.
    dangerouslyAllowSVG: true,
    contentSecurityPolicy: "default-src 'self'; script-src 'none'; sandbox;",
  },
  // typedRoutes disabled — re-enable once /blog, /ajuda, /privacidade pages exist
  // Next 15 promoted typedRoutes out of `experimental` to a top-level option.
  typedRoutes: false
};
export default config;
