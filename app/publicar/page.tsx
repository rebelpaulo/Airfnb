import type { Metadata } from "next";
import { redirect } from "next/navigation";
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

export default async function PublicarPage({ searchParams }: {
  searchParams: Promise<{ city?: Raw; start_at?: Raw; end_at?: Raw; expected_pax?: Raw; cuisines?: Raw }>;
}) {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) {
    // Preserve the discovery context across the auth detour. The login page
    // sends users back to the `next` URL with the same query string, so
    // /procurar → /login → /publicar?city=... still works.
    const sp = await searchParams;
    const qs = new URLSearchParams();
    const c = first(sp.city);          if (c) qs.set("city", c);
    const s = first(sp.start_at);      if (s) qs.set("start_at", s);
    const e = first(sp.end_at);        if (e) qs.set("end_at", e);
    const p = first(sp.expected_pax);  if (p) qs.set("expected_pax", p);
    const cu = first(sp.cuisines);     if (cu) qs.set("cuisines", cu);
    const tail = qs.toString();
    const next = tail ? `/publicar?${tail}` : "/publicar";
    redirect(`/login?next=${encodeURIComponent(next)}&as=organizer`);
  }
  const sp = await searchParams;
  const prefill = {
    city:     first(sp.city) ?? "",
    startAt:  first(sp.start_at) ?? "",
    endAt:    first(sp.end_at) ?? "",
    pax:      num(sp.expected_pax),
    cuisines: csv(sp.cuisines),
  };

  const dict = await getDictionary();
  const t = dict.gates.publicar;

  const { data: profile } = await (supa as any)
    .from("airfnb_profiles")
    .select("full_name, display_name, email, phone, role")
    .eq("id", user.id)
    .maybeSingle();

  // Resolve a display-ready name: prefer the public-facing display_name
  // (set in /dashboard/perfil) and fall back to the legal full_name from
  // signup. Either is fine for the wizard's "contact_name" field.
  const resolvedName  = (profile?.display_name?.trim() || profile?.full_name?.trim() || "");
  const resolvedEmail = (profile?.email?.trim() || user.email?.trim() || "");
  const resolvedPhone = (profile?.phone?.trim() || "");

  // If the user already has name + email + phone in their profile, the
  // wizard hides the first 3 fields and shows a compact "publishing as X"
  // header instead — the values still ride through as hidden inputs so
  // the submit payload is unchanged. Without this gate, returning users
  // see the same fields twice (profile + wizard) which feels broken.
  const profileComplete = !!(resolvedName && resolvedEmail && resolvedPhone);

  // Roles are exclusive — a truck owner can't pivot into organizing events.
  // They have to use a different email.
  if (profile?.role === "owner") {
    return <WrongAccountType intent="organize_event" currentRole="owner" />;
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
        userId={user.id}
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
