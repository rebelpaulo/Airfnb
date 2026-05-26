/** @type {import('next').NextConfig} */
const config = {
  images: {
    remotePatterns: [
      { protocol: "https", hostname: "images.unsplash.com" },
      { protocol: "https", hostname: "rvcvyeodglovmptcuyiz.supabase.co" }
    ],
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
