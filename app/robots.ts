import type { MetadataRoute } from "next";

const APP_URL = process.env.APP_URL ?? process.env.NEXT_PUBLIC_APP_URL ?? "https://airfnb.vercel.app";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: "*",
        allow: "/",
        // Auth-gated dashboards have no public value, and the api routes are
        // server-only. Block crawl explicitly so noisy bots don't waste budget.
        disallow: ["/dashboard/", "/api/", "/auth/"],
      },
    ],
    sitemap: `${APP_URL}/sitemap.xml`,
    host: APP_URL,
  };
}
