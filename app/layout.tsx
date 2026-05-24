import type { Metadata } from "next";
import "./globals.css";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import { supabaseServer } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "Air F&B — Marketplace de Food Trucks para Eventos",
  description:
    "Publica o teu evento e recebe propostas dos melhores food trucks do país. Grátis para organizers.",
};

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();

  let role: string | null = null;
  let avatarUrl: string | null = null;
  let displayName: string | null = null;
  if (user) {
    const { data: prof } = await (supa as any)
      .from("airfnb_profiles")
      .select("role, avatar_url, full_name, display_name")
      .eq("id", user.id)
      .maybeSingle();
    role = prof?.role ?? null;
    avatarUrl = prof?.avatar_url ?? null;
    displayName = prof?.display_name ?? prof?.full_name ?? null;
  }

  return (
    <html lang="pt">
      <head>
        <link
          href="https://fonts.googleapis.com/css2?family=Bebas+Neue&family=Montserrat:wght@400;500;600;700&display=swap"
          rel="stylesheet"
        />
        <link
          href="https://fonts.googleapis.com/icon?family=Material+Symbols+Outlined"
          rel="stylesheet"
        />
      </head>
      <body>
        <Header user={
          user
            ? { id: user.id, email: user.email ?? "", role, avatarUrl, displayName }
            : null
        } />
        <main>{children}</main>
        <Footer />
      </body>
    </html>
  );
}
