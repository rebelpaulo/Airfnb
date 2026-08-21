import type { Metadata } from "next";
import { Bebas_Neue, Montserrat } from "next/font/google";
import "./globals.css";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import { DictProvider } from "@/components/DictProvider";
import { supabaseServer } from "@/lib/supabase/server";
import { getLocale, dictionaries } from "@/lib/i18n";
import { resolveAppOrigin } from "@/lib/app-url.mjs";
import { publicAvatarUrl } from "@/lib/public-avatar-url";

const bebas = Bebas_Neue({
  subsets: ["latin"],
  weight: "400",
  variable: "--font-bebas",
  display: "swap",
});
const montserrat = Montserrat({
  subsets: ["latin"],
  weight: ["400", "600", "700"],
  variable: "--font-montserrat",
  display: "swap",
});

const APP_URL = resolveAppOrigin();

export const metadata: Metadata = {
  metadataBase: new URL(APP_URL),
  title: {
    default: "F&B Tailor — Food Trucks, Catering e Bares para Eventos",
    template: "%s · F&B Tailor",
  },
  description: "Food Trucks, Catering e Bares para Eventos. Encontra fornecedores selecionados e recebe propostas para o teu evento.",
  applicationName: "F&B Tailor",
  keywords: [
    "food trucks para eventos",
    "catering para eventos",
    "bares para eventos",
    "fornecedores para eventos",
    "F&B Tailor",
  ],
  category: "eventos",
  robots: { index: true, follow: true },
  openGraph: {
    type: "website",
    siteName: "F&B Tailor",
    title: "F&B Tailor — Food Trucks, Catering e Bares para Eventos",
    description: "Food Trucks, Catering e Bares para Eventos. Encontra fornecedores selecionados e recebe propostas para o teu evento.",
    locale: "pt_PT",
    url: APP_URL,
    images: [{ url: "/og-fb-tailor.png", width: 1200, height: 630, alt: "F&B Tailor — Food Trucks, Catering e Bares para Eventos" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "F&B Tailor — Food Trucks, Catering e Bares para Eventos",
    description: "Food Trucks, Catering e Bares para Eventos. Encontra fornecedores selecionados e recebe propostas para o teu evento.",
    images: ["/og-fb-tailor.png"],
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
    avatarUrl = publicAvatarUrl(
      prof?.avatar_url,
      process.env.NEXT_PUBLIC_SUPABASE_URL,
    );
    displayName = prof?.display_name ?? prof?.full_name ?? null;
  }

  const locale = await getLocale();
  const dict = dictionaries[locale];

  return (
    <html lang={locale} className={`${bebas.variable} ${montserrat.variable}`}>
      <head>
        {/* Material Symbols stays as a <link> — it's an icon font, not available via next/font/google. */}
        <link
          href="https://fonts.googleapis.com/icon?family=Material+Symbols+Outlined"
          rel="stylesheet"
        />
      </head>
      <body>
        {/* DictProvider lets any client component in the tree read translations
            via useDict() without prop-drilling. Server components keep calling
            getDictionary() from lib/i18n directly. */}
        <DictProvider dict={dict} locale={locale}>
          <Header
            locale={locale}
            user={
              user
                ? { id: user.id, email: user.email ?? "", role, avatarUrl, displayName }
                : null
            }
          />
          <main>{children}</main>
          <Footer />
        </DictProvider>
      </body>
    </html>
  );
}
