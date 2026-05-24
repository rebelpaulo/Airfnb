/** @type {import('next').NextConfig} */
const config = {
  images: {
    remotePatterns: [
      { protocol: "https", hostname: "images.unsplash.com" },
      { protocol: "https", hostname: "rvcvyeodglovmptcuyiz.supabase.co" }
    ]
  },
  experimental: { typedRoutes: true }
};
export default config;
