"use client";

import { useState, useTransition } from "react";
import { toggleFavorite } from "@/lib/favorites";
import { useDict } from "@/components/DictProvider";

type Props = {
  truckId: string;
  /** Whether the truck is currently favourited (server-rendered initial state). */
  initialFavorited: boolean;
  /** When false, render a sign-in CTA instead of the toggle. */
  authed: boolean;
  /** Size in px for the icon container; defaults to 36 (matches the truck-card .heart style). */
  size?: number;
  /** When true, button is absolutely-positioned within a truck card thumb (default). */
  absolute?: boolean;
};

/**
 * Heart toggle for adding/removing a truck from the user's favourites.
 *
 * Uses optimistic updates: clicking flips local state immediately, then
 * fires the server action. If the action returns a different state (e.g.
 * race with another tab) we sync to its truth.
 *
 * For unauthenticated visitors we still render the heart (otherwise the
 * card looks broken) but it's a non-interactive label — clicks bounce
 * them to /login with `next` set to come back here.
 */
export function HeartButton({ truckId, initialFavorited, authed, size = 36, absolute = true }: Props) {
  const dict = useDict();
  const t = (dict as any).favorites_button ?? {
    add: "Adicionar aos favoritos",
    remove: "Remover dos favoritos",
    sign_in_required: "Entra para guardar",
  };
  const [favorited, setFavorited] = useState(initialFavorited);
  const [pending, startTransition] = useTransition();

  const label = !authed
    ? t.sign_in_required
    : favorited
      ? t.remove
      : t.add;

  function onClick(e: React.MouseEvent) {
    e.preventDefault(); // suppress the parent <Link> nav if the heart sits inside one
    e.stopPropagation();
    if (!authed) {
      // Include search + hash so the user lands back on the exact filter /
      // anchor they were looking at — losing the query string would make
      // the catalog reset after sign-in, which is jarring.
      const back = window.location.pathname + window.location.search + window.location.hash;
      window.location.href = `/login?next=${encodeURIComponent(back)}`;
      return;
    }
    // Optimistic flip
    setFavorited((v) => !v);
    startTransition(async () => {
      try {
        const res = await toggleFavorite(truckId);
        setFavorited(res.favorited);
      } catch {
        // Revert on failure — silently. The next page revalidation will
        // bring truth back if this was a real bug.
        setFavorited((v) => !v);
      }
    });
  }

  return (
    <button
      type="button"
      className="heart"
      aria-label={label}
      aria-pressed={favorited}
      onClick={onClick}
      disabled={pending}
      style={{
        ...(absolute ? {} : { position: "static" }),
        width: size, height: size,
        color: favorited ? "#FF4919" : "#666",
        transition: "color 0.15s, transform 0.12s",
        transform: pending ? "scale(0.92)" : undefined,
      }}
    >
      <span
        className="material-symbols-outlined"
        style={{
          fontSize: 20,
          fontVariationSettings: favorited ? '"FILL" 1' : '"FILL" 0',
        }}
        aria-hidden="true"
      >
        favorite
      </span>
    </button>
  );
}
