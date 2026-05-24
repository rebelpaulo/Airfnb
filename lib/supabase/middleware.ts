import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

export async function updateSession(req: NextRequest) {
  let res = NextResponse.next({ request: req });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => req.cookies.getAll(),
        setAll: (xs) => {
          xs.forEach(({ name, value }) => req.cookies.set(name, value));
          res = NextResponse.next({ request: req });
          xs.forEach(({ name, value, options }) => res.cookies.set(name, value, options));
        },
      },
    },
  );
  // ensure auth tokens are refreshed
  await supabase.auth.getUser();
  return res;
}
