import type { Metadata } from "next";
import "./globals.css";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import { supabaseServer } from "@/lib/supabase/server";

const APP_URL = process.env.APP_URL ?? process.env.NEXT_PUBLIC_APP_URL ?? "https://airfnb.vercel.app";

export const metadata: Metadata = {
  metadataBase: new URL(APP_URL),
  title: {
    default: "Air F&B — Marketplace de Food Trucks para Eventos",
    template: "%s · Air F&B",
  },
  description:
    "Publica o teu evento e recebe propostas dos melhores food trucks do país. Grátis para organizers.",
  applicationName: "Air F&B",
  openGraph: {
    type: "website",
    siteName: "Air F&B",
    title: "Air F&B — Marketplace de Food Trucks para Eventos",
    description:
      "Publica o teu evento e recebe propostas dos melhores food trucks do país. Grátis para organizers.",
    locale: "pt_PT",
    url: APP_URL,
    images: [{ url: "/logo-airfb-white.png", width: 1200, height: 630, alt: "Air F&B" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Air F&B — Marketplace de Food Trucks para Eventos",
    description:
      "Publica o teu evento e recebe propostas dos melhores food trucks do país. Grátis para organizers.",
    images: ["/logo-airfb-white.png"],
  },
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
