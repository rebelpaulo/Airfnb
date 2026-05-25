// Server-side sign-out → redirect. Used by the WrongAccountType block
// page so a user with the wrong role can sign out + bounce straight to the
// correct signup flow in one click.
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type SP = Promise<{ next?: string }>;

function safeNext(raw: string | undefined): string {
  if (!raw) return "/";
  // only allow same-origin relative paths
  if (raw === "/" || /^\/[^/\\]/.test(raw)) return raw;
  return "/";
}

export default async function LogoutPage({ searchParams }: { searchParams: SP }) {
  const { next } = await searchParams;
  const supa = await supabaseServer();
  // signOut clears the supabase cookies via the cookie adapter wired in
  // supabaseServer(). Errors here aren't fatal — even if the row in
  // auth.refresh_tokens fails to delete, the local cookies are gone and
  // we'd rather move the user along than show a scary screen.
  try { await supa.auth.signOut(); } catch { /* noop */ }
  redirect(safeNext(next));
}
