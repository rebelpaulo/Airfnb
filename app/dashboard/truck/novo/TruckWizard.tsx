"use client";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { TruckPhotoUpload } from "@/components/TruckPhotoUpload";
import { TruckPdfUpload } from "@/components/TruckPdfUpload";
import { CityAutocomplete } from "@/components/CityAutocomplete";
import { useDict } from "@/components/DictProvider";

type Category = { id: number; slug: string; name_pt: string; icon: string | null };
type Props = { userId: string; categories: Category[] };
type ServiceType = "food_truck" | "catering" | "bar";

// --- Chip vocabularies that mirror the original /addTruck wizard. -----------
// Cuisine types: country-flag chips. Stored as free-text in trucks.cuisine_types
// because the original site lets owners type their own. The presets are the
// 10 the original ships with; "outros" lets owners add custom values.
// Labels are read from `dict.vocab.cuisines[slug]` at render time so the
// translations stay in lib/i18n.ts.
const CUISINES: { slug: keyof ReturnType<typeof useDict>["vocab"]["cuisines"]; flag: string }[] = [
  { slug: "portuguesa",  flag: "🇵🇹" },
  { slug: "italiana",    flag: "🇮🇹" },
  { slug: "japonesa",    flag: "🇯🇵" },
  { slug: "turca",       flag: "🇹🇷" },
  { slug: "espanhola",   flag: "🇪🇸" },
  { slug: "chinesa",     flag: "🇨🇳" },
  { slug: "mexicana",    flag: "🇲🇽" },
  { slug: "tailandesa",  flag: "🇹🇭" },
  { slug: "marroquina",  flag: "🇲🇦" },
  { slug: "americana",   flag: "🇺🇸" },
];

const DIETARY: { value: "vegetarian" | "gluten_free" | "vegan"; dictKey: "vegetarian" | "gluten_free" | "vegan"; icon: string }[] = [
  { value: "vegetarian",  dictKey: "vegetarian",  icon: "spa" },
  { value: "gluten_free", dictKey: "gluten_free", icon: "no_meals" },
  { value: "vegan",       dictKey: "vegan",       icon: "eco" },
];

const CATERING_TYPES: { value: "fixed" | "percent" | "mixed" }[] = [
  { value: "fixed" },
  { value: "percent" },
  { value: "mixed" },
];

const SERVICE_TYPES: { value: ServiceType }[] = [
  { value: "food_truck" },
  { value: "catering" },
  { value: "bar" },
];

const SANITATION: { value: string; dictKey: "none" | "wc_proximo" | "wc_dedicado" }[] = [
  { value: "none",        dictKey: "none" },
  { value: "wc_proximo",  dictKey: "wc_proximo" },
  { value: "wc_dedicado", dictKey: "wc_dedicado" },
];

const POWER_OPTIONS = ["nao_preciso", "ate_3kw", "3_a_10kw", "mais_10kw"] as const;
const POWER_KW: Record<typeof POWER_OPTIONS[number], number | null> = {
  nao_preciso:   0,
  ate_3kw:       3,
  "3_a_10kw":    10,
  mais_10kw:     15,
};

const SETUP_OPTIONS = [30, 45, 60, 90, 120, 180];

