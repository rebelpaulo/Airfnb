import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";
import { cookies } from "next/headers";
import type { AirfnbDatabase } from "@/types/database";

type SupaCookie = { name: string; value: string; options?: CookieOptions };

export async function supabaseServer() {
  const store = await cookies();
  return createServerClient<AirfnbDatabase>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => store.getAll(),
        setAll: (xs: SupaCookie[]) => {
          try {
            xs.forEach(({ name, value, options }) => store.set(name, value, options));
          } catch {
            /* called from a server component during render — ignore */
          }
        },
      },
    },
  );
}

/** Service-role client. Use ONLY in trusted server actions or route handlers. */
export function supabaseAdmin() {
  return createClient<AirfnbDatabase>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
}
