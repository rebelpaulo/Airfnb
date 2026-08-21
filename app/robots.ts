import type { MetadataRoute } from "next";
import { resolveAppOrigin } from "@/lib/app-url.mjs";

const APP_URL = resolveAppOrigin();

const PRIVATE_ROUTES = [
  "/admin",
  "/api/",
  "/auth/",
  "/dashboard/",
  "/login",
  "/signup",
  "/forgot-password",
  "/reset-password",
  "/onboarding/",
  "/logout",
] as const;

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: "*",
        allow: "/",
        // robots.txt is advisory crawl guidance only; authorization is enforced by the application.
        disallow: [...PRIVATE_ROUTES],
      },
    ],
    sitemap: `${APP_URL}/sitemap.xml`,
    host: APP_URL,
  };
}
