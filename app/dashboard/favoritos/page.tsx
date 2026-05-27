import Link from "next/link";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { getDictionary } from "@/lib/i18n";
import { TruckCard } from "@/components/TruckCard";

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
          {favorites.map((r: any) => (
            <TruckCard
              key={r.truck_id}
              truck={r.airfnb_v_truck_card}
              // Everything on this page is by definition a favorite —
              // the heart starts filled, the toggle still works.
              initialFavorited={true}
              authed={true}
              newLabel={t.empty_state /* not used; truck always rated by this point — placeholder */}
            />
          ))}
        </div>
      )}
    </div>
  );
}
