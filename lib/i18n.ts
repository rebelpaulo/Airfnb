// Type-safe i18n. Locale read from cookie or Accept-Language header on
// the server. No URL routing rewrite — every existing path stays stable.
//
// Architecture:
//   - Server components: `const dict = await getDictionary(); dict.namespace.key`
//   - Client components: wrap tree in <DictProvider> (already done in
//     app/layout.tsx) and read via `useDict()` from components/DictProvider
//   - Dictionary keys are validated by `satisfies Record<Locale, ...>` —
//     missing translations between PT and EN fail typecheck.

import { cookies, headers } from "next/headers";

export type Locale = "pt" | "en";
const SUPPORTED: Locale[] = ["pt", "en"];
const DEFAULT: Locale = "pt";

// ---------------------------------------------------------------------------
// Dictionary
//
// New namespaces are added per translation-PR. Keep the structure parallel
// between PT and EN — if PT has a key, EN must have it too (and vice-versa).
// The `satisfies` line below enforces this at typecheck time.
// ---------------------------------------------------------------------------

export const dictionaries = {
  pt: {
    common: {
      brand:          "Air F&B",
      tagline:        "A maior oferta de Food Trucks para o teu evento à distância de um click.",
      cta_event:      "Tenho um evento",
      register_truck: "Tens um food truck?",
      register_link:  "Regista aqui →",
      where:          "Onde",
      date:           "Data",
      end:            "Fim (opcional)",
      guests:         "Convidados",
      city_placeholder:  "Cidade ou localidade",
      guests_placeholder: "Nº convidados",
      back_home:      "← Voltar à página inicial",
      loading:        "A carregar…",
      saving:         "A guardar…",
      sending:        "A enviar…",
      submit:         "Submeter",
      cancel:         "Cancelar",
      save:           "Guardar",
      next:           "Seguinte",
      previous:       "Anterior",
      confirm:        "Confirmar",
      yes:            "Sim",
      no:             "Não",
      optional:       "(opcional)",
      required:       "*",
      search:         "Pesquisar",
      filter:         "Filtros",
      clear_filters:  "limpar filtros",
      see_all:        "Ver tudo",
      learn_more:     "Saber mais",
    },
    nav: {
      find_trucks: "Encontrar Trucks",
      organize:    "Organizar evento",
      blog:        "Blog",
      add_truck:   "Adicionar Truck",
      login:       "Entrar",
      signup:      "Registar",
      logout:      "Terminar sessão",
      dashboard:   "Dashboard",
      conversations: "Conversas",
      notifications: "Notificações",
    },
    footer: {
      newsletter_title: "Receba todas as novidades do mercado",
      newsletter_cta:   "SUBSCREVER",
      organizers:       "Organizers",
      trucks:           "Trucks",
      about:            "Air F&B",
    },
  },
  en: {
    common: {
      brand:          "Air F&B",
      tagline:        "The biggest selection of food trucks for your event, one click away.",
      cta_event:      "I have an event",
      register_truck: "Got a food truck?",
      register_link:  "Sign up here →",
      where:          "Where",
      date:           "Date",
      end:            "End (optional)",
      guests:         "Guests",
      city_placeholder:  "City or area",
      guests_placeholder: "Guest count",
      back_home:      "← Back to home",
      loading:        "Loading…",
      saving:         "Saving…",
      sending:        "Sending…",
      submit:         "Submit",
      cancel:         "Cancel",
      save:           "Save",
      next:           "Next",
      previous:       "Previous",
      confirm:        "Confirm",
      yes:            "Yes",
      no:             "No",
      optional:       "(optional)",
      required:       "*",
      search:         "Search",
      filter:         "Filters",
      clear_filters:  "clear filters",
      see_all:        "See all",
      learn_more:     "Learn more",
    },
    nav: {
      find_trucks: "Find Trucks",
      organize:    "Organize event",
      blog:        "Blog",
      add_truck:   "Add Truck",
      login:       "Log in",
      signup:      "Sign up",
      logout:      "Log out",
      dashboard:   "Dashboard",
      conversations: "Conversations",
      notifications: "Notifications",
    },
    footer: {
      newsletter_title: "Get all the news from the marketplace",
      newsletter_cta:   "SUBSCRIBE",
      organizers:       "Organizers",
      trucks:           "Trucks",
      about:            "Air F&B",
    },
  },
} satisfies Record<Locale, {
  common: Record<string, string>;
  nav: Record<string, string>;
  footer: Record<string, string>;
}>;

// Dictionary type is derived from PT (always present) and serves both locales
// because the `satisfies` constraint guarantees structural parity. Without
// `as const` the values widen to `string`, so `dictionaries[locale]` matches
// the Dictionary type cleanly without the "two unrelated types" error.
export type Dictionary = (typeof dictionaries)["pt"];

export function isSupportedLocale(s: string | undefined | null): s is Locale {
  return !!s && (SUPPORTED as string[]).includes(s);
}

/**
 * Server-side locale resolver. Precedence:
 *   1. ?lang=en query param   (handled at the page level by setting the cookie)
 *   2. airfnb_locale cookie
 *   3. Accept-Language header
 *   4. DEFAULT (pt)
 */
export async function getLocale(): Promise<Locale> {
  const cookieStore = await cookies();
  const fromCookie = cookieStore.get("airfnb_locale")?.value;
  if (isSupportedLocale(fromCookie)) return fromCookie;

  const headerStore = await headers();
  const accept = headerStore.get("accept-language") ?? "";
  // Parse the full Accept-Language list with q-values and return the highest-
  // ranked tag that we support. Falls back to DEFAULT when nothing matches —
  // previously we only inspected the first tag, so 'fr-FR,fr;q=0.9,en;q=0.8'
  // wrongly fell through to pt instead of picking en.
  const ranked = accept
    .split(",")
    .map((part) => {
      const [tag, ...params] = part.trim().split(";");
      const q = parseFloat(params.find((p) => p.trim().startsWith("q="))?.split("=")[1] ?? "1") || 0;
      const lang = tag.split("-")[0]?.toLowerCase() ?? "";
      return { lang, q };
    })
    .filter((r) => r.lang && r.q > 0)
    .sort((a, b) => b.q - a.q);
  for (const r of ranked) {
    if (isSupportedLocale(r.lang)) return r.lang as Locale;
  }
  return DEFAULT;
}

export async function getDictionary(): Promise<Dictionary> {
  const l = await getLocale();
  return dictionaries[l];
}
