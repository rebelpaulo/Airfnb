"use client";
import { createBrowserClient } from "@supabase/ssr";
import type { AirfnbDatabase } from "@/types/database";

export function supabaseBrowser() {
  return createBrowserClient<AirfnbDatabase>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
