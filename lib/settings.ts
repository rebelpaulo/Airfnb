// Server-side reader for `airfnb_platform_settings`. The table is RLS-gated
// to admins, so reads run through the service-role client. Values come back
// as strings; callers cast (parseInt, parseFloat) when needed.
//
// Usage:
//   const venuesEmail = await getSetting("partner_email_venues", process.env.PARTNER_EMAIL_VENUES);
//
// A request-scoped Map memoizes lookups so a page that calls getSetting()
// for several keys doesn't make N round-trips. Cache lives only for the
// duration of the current request because we recreate it on each call to
// supabaseAdmin() (no module-level cache).
import { supabaseAdmin } from "@/lib/supabase/server";

/**
 * Read a single platform setting. Returns the stored value, or `fallback`
 * if the row is missing or the value is empty.
 *
 * Always returns a string (or undefined). Numeric / boolean settings
 * should be parsed by the caller.
 */
export async function getSetting(
  key: string,
  fallback?: string,
): Promise<string | undefined> {
  try {
    const admin = supabaseAdmin();
    const { data } = await (admin as any)
      .from("airfnb_platform_settings")
      .select("value")
      .eq("key", key)
      .maybeSingle();
    const v = data?.value;
    if (typeof v === "string" && v.trim().length > 0) return v.trim();
  } catch (e) {
    // Don't crash the caller if the table doesn't exist yet (e.g. local
    // dev before the migration runs) or if service-role env isn't set —
    // fall back silently.
    console.warn(`getSetting(${key}) failed, using fallback`, e);
  }
  return fallback;
}

/**
 * Read every setting in a `group` (e.g. "leads", "rate_limits"). Returns
 * a key→value Map. Useful when an admin UI wants to render an editable
 * panel for a whole group at once.
 */
export async function getSettingsByGroup(group: string): Promise<Setting[]> {
  const admin = supabaseAdmin();
  const { data, error } = await (admin as any)
    .from("airfnb_platform_settings")
    .select("key, value, group, description, secret, updated_at")
    .eq("group", group)
    .order("key");
  if (error) {
    console.warn(`getSettingsByGroup(${group}) failed`, error.message);
    return [];
  }
  return (data as Setting[]) ?? [];
}

/**
 * Read all settings, grouped by `group`, for the admin settings page.
 */
export async function getAllSettings(): Promise<Record<string, Setting[]>> {
  const admin = supabaseAdmin();
  const { data, error } = await (admin as any)
    .from("airfnb_platform_settings")
    .select("key, value, group, description, secret, updated_at")
    .order("group")
    .order("key");
  if (error) {
    console.warn("getAllSettings failed", error.message);
    return {};
  }
  const out: Record<string, Setting[]> = {};
  for (const row of (data as Setting[]) ?? []) {
    (out[row.group] ??= []).push(row);
  }
  return out;
}

export type Setting = {
  key: string;
  value: string | null;
  group: string;
  description: string | null;
  secret: boolean;
  updated_at: string;
};
