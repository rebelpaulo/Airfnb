import type { Metadata } from "next";
import { supabaseServer } from "@/lib/supabase/server";
import { OrganizerWizard } from "./OrganizerWizard";
import { WrongAccountType } from "@/components/WrongAccountType";
import { getDictionary } from "@/lib/i18n";

// TODO(i18n): metadata is rendered before locale resolution; kept in PT for now.
// Migrate to generateMetadata async + getDictionary() once we accept the
// extra dynamic render.
export const metadata: Metadata = {
  title: "Publicar pedido",
  description:
    "Publica o teu evento grátis e recebe propostas dos melhores food trucks do país em poucas horas.",
  alternates: { canonical: "/publicar" },
};

export const dynamic = "force-dynamic";

// URL params come in from the /procurar discovery page CTA so the wizard's
// step 1 (location, dates, pax, cuisines) can be pre-populated. Each field
// is best-effort — missing or malformed values just fall back to the
// component defaults.
type Raw = string | string[] | undefined;
function first(v: Raw): string | undefined {
  if (v == null) return undefined;
  const s = Array.isArray(v) ? v[0] : v;
  return typeof s === "string" ? s.trim() || undefined : undefined;
}
function num(v: Raw): number | undefined {
  const s = first(v);
  if (!s) return undefined;
  const n = Number(s);
  return Number.isFinite(n) && n > 0 ? n : undefined;
}
function csv(v: Raw): string[] {
  const s = first(v);
  if (!s) return [];
  return s.split(",").map((x) => x.trim()).filter(Boolean);
}
// Validate a `YYYY-MM-DD` string against Date parsing so a malformed
// URL param doesn't slip through step-1 validation (which only checks
// non-empty) and then crash at `new Date(startAt).toISOString()` in
// submitAll. Returns "" for anything that's not a real calendar date.
function isoDate(v: Raw): string {
  const s = first(v) ?? "";
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return "";
  const d = new Date(s);
  return Number.isNaN(d.getTime()) ? "" : s;
}

export default async function PublicarPage({ searchParams }: {
  searchParams: Promise<{ city?: Raw; start_at?: Raw; end_at?: Raw; expected_pax?: Raw; cuisines?: Raw }>;
}) {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  // Anonymous publish: organizers can fill the wizard without an account.
  // signUp + insert run together at the final step (the wizard collects
  // password + ToS consent in step 5 when isAuthenticated=false). The
  // previous behaviour — redirect to /login first — added friction at the
  // top of the funnel where we have the most to lose.
  const sp = await searchParams;
  const prefill = {
    city:     first(sp.city) ?? "",
    startAt:  isoDate(sp.start_at),
    endAt:    isoDate(sp.end_at),
    pax:      num(sp.expected_pax),
    cuisines: csv(sp.cuisines),
  };

  const dict = await getDictionary();
  const t = dict.gates.publicar;

  // Authenticated branch: pull the profile so we can pre-populate
  // contact fields and gate truck-owners out (roles are exclusive).
  let resolvedName  = "";
  let resolvedEmail = "";
  let resolvedPhone = "";
  let profileComplete = false;
  if (user) {
    const { data: profile } = await (supa as any)
      .from("airfnb_profiles")
      .select("full_name, display_name, phone, role")
      .eq("id", user.id)
      .maybeSingle();
    if (profile?.role === "owner") {
      return <WrongAccountType intent="organize_event" currentRole="owner" />;
    }
    resolvedName  = (profile?.display_name?.trim() || profile?.full_name?.trim() || "");
    resolvedEmail = (user.email?.trim() || "");
    resolvedPhone = (profile?.phone?.trim() || "");
    profileComplete = !!(resolvedName && resolvedEmail && resolvedPhone);
  }

  const { data: categoriesData } = await (supa as any)
    .from("airfnb_categories")
    .select("id, slug, name_pt, icon")
    .order("name_pt");

  return (
    <div className="dash" style={{ maxWidth: 920 }}>
      <h1 style={{ margin: 0 }}>{t.page_title}</h1>
      <p style={{ color: "var(--muted)", margin: "6px 0 22px" }}>
        {t.intro}
      </p>
      <OrganizerWizard
        userId={user?.id ?? null}
        defaultName={resolvedName}
        defaultEmail={resolvedEmail}
        defaultPhone={resolvedPhone}
        profileComplete={profileComplete}
        categories={categoriesData ?? []}
        defaultCity={prefill.city}
        defaultStartAt={prefill.startAt}
        defaultEndAt={prefill.endAt}
        defaultGuests={prefill.pax}
        defaultCuisines={prefill.cuisines}
      />
    </div>
  );
}
