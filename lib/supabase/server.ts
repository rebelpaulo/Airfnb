import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import type { AirfnbDatabase } from "@/types/database";

export async function supabaseServer() {
  const store = await cookies();
  return createServerClient<AirfnbDatabase>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => store.getAll(),
        setAll: (xs) => {
          try {
            xs.forEach(({ name, value, options }) => store.set(name, value, options));
          } catch {
            /* called from server component during render — ignore */
          }
        },
      },
    },
  );
}

export function supabaseAdmin() {
  // service-role client. Use only in trusted server actions/route handlers.
  const { createClient } = require("@supabase/supabase-js");
  return createClient<AirfnbDatabase>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
}
