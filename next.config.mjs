/** @type {import('next').NextConfig} */
const config = {
  images: {
    remotePatterns: [
      { protocol: "https", hostname: "images.unsplash.com" },
      { protocol: "https", hostname: "rvcvyeodglovmptcuyiz.supabase.co" }
    ]
  },
  // typedRoutes disabled — re-enable once /blog, /ajuda, /privacidade pages exist
  experimental: { typedRoutes: false }
};
export default config;
