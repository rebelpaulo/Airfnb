import type { SupabaseClient } from "@supabase/supabase-js";
import type { AirfnbDatabase } from "@/types/database";

export type FbSelfServiceRole = "owner" | "organizer";

type FbMembershipClient = Pick<SupabaseClient<AirfnbDatabase>, "rpc">;
type FbProfile = AirfnbDatabase["public"]["Tables"]["airfnb_profiles"]["Row"];

type EnsureFbProfileOptions = {
  fullName?: string | null;
  locale?: "pt-PT" | "en";
};

type EnsureFbMembershipOptions = EnsureFbProfileOptions & {
  role: FbSelfServiceRole;
};

function rpcError(operation: string, error: { message: string }): Error {
  return new Error(`${operation}: ${error.message}`);
}

/** Bootstrap the authenticated actor's F&B profile without assigning a role. */
export async function ensureFbProfile(
  client: FbMembershipClient,
  options: EnsureFbProfileOptions = {},
): Promise<FbProfile> {
  const { data, error } = await client.rpc("airfnb_ensure_profile", {
    p_full_name: options.fullName ?? null,
    p_locale: options.locale ?? "pt-PT",
  });

  if (error) throw rpcError("F&B profile bootstrap failed", error);
  if (!data) throw new Error("F&B profile bootstrap returned no profile");
  return data;
}

/**
 * Bootstrap the authenticated actor, then make an explicit one-time role claim.
 * The caller cannot nominate a user id or request privileged roles.
 */
export async function ensureFbMembership(
  client: FbMembershipClient,
  options: EnsureFbMembershipOptions,
): Promise<FbProfile> {
  await ensureFbProfile(client, options);

  const { data, error } = await client.rpc("airfnb_claim_role", {
    p_role: options.role,
  });

  if (error) throw rpcError("F&B role claim failed", error);
  if (!data) throw new Error("F&B role claim returned no profile");
  return data;
}

export function parseFbSelfServiceRole(value: string | null): FbSelfServiceRole | null {
  return value === "owner" || value === "organizer" ? value : null;
}
