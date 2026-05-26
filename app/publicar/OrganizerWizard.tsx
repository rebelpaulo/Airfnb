"use client";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { CityAutocomplete } from "@/components/CityAutocomplete";
import { useDict } from "@/components/DictProvider";

// Inline placeholder formatter (kept local because lib/i18n imports
// next/headers, which can't be bundled into client components).
function format(template: string, vars: Record<string, string | number>): string {
  return Object.entries(vars).reduce(
    (out, [k, v]) => out.replace(`{${k}}`, String(v)),
    template,
  );
}

type Category = { id: number; slug: string; name_pt: string; icon: string | null };
type Props = {
  /** Null when an anonymous visitor lands on /publicar — wizard then
   *  collects password + ToS in step 5 and signs them up before insert. */
  userId: string | null;
  defaultName: string;
  defaultEmail: string;
  defaultPhone: string;
  categories: Category[];
  // True if profile already has name + email + phone. When set, the wizard's
  // step 1 hides those 3 inputs (still submits them via hidden inputs) and
  // shows a compact "publishing as X" banner instead. Removes a redundant
  // data-entry burden for returning users without losing the values.
  profileComplete?: boolean;
  // Pre-populated from /procurar discovery page (or empty if reached directly).
  defaultCity?: string;
  defaultStartAt?: string;
  defaultEndAt?: string;
  defaultGuests?: number;
  defaultCuisines?: string[];
};

// Labels for these chip arrays come from `dict.vocab.*` and `dict.wizard.organizer.*`
// at render time so translations stay in lib/i18n.ts.
const EVENT_KINDS: Array<{ value: "wedding" | "birthday" | "corporate" | "festival" | "conference" | "private" | "other" }> = [
  { value: "wedding"    },
  { value: "birthday"   },
  { value: "corporate"  },
  { value: "festival"   },
  { value: "conference" },
  { value: "private"    },
  { value: "other"      },
];

const CATERING_RADIOS: Array<{ value: "food" | "drinks" | "food_and_drinks"; dictKey: "catering_food" | "catering_drinks" | "catering_both" }> = [
  { value: "food",            dictKey: "catering_food" },
  { value: "drinks",          dictKey: "catering_drinks" },
  { value: "food_and_drinks", dictKey: "catering_both" },
];

// Same 10 cuisine chips as the truck wizard (flag emoji + label from dict).
const CUISINES: { slug: "portuguesa" | "italiana" | "japonesa" | "turca" | "espanhola" | "chinesa" | "mexicana" | "tailandesa" | "marroquina" | "americana"; flag: string }[] = [
  { slug: "portuguesa", flag: "🇵🇹" },
  { slug: "italiana",   flag: "🇮🇹" },
  { slug: "japonesa",   flag: "🇯🇵" },
  { slug: "turca",      flag: "🇹🇷" },
  { slug: "espanhola",  flag: "🇪🇸" },
  { slug: "chinesa",    flag: "🇨🇳" },
  { slug: "mexicana",   flag: "🇲🇽" },
  { slug: "tailandesa", flag: "🇹🇭" },
  { slug: "marroquina", flag: "🇲🇦" },
  { slug: "americana",  flag: "🇺🇸" },
];

// Organizer uses the shorter form "Vegetariano" / "Vegetarian" (vs the longer
// "Pratos Vegetarianos" in the truck wizard) — both come from vocab.dietary.
const DIETARY: Array<{ value: "vegetarian" | "gluten_free" | "vegan"; dictKey: "vegetarian_short" | "vegan" | "gluten_free" }> = [
  { value: "vegetarian",  dictKey: "vegetarian_short" },
  { value: "vegan",       dictKey: "vegan" },
  { value: "gluten_free", dictKey: "gluten_free" },
];

const SETUP_OPTIONS: Array<{ value: number; dictKey: "h0" | "h1" | "h2" | "h3" | "h4" | "h6" | "h8" }> = [
  { value: 0,   dictKey: "h0" },
  { value: 60,  dictKey: "h1" },
  { value: 120, dictKey: "h2" },
  { value: 180, dictKey: "h3" },
  { value: 240, dictKey: "h4" },
  { value: 360, dictKey: "h6" },
  { value: 480, dictKey: "h8" },
];

const ENERGY: Array<{ value: "nao_preciso" | "ate_3kw" | "3_a_10kw" | "mais_10kw" }> = [
  { value: "nao_preciso" },
  { value: "ate_3kw"     },
  { value: "3_a_10kw"    },
  { value: "mais_10kw"   },
];

