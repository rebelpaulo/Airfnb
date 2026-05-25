import Link from "next/link";
import Image from "next/image";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { getDictionary } from "@/lib/i18n";
import { truckCover } from "@/lib/img";

export const dynamic = "force-dynamic";

/**
 * User favourites — lists trucks the current user has hearted. Reads from
 * `airfnb_favorites` (user_id, truck_id, created_at) joined with the
 * truck-card view to get name/city/cover/etc.
 *
 * The heart toggle on truck cards / truck detail is a separate task; this
 * page is read-only for now and shows an empty state with a CTA to the
 * catalog when there's nothing saved.
 */
export default async function FavoritesPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/favoritos");

  const dict = await getDictionary();
  const t = dict.dashboard_favorites;

  // Pull the favourite rows then enrich with the truck card view in a single
  // query. The view `airfnb_v_truck_card` is already used by /catalogo, so
  // the shape and indexes are warm.
  const { data: favRows } = await (supa as any)
    .from("airfnb_favorites")
    .select("truck_id, created_at, airfnb_v_truck_card(*)")
    .eq("user_id", user.id)
    .order("created_at", { ascending: false });

  // Guard on `slug` (not just row existence) — without slug we'd build
  // an invalid `/catalogo/null` link below.
  const favorites = ((favRows as any[]) ?? []).filter((r) => r.airfnb_v_truck_card?.slug);

  return (
    <div className="dash" style={{ maxWidth: 1100, padding: "32px 28px" }}>
      <h1 style={{ margin: 0 }}>{t.page_title}</h1>
      <p style={{ color: "var(--muted)", marginTop: 6 }}>{t.subtitle}</p>

      {favorites.length === 0 ? (
        <div className="dash empty" style={{ marginTop: 30, padding: 28 }}>
          <p style={{ margin: 0, lineHeight: 1.6 }}>{t.empty_state}</p>
          <Link href="/catalogo" className="btn-pill" style={{ marginTop: 16, display: "inline-block" }}>
            {t.empty_cta}
          </Link>
        </div>
      ) : (
        <div className="truck-grid cols-3" style={{ marginTop: 26 }}>
          {favorites.map((r: any) => {
            const tr = r.airfnb_v_truck_card;
            return (
              <Link key={r.truck_id} href={`/catalogo/${tr.slug}`} className="truck-card">
                <div className="thumb" style={{ position: "relative" }}>
                  <Image
                    src={truckCover(tr.cover_url)}
                    alt={tr.name ?? "Truck"}
                    fill
                    sizes="(max-width: 600px) 100vw, (max-width: 1024px) 50vw, 33vw"
                    style={{ objectFit: "cover" }}
                  />
                </div>
                <div className="info">
                  <h3>{tr.name}</h3>
                  <div className="meta">
                    <span className="loc">
                      <span className="material-symbols-outlined" style={{ fontSize: 18, color: "#FF4919" }} aria-hidden="true">location_on</span>
                      {tr.base_city ?? "—"}
                    </span>
                  </div>
                </div>
              </Link>
            );
          })}
        </div>
      )}
    </div>
  );
}
