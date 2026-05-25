"use server";

import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";

/**
 * Toggle a truck in the current user's favourites. Returns the resulting
 * state so the client can confirm or correct an optimistic update.
 *
 * Throws on auth missing (the caller's error boundary catches it) — the
 * heart UI is only rendered to authenticated visitors anyway, and a missing
 * cookie usually means the session expired mid-page.
 */
export async function toggleFavorite(truckId: string): Promise<{ favorited: boolean }> {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) throw new Error("auth required");
  if (!truckId) throw new Error("truck_id required");

  // Read current state first so we know which branch to take. Costs an
  // extra round-trip but lets us return the post-mutation state without a
  // follow-up read.
  //
  // NOTE: the read-then-write here has a race window — two near-simultaneous
  // calls from different tabs could either both INSERT (one hits unique
  // violation) or both DELETE (idempotent, no harm). Within a single tab
  // the HeartButton disables itself via useTransition so this is unreachable.
  // Cross-tab race is rare; the bad path is a one-shot error toast. A true
  // atomic toggle would need an RPC (`airfnb_toggle_favorite`) — TODO.
  const { data: existing } = await (supa as any)
    .from("airfnb_favorites")
    .select("truck_id")
    .eq("user_id", user.id)
    .eq("truck_id", truckId)
    .maybeSingle();

  if (existing) {
    const { error } = await (supa as any)
      .from("airfnb_favorites")
      .delete()
      .eq("user_id", user.id)
      .eq("truck_id", truckId);
    if (error) throw new Error(error.message);
    revalidatePath("/dashboard/favoritos");
    return { favorited: false };
  }

  const { error } = await (supa as any)
    .from("airfnb_favorites")
    .insert({ user_id: user.id, truck_id: truckId });
  if (error) throw new Error(error.message);
  revalidatePath("/dashboard/favoritos");
  return { favorited: true };
}

/**
 * Fetch the set of truck IDs the current user has favourited. Returns an
 * empty Set for unauthenticated visitors so the catalog can render
 * unfavourited hearts without crashing.
 */
export async function getFavoritedTruckIds(): Promise<Set<string>> {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) return new Set();

  const { data, error } = await (supa as any)
    .from("airfnb_favorites")
    .select("truck_id")
    .eq("user_id", user.id);
  if (error) return new Set();
  return new Set((data as { truck_id: string }[]).map((r) => r.truck_id));
}