// Replaced by the WATER/WC multi-select chips below — keeping the legacy
// enum mapping is only useful for deriving sanitation_level on submit so
// existing /catalogo filters and truck-side matching keep working until
// PR 7 migrates them to the new arrays.

// Water sources the venue offers. Multi-select (a venue can have both a
// mains tap AND a backup depósito). 'agua_truck' means trucks need to
// rely on their internal tank, 'agua_indisponivel' is the explicit "no"
// signal so trucks can self-exclude without guessing.
const WATER_OPTIONS = ["agua_rede", "agua_deposito", "agua_truck", "agua_indisponivel"] as const;
type WaterOption = typeof WATER_OPTIONS[number];

// WC available on-site. Multi-select because real venues frequently
// offer both convidados WCs and a separate staff WC. 'wc_inexistente'
// is the explicit "no WC" — important: many trucks won't take a gig
// without WC access for the crew.
const WC_OPTIONS = ["wc_publicos", "wc_staff", "wc_inexistente"] as const;
type WcOption = typeof WC_OPTIONS[number];

/**
 * Derive the legacy sanitation_level enum value (nao_necessario /
 * wc_proximo / wc_dedicado) from the new multi-select WC chips so the
 * /catalogo filter and matching keep working. Heuristic mirrors the
 * old wording: dedicated staff WC > public/nearby WC > none.
 */
function deriveLegacySanitation(wc: WcOption[]): "nao_necessario" | "wc_proximo" | "wc_dedicado" {
  // wc_inexistente is the explicit "no WC" — wins over any other chip
  // because the toggle handler clears positives when the user picks it,
  // but a stale or replayed payload could still ship both. Treat it as
  // truth.
  if (wc.includes("wc_inexistente")) return "nao_necessario";
  if (wc.includes("wc_staff"))       return "wc_dedicado";
  if (wc.includes("wc_publicos"))    return "wc_proximo";
  return "nao_necessario";
}

/**
 * Toggle helper that enforces mutual exclusion between the explicit
 * "none" chip and any positive option in the same group. Picking the
 * "none" chip clears everything else; picking a positive chip clears
 * the "none" chip. Without this the wizard accepts impossible
 * combinations like ["agua_rede", "agua_indisponivel"].
 */
function toggleWithNone<T extends string>(list: T[], value: T, noneValue: T): T[] {
  const present = list.includes(value);
  if (value === noneValue) {
    // Picking the none chip: clear everything else, leaving only it
    // (or remove it if already present).
    return present ? [] : [noneValue];
  }
  // Picking a positive chip: drop the none chip if it was set, then
  // toggle the positive normally.
  const without = list.filter((v) => v !== noneValue && v !== value);
  return present ? without : [...without, value];
}

const EXTRA_SERVICES: Array<{ value: string; dictKey: "ticketing" | "security" | "photo_video" | "planning" | "entertainment" | "venue" | "cleaning" | "promotion" }> = [
  { value: "Ticketing e Gestão de Convidados", dictKey: "ticketing" },
  { value: "Segurança",                        dictKey: "security" },
  { value: "Fotografia e Vídeo",               dictKey: "photo_video" },
  { value: "Organização e Planeamento",        dictKey: "planning" },
  { value: "Animação",                         dictKey: "entertainment" },
  { value: "Encontrar uma Venue",              dictKey: "venue" },
  { value: "Limpeza e Gestão de Resíduos",     dictKey: "cleaning" },
  { value: "Promoção do Evento",               dictKey: "promotion" },
];

const SELECTION_MODES: Array<{ value: "open_to_offers" | "pick_myself" | "assisted"; labelKey: "mode_open_label" | "mode_pick_label" | "mode_assisted_label"; hintKey: "mode_open_hint" | "mode_pick_hint" | "mode_assisted_hint" }> = [
  { value: "open_to_offers", labelKey: "mode_open_label",     hintKey: "mode_open_hint" },
  { value: "pick_myself",    labelKey: "mode_pick_label",     hintKey: "mode_pick_hint" },
  { value: "assisted",       labelKey: "mode_assisted_label", hintKey: "mode_assisted_hint" },
];