export function TruckWizard({ userId, categories }: Props) {
  const dict = useDict();
  const t = dict.wizard.truck;
  const router = useRouter();
  const [step, setStep] = useState(1);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [truckId, setTruckId] = useState<string | null>(null);

  // step 1
  const [name, setName] = useState("");
  const [baseCity, setBaseCity] = useState("");
  const [radius, setRadius] = useState(50);
  const [capacity, setCapacity] = useState(100);
  const [minPax, setMinPax] = useState(30);
  const [maxPax, setMaxPax] = useState(500);
  const [priceMin, setPriceMin] = useState<number | "">("");
  const [priceMax, setPriceMax] = useState<number | "">("");
  const [serviceType, setServiceType] = useState<ServiceType | "">("");
  const [cateringType, setCateringType] = useState<string>("fixed");

  // step 2
  const [cuisines, setCuisines] = useState<string[]>([]);
  const [cuisineOther, setCuisineOther] = useState("");
  const [categoryIds, setCategoryIds] = useState<number[]>([]);
  const [dietary, setDietary] = useState<string[]>([]);
  // Which event kinds this truck declares itself a fit for. Used by the
  // /catalogo?event_kind= deep links from the landing's themed cards.
  const [eventKinds, setEventKinds] = useState<string[]>([]);

  // step 3
  const [setupMin, setSetupMin] = useState(60);
  const [teardownMin, setTeardownMin] = useState(60);
  const [power, setPower] = useState<typeof POWER_OPTIONS[number]>("ate_3kw");
  const [sanitation, setSanitation] = useState("none");

  function toggle<T>(list: T[], value: T): T[] {
    return list.includes(value) ? list.filter((v) => v !== value) : [...list, value];
  }

  async function saveStep1AndAdvance() {
    setErr(null);
    if (!serviceType)     { setErr(t.errors.no_service_type); return; }
    if (!name.trim())     { setErr(t.errors.no_name); return; }
    if (!baseCity.trim()) { setErr(t.errors.no_city); return; }
    setBusy(true);
    try {
      const supa = supabaseBrowser();
      // Role is a security-sensitive field. Claim it through the guarded RPC
      // so the browser never receives direct write authority over profile roles.
      // The RPC is idempotent for an existing owner and rejects role changes,
      // privileged roles, and identities blocked by an F&B deletion tombstone.
      const { error: claimError } = await (supa as any).rpc("airfnb_claim_role", {
        p_role: "owner",
      });
      if (claimError) throw new Error(claimError.message);

      if (truckId) {
        // editing an in-progress draft
        const { error } = await (supa as any).from("airfnb_trucks")
          .update({
            name: name.trim(),
            base_city: baseCity.trim(),
            service_radius_km: radius,
            capacity,
            min_event_pax: minPax,
            max_event_pax: maxPax,
            base_price: priceMin === "" ? null : priceMin,
            price_per_pax: priceMax === "" ? null : priceMax,
            service_type: serviceType,
            catering_type: cateringType,
          })
          .eq("id", truckId);
        if (error) throw new Error(error.message);
      } else {
        const slug = slugify(name);
        const { data, error } = await (supa as any).from("airfnb_trucks").insert({
          owner_id:           userId,
          slug,
          name:               name.trim(),
          base_city:          baseCity.trim(),
          service_radius_km:  radius,
          capacity,
          min_event_pax:      minPax,
          max_event_pax:      maxPax,
          base_price:         priceMin === "" ? null : priceMin,
          price_per_pax:      priceMax === "" ? null : priceMax,
          service_type:       serviceType,
          catering_type:      cateringType,
          status:             "draft",
        }).select("id").single();
        if (error) throw new Error(error.message);
        setTruckId(data.id);
      }
      setStep(2);
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function saveStep2AndAdvance() {
    if (!truckId) { setErr(t.errors.invalid_state); return; }
    setBusy(true);
    setErr(null);
    try {
      const supa = supabaseBrowser();
      const cuisinesFinal = cuisineOther.trim()
        ? Array.from(new Set([...cuisines, cuisineOther.trim().toLowerCase()]))
        : cuisines;
      const { error } = await (supa as any).from("airfnb_trucks").update({
        cuisine_types:         cuisinesFinal,
        dietary_options:       dietary,
        compatible_event_kinds: eventKinds,
      }).eq("id", truckId);
      if (error) throw new Error(error.message);

      // categories: wipe + reinsert (small set, simple to reason about).
      // If either side fails we abort — leaving step 2 advanced with stale
      // categories would be confusing and silently lose the owner's input.
      const delRes = await (supa as any).from("airfnb_truck_categories").delete().eq("truck_id", truckId);
      if (delRes.error) throw new Error(delRes.error.message);
      if (categoryIds.length) {
        const insRes = await (supa as any).from("airfnb_truck_categories").insert(
          categoryIds.map((cid) => ({ truck_id: truckId, category_id: cid })),
        );
        if (insRes.error) throw new Error(insRes.error.message);
      }
      setStep(3);
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function saveStep3AndAdvance() {
    if (!truckId) { setErr(t.errors.invalid_state); return; }
    setBusy(true);
    setErr(null);
    try {
      const supa = supabaseBrowser();
      const { error } = await (supa as any).from("airfnb_trucks").update({
        setup_minutes:        setupMin,
        teardown_minutes:     teardownMin,
        power_required_kw:    POWER_KW[power],
        sanitation_required:  sanitation,
      }).eq("id", truckId);
      if (error) throw new Error(error.message);
      setStep(4);
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  function finish() {
    if (!truckId) return;
    router.push(`/dashboard/truck/${truckId}`);
  }

  return (
    <div className="wizard-shell" style={{ background: "#fff", border: "1px solid var(--line)", borderRadius: 16, padding: 26 }}>
      <Stepper step={step} labels={[t.stepper_basics, t.stepper_cuisine, t.stepper_logistics, t.stepper_media]} />
      {err && <div style={{ background: "var(--error-bg)", color: "var(--error-text)", border: "1px solid var(--error-line)", padding: "10px 14px", borderRadius: "var(--radius-sm)", margin: "0 0 16px", fontSize: 14 }}>{err}</div>}

      {step === 1 && (
        <div style={{ display: "grid", gap: 14 }}>
          <Field label={t.step1.service_type_label}>
            <div>
              <div className="chips">
                {SERVICE_TYPES.map((service) => (
                  <button
                    type="button"
                    key={service.value}
                    className="chip"
                    data-active={serviceType === service.value}
                    aria-pressed={serviceType === service.value}
                    onClick={() => setServiceType(service.value)}
                  >
                    {dict.vocab.service_type[service.value]}
                  </button>
                ))}
              </div>
              <p style={{ color: "var(--muted)", fontSize: 12, margin: "7px 0 0" }}>
                {t.step1.service_type_hint}
              </p>
            </div>
          </Field>
          <Field label={t.step1.name_label}>
            <input value={name} onChange={(e) => setName(e.target.value)} maxLength={120} placeholder={t.step1.name_placeholder} />
          </Field>
          <div style={{ display: "grid", gridTemplateColumns: "2fr 1fr", gap: 14 }}>
            <Field label={t.step1.city_label}>
              <CityAutocomplete
                defaultValue={baseCity}
                placeholder={t.step1.city_placeholder}
                onChange={(v) => setBaseCity(v)}
              />
            </Field>
            <Field label={t.step1.radius_label}>
              <input type="number" min={5} max={500} value={radius} onChange={(e) => setRadius(Number(e.target.value))} />
            </Field>
          </div>
          <Field label={t.step1.capacity_label}>
            <input type="number" min={10} value={capacity} onChange={(e) => setCapacity(Number(e.target.value))} />
          </Field>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
            <Field label={t.step1.min_pax_label}>
              <input type="number" min={1} value={minPax} onChange={(e) => setMinPax(Number(e.target.value))} />
            </Field>
            <Field label={t.step1.max_pax_label}>
              <input type="number" min={1} value={maxPax} onChange={(e) => setMaxPax(Number(e.target.value))} />
            </Field>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
            <Field label={t.step1.price_min_label}>
              <input type="number" min={0} step={10} value={priceMin} onChange={(e) => setPriceMin(e.target.value === "" ? "" : Number(e.target.value))} placeholder="600" />
            </Field>
            <Field label={t.step1.price_per_pax_label}>
              <input type="number" min={0} step={0.5} value={priceMax} onChange={(e) => setPriceMax(e.target.value === "" ? "" : Number(e.target.value))} placeholder="12" />
            </Field>
          </div>
          <Field label={t.step1.catering_type_label}>
            <div className="chips">
              {CATERING_TYPES.map((c) => (
                <button
                  type="button"
                  key={c.value}
                  className="chip"
                  data-active={cateringType === c.value}
                  onClick={() => setCateringType(c.value)}
                >
                  {dict.vocab.catering_type[c.value]}
                </button>
              ))}
            </div>
          </Field>
        </div>
      )}

      {step === 2 && (
        <div style={{ display: "grid", gap: 20 }}>
          <section>
            <SectionTitle>{t.step2.cuisines_title}</SectionTitle>
            <div className="chips">
              {CUISINES.map((c) => (
                <button
                  type="button"
                  key={c.slug}
                  className="chip"
                  data-active={cuisines.includes(c.slug)}
                  onClick={() => setCuisines((s) => toggle(s, c.slug))}
                >
                  <span style={{ fontSize: 16 }}>{c.flag}</span> {dict.vocab.cuisines[c.slug]}
                </button>
              ))}
            </div>
            <div style={{ marginTop: 10 }}>
              <input
                value={cuisineOther}
                onChange={(e) => setCuisineOther(e.target.value)}
                placeholder={t.step2.cuisine_other_placeholder}
                style={{ width: "100%", maxWidth: 360 }}
              />
            </div>
          </section>

          <section>
            <SectionTitle>{t.step2.specialties_title}</SectionTitle>
            <div className="chips">
              {categories.map((c) => (
                <button
                  type="button"
                  key={c.id}
                  className="chip"
                  data-active={categoryIds.includes(c.id)}
                  onClick={() => setCategoryIds((s) => toggle(s, c.id))}
                >
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
                <button
                  type="button"
                  key={d.value}
                  className="chip"
                  data-active={dietary.includes(d.value)}
                  onClick={() => setDietary((s) => toggle(s, d.value))}
                >
                  <span className="material-symbols-outlined" style={{ fontSize: 16 }}>{d.icon}</span>
                  {dict.vocab.dietary[d.dictKey]}
                </button>
              ))}
            </div>
          </section>

          <section>
            <SectionTitle>{t.step2.event_kinds_title}</SectionTitle>
            <p style={{ color: "var(--muted)", fontSize: 13, margin: "0 0 10px" }}>
              {t.step2.event_kinds_hint}
            </p>
            <div className="chips">
              {(["wedding","birthday","corporate","festival","conference","private","other"] as const).map((k) => (
                <button
                  type="button"
                  key={k}
                  className="chip"
                  data-active={eventKinds.includes(k)}
                  onClick={() => setEventKinds((s) => toggle(s, k))}
                >
                  {(dict.vocab.event_kinds as Record<string, string>)[k] ?? k}
                </button>
              ))}
            </div>
          </section>
        </div>
      )}

      {step === 3 && (
        <div style={{ display: "grid", gap: 14 }}>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
            <Field label={t.step3.setup_label}>
              <select value={setupMin} onChange={(e) => setSetupMin(Number(e.target.value))}>
                {SETUP_OPTIONS.map((m) => <option key={m} value={m}>{m} {t.step3.minutes_suffix}</option>)}
              </select>
            </Field>
            <Field label={t.step3.teardown_label}>
              <select value={teardownMin} onChange={(e) => setTeardownMin(Number(e.target.value))}>
                {SETUP_OPTIONS.map((m) => <option key={m} value={m}>{m} {t.step3.minutes_suffix}</option>)}
              </select>
            </Field>
          </div>
          <Field label={t.step3.power_label}>
            <select value={power} onChange={(e) => setPower(e.target.value as typeof POWER_OPTIONS[number])}>
              {POWER_OPTIONS.map((p) => <option key={p} value={p}>{dict.vocab.power[p]}</option>)}
            </select>
          </Field>
          <Field label={t.step3.sanitation_label}>
            <select value={sanitation} onChange={(e) => setSanitation(e.target.value)}>
              {SANITATION.map((s) => <option key={s.value} value={s.value}>{dict.vocab.sanitation[s.dictKey]}</option>)}
            </select>
          </Field>
        </div>
      )}

      {step === 4 && truckId && (
        <div style={{ display: "grid", gap: 20 }}>
          <section>
            <SectionTitle>{t.step4.photos_title}</SectionTitle>
            <TruckPhotoUpload truckId={truckId} />
          </section>
          <section>
            <SectionTitle>{t.step4.docs_title}</SectionTitle>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(260px, 1fr))", gap: 12 }}>
              <TruckPdfUpload truckId={truckId} kind="asae"      label={t.step4.doc_asae} />
              <TruckPdfUpload truckId={truckId} kind="comercial" label={t.step4.doc_comercial} />
              <TruckPdfUpload truckId={truckId} kind="financas"  label={t.step4.doc_financas} />
              <TruckPdfUpload truckId={truckId} kind="outros"    label={t.step4.doc_outros} />
            </div>
          </section>
        </div>
      )}

      {/* ----- footer ----- */}
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
        {step < 4 ? (
          <button
            type="button"
            className="btn-pill"
            onClick={step === 1 ? saveStep1AndAdvance : step === 2 ? saveStep2AndAdvance : saveStep3AndAdvance}
            disabled={busy}
          >
            {busy ? dict.common.saving : dict.common.next}
          </button>
        ) : (
          <button type="button" className="btn-pill" onClick={finish}>
            {t.finish}
          </button>
        )}
      </div>
    </div>
  );
}

function Stepper({ step, labels }: { step: number; labels: string[] }) {
  return (
    <ol style={{ display: "flex", gap: 12, padding: 0, margin: "0 0 22px", listStyle: "none", flexWrap: "wrap" }}>
      {labels.map((label, i) => {
        const n = i + 1;
        const done = n < step;
        const active = n === step;
        return (
          <li key={label} style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <span style={{
              width: 28, height: 28, borderRadius: "50%",
              background: done ? "#10A37F" : active ? "var(--orange)" : "#E5E5E5",
              color: done || active ? "#fff" : "#888",
              display: "inline-flex", alignItems: "center", justifyContent: "center",
              fontWeight: 700, fontSize: 13,
            }}>{done ? "✓" : n}</span>
            <span style={{ color: active ? "var(--ink)" : "var(--muted)", fontWeight: active ? 700 : 500, fontSize: 14 }}>
              {label}
            </span>
            {n < labels.length && <span style={{ width: 24, height: 2, background: "#E5E5E5", marginLeft: 4 }} />}
          </li>
        );
      })}
    </ol>
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
  return <h3 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", margin: "0 0 10px", fontSize: 22 }}>{children}</h3>;
}

function slugify(s: string) {
  return s.toLowerCase()
    .normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60) || ("truck-" + Math.random().toString(36).slice(2, 8));
}
