import type { MetadataRoute } from "next";
import { supabaseServer } from "@/lib/supabase/server";

const APP_URL = process.env.APP_URL ?? process.env.NEXT_PUBLIC_APP_URL ?? "https://airfnb.vercel.app";

/**
 * Dynamic sitemap pulling every active truck plus the static marketing pages.
 * Re-generated at most once per hour so search engines see fresh entries
 * without hammering the catalog view.
 */
export const revalidate = 3600;

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const supa = await supabaseServer();
  const { data } = await (supa as any)
    .from("airfnb_v_truck_card")
    .select("slug, updated_at:rating_count")
    .limit(2000);

  const trucks = (data as { slug: string }[] | null) ?? [];
  const now = new Date();

  const staticUrls: MetadataRoute.Sitemap = [
    { url: `${APP_URL}/`,            lastModified: now, changeFrequency: "weekly",  priority: 1.0 },
    { url: `${APP_URL}/catalogo`,    lastModified: now, changeFrequency: "daily",   priority: 0.9 },
    { url: `${APP_URL}/publicar`,    lastModified: now, changeFrequency: "monthly", priority: 0.7 },
    { url: `${APP_URL}/registar`,    lastModified: now, changeFrequency: "monthly", priority: 0.7 },
    { url: `${APP_URL}/blog`,        lastModified: now, changeFrequency: "weekly",  priority: 0.5 },
    { url: `${APP_URL}/sobre-nos`,   lastModified: now, changeFrequency: "yearly",  priority: 0.4 },
    { url: `${APP_URL}/equipa`,      lastModified: now, changeFrequency: "yearly",  priority: 0.3 },
    { url: `${APP_URL}/ajuda`,       lastModified: now, changeFrequency: "monthly", priority: 0.3 },
    { url: `${APP_URL}/privacidade`, lastModified: now, changeFrequency: "yearly",  priority: 0.3 },
  ];

  const truckUrls: MetadataRoute.Sitemap = trucks.map((t) => ({
    url:            `${APP_URL}/catalogo/${t.slug}`,
    lastModified:   now,
    changeFrequency: "weekly",
    priority:       0.8,
  }));

  return [...staticUrls, ...truckUrls];
}
