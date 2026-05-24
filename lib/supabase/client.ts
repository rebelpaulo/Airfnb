"use client";
import { createBrowserClient } from "@supabase/ssr";
import type { AirfnbDatabase } from "@/types/database";

function readEnv() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anon) {
    // Fail loudly with a clear error instead of mysterious "fetch failed"
    // errors deep inside supabase-js when the env is missing.
    throw new Error(
      "Missing Supabase env. Set NEXT_PUBLIC_SUPABASE_URL and " +
      "NEXT_PUBLIC_SUPABASE_ANON_KEY in your environment (.env.local for dev).",
    );
  }
  return { url, anon };
}

export function supabaseBrowser() {
  const { url, anon } = readEnv();
  return createBrowserClient<AirfnbDatabase>(url, anon);
}