export function OrganizerWizard({
  userId, defaultName, defaultEmail, defaultPhone, categories,
  profileComplete = false,
  defaultCity = "", defaultStartAt = "", defaultEndAt = "",
  defaultGuests, defaultCuisines = [],
}: Props) {
  const dict = useDict();
  const t = dict.wizard.organizer;
  const router = useRouter();
  const [step, setStep] = useState(1);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  // ---- Step 1: contact + event basics ----
  const [name, setName] = useState(defaultName);
  const [email, setEmail] = useState(defaultEmail);
  const [phone, setPhone] = useState(defaultPhone);
  const [eventTitle, setEventTitle] = useState("");
  const [address, setAddress] = useState("");
  const [locality, setLocality] = useState(defaultCity);
  const [kind, setKind] = useState("wedding");
  const [guests, setGuests] = useState(defaultGuests ?? 200);
  // Recommended truck count tracks the guest slider at ~1 truck / 150 pax
  // (mid-point of the conservative 120-200 range used in the planning copy).
  // Recompute every time `guests` changes; the field remains editable, so
  // the user can override the recommendation manually — their value sticks
  // until they touch the guest slider again.
  // Clamp to 1..10 because airfnb_event_requests.slots_needed has a
  // CHECK constraint in that range — a 1500-guest event would otherwise
  // try 10 → 11+ and the insert would 400 at submit time.
  const [trucksWanted, setTrucksWanted] = useState(() => Math.min(10, Math.max(1, Math.ceil((defaultGuests ?? 200) / 150))));
  useEffect(() => {
    setTrucksWanted(Math.min(10, Math.max(1, Math.ceil(guests / 150))));
  }, [guests]);

  // Auto-clear a stale step-1 validation error once the user has actually
  // filled in the offending fields. Without this the banner stays on screen
  // even after the user types into the empty input, which looks broken
  // (regression observed on returning users whose profile had no
  // display_name → defaultName came through empty).
  const [cateringType, setCateringType] = useState<"food" | "drinks" | "food_and_drinks">("food_and_drinks");
  const [startAt, setStartAt] = useState(defaultStartAt);
  const [endAt, setEndAt] = useState(defaultEndAt);
  const [budget, setBudget] = useState(500);
  const [budgetFlex, setBudgetFlex] = useState(false);

  // ---- Step 2: cuisine + specialties + dietary + notes ----
  const [cuisines, setCuisines] = useState<string[]>(defaultCuisines);
  const [specialtyIds, setSpecialtyIds] = useState<number[]>([]);
  const [dietary, setDietary] = useState<string[]>([]);
  const [notes, setNotes] = useState("");

  // ---- Step 3: logistics ----
  const [setupMin, setSetupMin] = useState(60);
  const [teardownMin, setTeardownMin] = useState(60);
  const [energy, setEnergy] = useState<typeof ENERGY[number]["value"]>("ate_3kw");
  const [energyHelp, setEnergyHelp] = useState(false);
  // Multi-select infrastructure chips. Water and WC are independent
  // axes; the legacy single-value sanitation_level is computed on
  // submit from `wcProvided` for back-compat with /catalogo filters.
  const [waterProvided, setWaterProvided] = useState<WaterOption[]>([]);
  const [wcProvided,    setWcProvided]    = useState<WcOption[]>([]);

  // ---- Step 4: extra services ----
  const [extras, setExtras] = useState<string[]>([]);

  // ---- Step 5: selection mode + (anon-only) account creation ----
  const [selectionMode, setSelectionMode] = useState<"open_to_offers" | "pick_myself" | "assisted">("open_to_offers");
  // Inline signup fields, only used when userId === null. The wizard's
  // existing step-1 already captures name / email; password and ToS
  // are the only extras needed to call supabase.auth.signUp() before
  // inserting the request.
  const isAnonymous = userId === null;
  const [password, setPassword]   = useState("");
  const [tosAccepted, setTos]     = useState(false);

  // Auto-clear stale step-1 banner once the step actually validates again.
  // Re-runs the same validator instead of just checking "all required
  // fields non-empty" — otherwise an `end_before_start` error would be
  // silently dismissed the moment any required text field is filled,
  // even though the bad date range is still there.
  useEffect(() => {
    if (step !== 1 || !err) return;
    if (validateStep1() === null) setErr(null);
    // validateStep1 reads from the same state slice the deps list watches.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [step, err, name, email, eventTitle, locality, startAt, endAt]);

  // Honeypot: hidden field invisible to humans but eagerly filled by naive
  // form-scraping bots. We use a ref to read the LIVE DOM value at submit
  // time — React onChange only fires when input events bubble, so a bot
  // that mutates `input.value` directly via JS would bypass a state-only
  // check. Reading the ref catches both cases.
  const honeypotRef = useRef<HTMLInputElement | null>(null);

  function toggle<T>(list: T[], value: T): T[] {
    return list.includes(value) ? list.filter((v) => v !== value) : [...list, value];
  }

  function validateStep1(): string | null {
    if (!name.trim())              return t.errors.no_name;
    if (!email.trim())             return t.errors.no_email;
    if (!eventTitle.trim())        return t.errors.no_event_title;
    if (!locality.trim())          return t.errors.no_locality;
    if (!startAt)                  return t.errors.no_start;
    if (endAt && endAt < startAt)  return t.errors.end_before_start;
    return null;
  }

  async function submitAll() {
    setBusy(true);
    setErr(null);
    try {
      // Honeypot tripwire — silently no-op (don't reveal the trap exists).
      // Read the live DOM value (not React state) so DOM-mutating bots that
      // skip the onChange path still get caught.
      const honeypotVal = honeypotRef.current?.value ?? "";
      if (honeypotVal.trim() !== "") {
        setBusy(false);
        router.push("/dashboard/organizer");
        return;
      }

      const supa = supabaseBrowser();

      // Anonymous publish: signUp first, then use the resulting user.id
      // as organizer_id for the request insert. If Supabase requires
      // email confirmation (no session returned), stash the assembled
      // form state in localStorage and bail with an actionable message
      // — the next /publicar visit with a confirmed session will
      // restore the draft and let them publish in one click (rehydrate
      // logic ships separately; for now the user re-fills from the
      // draft on a future visit).
      let effectiveUserId: string = userId ?? "";
      if (isAnonymous) {
        if ((password ?? "").length < 8) {
          throw new Error((t.errors as Record<string, string>).short_password ?? "Password com pelo menos 8 caracteres.");
        }
        if (!tosAccepted) {
          throw new Error((t.errors as Record<string, string>).tos_required ?? "Aceita os Termos para publicar.");
        }
        const { data: signUpData, error: signUpErr } = await supa.auth.signUp({
          email: email.trim(),
          password,
          options: {
            data: { full_name: name.trim(), locale: "pt-PT" },
            emailRedirectTo: `${window.location.origin}/auth/callback?next=${encodeURIComponent("/publicar?draft=1")}&as=organizer`,
          },
        });
        if (signUpErr) throw new Error(signUpErr.message);
        if (!signUpData.user) throw new Error("signup failed");
        if (!signUpData.session) {
          // Email confirmation pending — persist a draft of the
          // wizard's state so a future return visit (after confirming)
          // can rehydrate the form. We use localStorage rather than
          // round-tripping the whole payload through a token because
          // the draft is large and only useful in the same browser.
          try {
            localStorage.setItem("airfnb-publish-draft", JSON.stringify({
              ts: Date.now(),
              email: email.trim(),
              draft: {
                name, phone, eventTitle, address, locality, kind, guests, trucksWanted,
                cateringType, startAt, endAt, budget, budgetFlex, cuisines, specialtyIds,
                dietary, notes, setupMin, teardownMin, energy, energyHelp,
                waterProvided, wcProvided, extras, selectionMode,
              },
            }));
          } catch { /* private mode / storage full — silently ignore */ }
          setBusy(false);
          setErr((t.errors as Record<string, string>).confirm_email ?? "Conta criada. Confirma o teu email e volta a publicar — os teus dados ficaram guardados.");
          return;
        }
        effectiveUserId = signUpData.user.id;
        // Best-effort profile patch so the wizard's contact_phone /
        // role lands on the new profile row. The profile is auto-
        // created by an auth trigger; this fills in fields beyond
        // what user_metadata covers.
        await (supa as any).from("airfnb_profiles").update({
          full_name: name.trim(),
          phone: phone.trim() || null,
          role: "organizer",
        }).eq("id", signUpData.user.id);
      }

      // Rate limit (10 pedidos/organizer/day) is enforced by a BEFORE INSERT
      // trigger on airfnb_event_requests. We don't precheck here because the
      // precheck calls the SAME mutating RPC and would double-charge the
      // bucket (halving the effective cap to 5). The trigger raises a
      // Portuguese exception we surface to the user via the catch path.

      // selection_mode → discovery_mode mapping for the marketplace match logic
      const discovery =
        selectionMode === "pick_myself" ? "curated" :
        "broadcast"; // open_to_offers + assisted both go broadcast; assisted just flags assistance_requested
      const { data, error } = await (supa as any).from("airfnb_event_requests").insert({
        organizer_id:          effectiveUserId,
        title:                 eventTitle.trim(),
        kind,
        contact_name:          name.trim(),
        contact_email:         email.trim(),
        contact_phone:         phone.trim() || null,
        address_line:          address.trim() || null,
        locality:              locality.trim(),
        city:                  locality.trim(),
        start_at:              new Date(startAt).toISOString(),
        end_at:                endAt ? new Date(endAt).toISOString() : null,
        expected_pax:          guests,
        slots_needed:          trucksWanted,
        budget_estimate:       budget,
        budget_flexible:       budgetFlex,
        budget_min:            budgetFlex ? null : Math.round(budget * 0.8),
        budget_max:            budgetFlex ? null : Math.round(budget * 1.2),
        catering_type:         cateringType,
        desired_cuisines:      cuisines,
        desired_categories:    specialtyIds,
        dietary_requirements:  dietary,
        setup_minutes:         setupMin,
        teardown_minutes:      teardownMin,
        energy_need:           energy,
        energy_assistance:     energyHelp,
        sanitation_level:      deriveLegacySanitation(wcProvided),
        water_provided:        waterProvided,
        wc_provided:           wcProvided,
        extra_services:        extras,
        selection_mode:        selectionMode,
        assistance_requested:  selectionMode === "assisted",
        discovery_mode:        discovery,
        accepted_deal_types:   ["fixed", "percent", "mixed"],
        notes:                 notes.trim() || null,
        status:                "open",
        visibility:            "public",
        applications_deadline: subtractDaysISO(startAt, 3),
      }).select("id").single();
      if (error) throw new Error(error.message);
      // pick_myself organizers land on the dedicated invite picker so
      // they can shortlist trucks immediately — the detail page would
      // otherwise show an empty "0 applications" state and look broken
      // for a request that's curated-only by design.
      if (selectionMode === "pick_myself") {
        router.push(`/dashboard/organizer/pedidos/${data.id}/convidar`);
      } else {
        router.push(`/dashboard/organizer/pedidos/${data.id}`);
      }
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function next() {
    setErr(null);
    if (step === 1) {
      const v = validateStep1();
      if (v) { setErr(v); return; }
      setStep(2);
      return;
    }
    if (step < 5) { setStep(step + 1); return; }
    await submitAll();
  }

  return (
    <div className="wizard-shell" style={{ background: "#fff", border: "1px solid var(--line)", borderRadius: 16, padding: 26 }}>
      {/* Honeypot — visually hidden + aria-hidden so humans never see or
          tab into it; bots that auto-fill every input trip the no-op path.
          Uncontrolled (ref-only) so DOM-mutating bots can't bypass via
          direct value assignment without firing change events. */}
      <input
        ref={honeypotRef}
        type="text"
        name="website"
        tabIndex={-1}
        autoComplete="off"
        aria-hidden="true"
        defaultValue=""
        style={{ position: "absolute", left: "-9999px", width: 1, height: 1, opacity: 0 }}
      />
      <DotStepper step={step} total={5} />
      {err && <div style={{ background: "var(--error-bg)", color: "var(--error-text)", border: "1px solid var(--error-line)", padding: "10px 14px", borderRadius: "var(--radius-sm)", margin: "0 0 16px", fontSize: 14 }}>{err}</div>}

      {step === 1 && (
        <div style={{ display: "grid", gap: 14 }}>
          {profileComplete ? (
            // Returning user — show a compact "publishing as" banner and ride
            // the contact values through as hidden inputs so the submit
            // payload stays identical (server-side reads them from state,
            // not the DOM, but the banner makes the values visible to the
            // user without re-typing).
            <div
              style={{
                display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12,
                padding: "12px 14px",
                background: "var(--soft-bg, #F6F7F9)",
                border: "1px solid var(--line)",
                borderRadius: 10,
                fontSize: 14,
              }}
            >
              <div>
                <div style={{ color: "var(--muted)", fontSize: 12, fontWeight: 600, textTransform: "uppercase", letterSpacing: 0.3 }}>
                  {t.step1.publishing_as ?? "A publicar como"}
                </div>
                <div style={{ marginTop: 2 }}>
                  <strong>{name}</strong> · {email}
                </div>
              </div>
              <a
                href="/dashboard/perfil"
                target="_blank"
                rel="noopener noreferrer"
                style={{ color: "var(--orange)", textDecoration: "underline", fontSize: 13 }}
              >
                {t.step1.publishing_as_edit ?? "Alterar perfil"}
              </a>
            </div>
          ) : (
            <>
              <Field label={t.step1.name_label}>
                <input value={name} onChange={(e) => setName(e.target.value)} placeholder={t.step1.name_placeholder} />
              </Field>
              <Field label={t.step1.email_label}>
                <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder={t.step1.email_placeholder} />
              </Field>
              <Field label={t.step1.phone_label}>
                <input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder={t.step1.phone_placeholder} />
              </Field>
            </>
          )}
          <Field label={t.step1.event_title_label}>
            <input value={eventTitle} onChange={(e) => setEventTitle(e.target.value)} maxLength={120} placeholder={t.step1.event_title_placeholder} />
          </Field>
          <Field label={t.step1.address_label}>
            <input value={address} onChange={(e) => setAddress(e.target.value)} placeholder={t.step1.address_placeholder} />
          </Field>
          <Field label={t.step1.locality_label}>
            <CityAutocomplete
              defaultValue={locality}
              placeholder={t.step1.locality_placeholder}
              onChange={(v) => setLocality(v)}
            />
          </Field>
          <Field label={t.step1.kind_label}>
            <select value={kind} onChange={(e) => setKind(e.target.value)}>
              {EVENT_KINDS.map((k) => <option key={k.value} value={k.value}>{dict.vocab.event_kinds[k.value]}</option>)}
            </select>
          </Field>
          <Field label={format(t.step1.guests_label, { n: guests })}>
            <input type="range" min={20} max={5000} step={10} value={guests} onChange={(e) => setGuests(Number(e.target.value))} />
          </Field>
          <Field label={t.step1.trucks_label}>
            <input type="number" min={1} max={10}
              value={trucksWanted}
              onChange={(e) => {
                // Clamp client-side so the user can't type 11+ and hit the
                // airfnb_event_requests.slots_needed check constraint (1..10).
                const v = Math.min(10, Math.max(1, Number(e.target.value) || 1));
                setTrucksWanted(v);
              }} />
            <small style={{ color: "var(--muted)", fontSize: 12 }}>
              {t.step1.trucks_hint}
            </small>
          </Field>
          <div>
            <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 6 }}>{t.step1.catering_label}</div>
            <div style={{ display: "flex", gap: 18, flexWrap: "wrap" }}>
              {CATERING_RADIOS.map((c) => (
                <label key={c.value} style={{ display: "inline-flex", alignItems: "center", gap: 6, cursor: "pointer", fontSize: 14 }}>
                  <input
                    type="radio"
                    name="catering_type"
                    value={c.value}
                    checked={cateringType === c.value}
                    onChange={() => setCateringType(c.value)}
                  />
                  {t.step1[c.dictKey]}
                </label>
              ))}
            </div>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
            <Field label={t.step1.start_label}>
              <input type="date" value={startAt} onChange={(e) => setStartAt(e.target.value)} />
            </Field>
            <Field label={t.step1.end_label}>
              <input type="date" value={endAt} onChange={(e) => setEndAt(e.target.value)} />
            </Field>
          </div>
          <Field label={format(t.step1.budget_label, { budget })}>
            <input type="range" min={100} max={20000} step={50} value={budget} onChange={(e) => setBudget(Number(e.target.value))} />
          </Field>
          <label style={{ display: "inline-flex", alignItems: "center", gap: 6, cursor: "pointer", fontSize: 14 }}>
            <input type="checkbox" checked={budgetFlex} onChange={(e) => setBudgetFlex(e.target.checked)} />
            {t.step1.budget_flex}
          </label>
        </div>
      )}

      {step === 2 && (
        <div style={{ display: "grid", gap: 20 }}>
          <section>
            <SectionTitle>{t.step2.cuisines_title}</SectionTitle>
            <div className="chips">
              {CUISINES.map((c) => (
                <button type="button" key={c.slug} className="chip"
                  data-active={cuisines.includes(c.slug)}
                  onClick={() => setCuisines((s) => toggle(s, c.slug))}>
                  <span style={{ fontSize: 16 }}>{c.flag}</span> {dict.vocab.cuisines[c.slug]}
                </button>
              ))}
            </div>
          </section>
          <section>
            <SectionTitle>{t.step2.specialties_title}</SectionTitle>
            <div className="chips">
              {categories.map((c) => (
                <button type="button" key={c.id} className="chip"
                  data-active={specialtyIds.includes(c.id)}
                  onClick={() => setSpecialtyIds((s) => toggle(s, c.id))}>
                  <span className="material-symbols-outlined" style={{ fontSize: 16 }}>{c.icon ?? "restaurant"}</span>
                  {c.name_pt}
                </button>
              ))}
            </div>
          </section>
          <section>
            <SectionTitle>{t.step2.dietary_title}</SectionTitle>
            <div className="chips">
              {DIETARY.map((d) => (
                <button type="button" key={d.value} className="chip"
                  data-active={dietary.includes(d.value)}
                  onClick={() => setDietary((s) => toggle(s, d.value))}>
                  {dict.vocab.dietary[d.dictKey]}
                </button>
              ))}
            </div>
          </section>
          <Field label={t.step2.notes_label}>
            <textarea
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder={t.step2.notes_placeholder}
              style={{ minHeight: 140, resize: "vertical" }}
            />
          </Field>
        </div>
      )}

      {step === 3 && (
        <div style={{ display: "grid", gap: 18 }}>
          <section>
            <SectionTitle>{t.step3.setup_section_title}</SectionTitle>
            <p style={{ color: "var(--muted)", margin: "0 0 12px", fontSize: 13 }}>
              {t.step3.setup_intro}
            </p>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
              <Field label={t.step3.setup_label}>
                <select value={setupMin} onChange={(e) => setSetupMin(Number(e.target.value))}>
                  {SETUP_OPTIONS.map((o) => <option key={o.value} value={o.value}>{dict.vocab.setup_hours[o.dictKey]}</option>)}
                </select>
              </Field>
              <Field label={t.step3.teardown_label}>
                <select value={teardownMin} onChange={(e) => setTeardownMin(Number(e.target.value))}>
                  {SETUP_OPTIONS.map((o) => <option key={o.value} value={o.value}>{dict.vocab.setup_hours[o.dictKey]}</option>)}
                </select>
              </Field>
            </div>
          </section>
          <section>
            <SectionTitle>{t.step3.energy_section_title}</SectionTitle>
            <p style={{ color: "var(--muted)", margin: "0 0 8px", fontSize: 13 }}>
              {t.step3.energy_intro}
            </p>
            <select value={energy} onChange={(e) => setEnergy(e.target.value as typeof ENERGY[number]["value"])}>
              {ENERGY.map((o) => <option key={o.value} value={o.value}>{dict.vocab.power[o.value]}</option>)}
            </select>
            <label style={{ display: "inline-flex", alignItems: "center", gap: 6, marginTop: 10, fontSize: 14, cursor: "pointer" }}>
              <input type="checkbox" checked={energyHelp} onChange={(e) => setEnergyHelp(e.target.checked)} />
              {t.step3.energy_help}
            </label>
          </section>
          <section>
            <SectionTitle>{(t.step3 as any).infrastructure_section_title ?? t.step3.sanitation_section_title}</SectionTitle>
            <p style={{ color: "var(--muted)", margin: "0 0 12px", fontSize: 13 }}>
              {(t.step3 as any).infrastructure_intro ?? t.step3.sanitation_intro}
            </p>

            <div style={{ fontSize: 13, fontWeight: 600, marginTop: 4, marginBottom: 6 }}>
              {(t.step3 as any).water_label ?? "Água disponível"}
            </div>
            <div className="chips" style={{ marginBottom: 14 }}>
              {WATER_OPTIONS.map((opt) => (
                <button type="button" key={opt} className="chip"
                  data-active={waterProvided.includes(opt)}
                  onClick={() => setWaterProvided((s) => toggleWithNone(s, opt, "agua_indisponivel"))}>
                  {((dict.vocab as any).water_provided ?? {})[opt] ?? opt}
                </button>
              ))}
            </div>

            <div style={{ fontSize: 13, fontWeight: 600, marginTop: 4, marginBottom: 6 }}>
              {(t.step3 as any).wc_label ?? "WC disponível"}
            </div>
            <div className="chips">
              {WC_OPTIONS.map((opt) => (
                <button type="button" key={opt} className="chip"
                  data-active={wcProvided.includes(opt)}
                  onClick={() => setWcProvided((s) => toggleWithNone(s, opt, "wc_inexistente"))}>
                  {((dict.vocab as any).wc_provided ?? {})[opt] ?? opt}
                </button>
              ))}
            </div>
          </section>
        </div>
      )}

      {step === 4 && (
        <div>
          <SectionTitle>{t.step4.title}</SectionTitle>
          <p style={{ color: "var(--muted)", margin: "0 0 14px", fontSize: 13 }}>
            {t.step4.intro}
          </p>
          <div className="chips">
            {EXTRA_SERVICES.map((s) => (
              <button type="button" key={s.value} className="chip"
                data-active={extras.includes(s.value)}
                onClick={() => setExtras((list) => toggle(list, s.value))}>
                {dict.vocab.extra_services[s.dictKey]}
              </button>
            ))}
          </div>
        </div>
      )}

      {step === 5 && (
        <div>
          <h2 style={{ textAlign: "center", margin: "8px 0 6px", fontFamily: "Bebas Neue, sans-serif", color: "var(--ink)", fontSize: 26 }}>
            {t.title_select_mode}
          </h2>
          <p style={{ textAlign: "center", color: "var(--muted)", margin: "0 0 20px", fontSize: 14 }}>
            {t.subtitle_select_mode}
          </p>
          <div style={{ display: "grid", gap: 12, maxWidth: 520, margin: "0 auto" }}>
            {SELECTION_MODES.map((m) => (
              <button
                type="button"
                key={m.value}
                onClick={() => setSelectionMode(m.value)}
                style={{
                  textAlign: "left", padding: "14px 18px",
                  border: `2px solid ${selectionMode === m.value ? "var(--orange)" : "var(--line)"}`,
                  background: selectionMode === m.value ? "#FFF6F2" : "#fff",
                  borderRadius: 999, cursor: "pointer", fontFamily: "inherit",
                }}
              >
                <div style={{ fontWeight: 700, color: "var(--ink)" }}>{t.step5[m.labelKey]}</div>
                <div style={{ fontSize: 12, color: "var(--muted)", marginTop: 2 }}>{t.step5[m.hintKey]}</div>
              </button>
            ))}
          </div>

          {isAnonymous && (
            <div style={{
              marginTop: 28, padding: 18,
              background: "linear-gradient(180deg, #FFF6F2 0%, #FFFFFF 100%)",
              border: "1px solid var(--orange)", borderRadius: 14,
            }}>
              <div style={{ fontWeight: 700, marginBottom: 6 }}>
                {(t as any).anon_signup_title ?? "Cria conta para publicar"}
              </div>
              <div style={{ color: "var(--muted)", fontSize: 13, marginBottom: 12 }}>
                {(t as any).anon_signup_hint ?? "Vamos criar uma conta com o teu email para acompanhares as candidaturas dos trucks."}
              </div>
              <Field label={(t as any).anon_password_label ?? "Password (mín. 8 caracteres)"}>
                <input
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  autoComplete="new-password"
                  minLength={8}
                />
              </Field>
              <label style={{ display: "flex", alignItems: "flex-start", gap: 8, marginTop: 10, fontSize: 14, cursor: "pointer" }}>
                <input
                  type="checkbox"
                  checked={tosAccepted}
                  onChange={(e) => setTos(e.target.checked)}
                  style={{ marginTop: 2 }}
                />
                <span>
                  {(t as any).anon_tos_prefix ?? "Aceito os "}
                  <a href="/termos" target="_blank" rel="noopener noreferrer" style={{ color: "var(--orange)", textDecoration: "underline" }}>
                    {(t as any).anon_tos_link ?? "Termos"}
                  </a>
                  {(t as any).anon_tos_middle ?? " e a "}
                  <a href="/privacidade" target="_blank" rel="noopener noreferrer" style={{ color: "var(--orange)", textDecoration: "underline" }}>
                    {(t as any).anon_privacy_link ?? "Política de Privacidade"}
                  </a>
                  .
                </span>
              </label>
            </div>
          )}
        </div>
      )}

      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginTop: 26, gap: 10, flexWrap: "wrap" }}>
        <button
          type="button"
          className="btn-pill outline"
          style={{ borderColor: "var(--line)", color: "var(--muted)" }}
          onClick={() => setStep((s) => Math.max(1, s - 1))}
          disabled={step === 1 || busy}
        >
          {dict.common.previous}
        </button>
        <button type="button" className="btn-pill" onClick={next} disabled={busy}>
          {busy ? t.submitting : step < 5 ? dict.common.next : t.finish}
        </button>
      </div>
    </div>
  );
}

function DotStepper({ step, total }: { step: number; total: number }) {
  return (
    <div style={{ display: "flex", gap: 8, justifyContent: "center", margin: "0 0 22px" }}>
      {Array.from({ length: total }).map((_, i) => (
        <span
          key={i}
          aria-hidden="true"
          style={{
            width: 10, height: 10, borderRadius: "50%",
            background: i < step ? "var(--orange)" : "#E5E5E5",
            transition: "background 0.2s",
          }}
        />
      ))}
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label style={{ display: "grid", gap: 6 }}>
      <span style={{ fontSize: 13, fontWeight: 600, color: "var(--ink)" }}>{label}</span>
      {children}
    </label>
  );
}

function SectionTitle({ children }: { children: React.ReactNode }) {
  return <h3 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--ink)", margin: "0 0 10px", fontSize: 22 }}>{children}</h3>;
}

function subtractDaysISO(date: string, days: number) {
  const d = new Date(date);
  d.setDate(d.getDate() - days);
  return d.toISOString();
}
