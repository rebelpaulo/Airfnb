"use client";

import { createContext, useContext, type ReactNode } from "react";
import type { Dictionary, Locale } from "@/lib/i18n";

/**
 * Client-side dictionary access.
 *
 * Server components should call `getDictionary()` from lib/i18n directly.
 * Client components — which can't await server functions — read the dict
 * from this Context, populated by <DictProvider> in the root layout.
 *
 * Example usage in a client component:
 *
 *     "use client";
 *     import { useDict } from "@/components/DictProvider";
 *     export function MyButton() {
 *       const dict = useDict();
 *       return <button>{dict.common.cta_event}</button>;
 *     }
 *
 * If a component reads `useDict()` outside of any provider it throws —
 * better to fail loud at boot than show keys silently in production.
 */

type Ctx = {
  dict: Dictionary;
  locale: Locale;
};

const DictContext = createContext<Ctx | null>(null);

export function DictProvider({ dict, locale, children }: { dict: Dictionary; locale: Locale; children: ReactNode }) {
  return <DictContext.Provider value={{ dict, locale }}>{children}</DictContext.Provider>;
}

export function useDict(): Dictionary {
  const ctx = useContext(DictContext);
  if (!ctx) {
    throw new Error(
      "useDict() must be used inside <DictProvider>. Wrap your tree in app/layout.tsx.",
    );
  }
  return ctx.dict;
}

export function useLocale(): Locale {
  const ctx = useContext(DictContext);
  if (!ctx) {
    throw new Error(
      "useLocale() must be used inside <DictProvider>. Wrap your tree in app/layout.tsx.",
    );
  }
  return ctx.locale;
}
