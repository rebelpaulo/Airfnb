"use client";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { TruckPhotoUpload } from "@/components/TruckPhotoUpload";
import { TruckPdfUpload } from "@/components/TruckPdfUpload";
import { CityAutocomplete } from "@/components/CityAutocomplete";

type Category = { id: number; slug: string; name_pt: string; icon: string | null };
type Props = { userId: string; categories: Category[] };

// --- Chip vocabularies that mirror the original /addTruck wizard. -----------
// Cuisine types: country-flag chips. Stored as free-text in trucks.cuisine_types
// because the original site lets owners type their own. The presets are the
// 10 the original ships with; "outros" lets owners add custom values.
const CUISINES: { slug: string; label: string; flag: string }[] = [
  { slug: "portuguesa",  label: "Portuguesa",  flag: "🇵🇹" },
  { slug: "italiana",    label: "Italiana",    flag: "🇮🇹" },
  { slug: "japonesa",    label: "Japonesa",    flag: "🇯🇵" },
  { slug: "turca",       label: "Turca",       flag: "🇹🇷" },
  { slug: "espanhola",   label: "Espanhola",   flag: "🇪🇸" },
  { slug: "chinesa",     label: "Chinesa",     flag: "🇨🇳" },
  { slug: "mexicana",    label: "Mexicana",    flag: "🇲🇽" },
  { slug: "tailandesa",  label: "Tailandesa",  flag: "🇹🇭" },
  { slug: "marroquina",  label: "Marroquina",  flag: "🇲🇦" },
  { slug: "americana",   label: "Americana",   flag: "🇺🇸" },
];

const DIETARY: { value: "vegetarian" | "gluten_free" | "vegan"; label: string; icon: string }[] = [
  { value: "vegetarian",  label: "Pratos Vegetarianos", icon: "spa" },
  { value: "gluten_free", label: "Sem Glúten",          icon: "no_meals" },
  { value: "vegan",       label: "Vegan",               icon: "eco" },
];

const CATERING_TYPES = [
  { value: "fixed",   label: "Preço Fixo" },
  { value: "percent", label: "% sobre vendas" },
  { value: "mixed",   label: "Misto" },
];

const SANITATION = [
  { value: "none",        label: "Sem necessidade" },
  { value: "wc_proximo",  label: "WC próximo do local" },
  { value: "wc_dedicado", label: "WC dedicado" },
];

const POWER_OPTIONS = ["nao_preciso", "ate_3kw", "3_a_10kw", "mais_10kw"] as const;
const POWER_LABEL: Record<typeof POWER_OPTIONS[number], string> = {
  nao_preciso:   "Não preciso",
  ate_3kw:       "Até 3 kW",
  "3_a_10kw":    "3 – 10 kW",
  mais_10kw:     "Mais de 10 kW",
};
const POWER_KW: Record<typeof POWER_OPTIONS[number], number | null> = {
  nao_preciso:   0,
  ate_3kw:       3,
  "3_a_10kw":    10,
  mais_10kw:     15,
};

const SETUP_OPTIONS = [30, 45, 60, 90, 120, 180];

export function TruckWizard({ userId, categories }: Props) {
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
  const [cateringType, setCateringType] = useState<string>("fixed");

  // step 2
  const [cuisines, setCuisines] = useState<string[]>([]);
  const [cuisineOther, setCuisineOther] = useState("");
  const [categoryIds, setCategoryIds] = useState<number[]>([]);
  const [dietary, setDietary] = useState<string[]>([]);

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
    if (!name.trim())     { setErr("Indica o nome do truck.");      return; }
    if (!baseCity.trim()) { setErr("Indica a localidade base.");    return; }
    setBusy(true);
    try {
      const supa = supabaseBrowser();
      // Atomic role claim: only set role=owner when it's still null. Using
      // .is("role", null) in the WHERE clause closes the read-then-write race
      // window. If the row already had a role, the update affects 0 rows and
      // we then re-read to decide whether to advance or block.
      const claim = await (supa as any)
        .from("airfnb_profiles")
        .update({ role: "owner" })
        .eq("id", userId)
        .is("role", null)
        .select("role");
      if (claim.error) throw new Error(claim.error.message);
      if (!claim.data?.length) {
        const { data: cur } = await (supa as any)
          .from("airfnb_profiles").select("role").eq("id", userId).maybeSingle();
        if (cur?.role !== "owner") {
          setErr("Esta conta é de organizador. Para adicionar trucks usa uma conta diferente.");
          setBusy(false);
          return;
        }
      }

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
    if (!truckId) { setErr("Estado inválido — recarrega a página."); return; }
    setBusy(true);
    setErr(null);
    try {
      const supa = supabaseBrowser();
      const cuisinesFinal = cuisineOther.trim()
        ? Array.from(new Set([...cuisines, cuisineOther.trim().toLowerCase()]))
        : cuisines;
      const { error } = await (supa as any).from("airfnb_trucks").update({
        cuisine_types:   cuisinesFinal,
        dietary_options: dietary,
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
    if (!truckId) { setErr("Estado inválido — recarrega a página."); return; }
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
      <Stepper step={step} />
      {err && <div style={{ background: "var(--error-bg)", color: "var(--error-text)", border: "1px solid var(--error-line)", padding: "10px 14px", borderRadius: "var(--radius-sm)", margin: "0 0 16px", fontSize: 14 }}>{err}</div>}

      {step === 1 && (
        <div style={{ display: "grid", gap: 14 }}>
          <Field label="Nome do truck">
            <input value={name} onChange={(e) => setName(e.target.value)} maxLength={120} placeholder="Ex: Divine Burguer's" />
          </Field>
          <div style={{ display: "grid", gridTemplateColumns: "2fr 1fr", gap: 14 }}>
            <Field label="Localidade base">
              <CityAutocomplete
                defaultValue={baseCity}
                placeholder="Lisboa"
                onChange={(v) => setBaseCity(v)}
              />
            </Field>
            <Field label="Raio (km)">
              <input type="number" min={5} max={500} value={radius} onChange={(e) => setRadius(Number(e.target.value))} />
            </Field>
          </div>
          <Field label="Capacidade máxima (pax/evento)">
            <input type="number" min={10} value={capacity} onChange={(e) => setCapacity(Number(e.target.value))} />
          </Field>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
            <Field label="Eventos a partir de (pax)">
              <input type="number" min={1} value={minPax} onChange={(e) => setMinPax(Number(e.target.value))} />
            </Field>
            <Field label="Até (pax)">
              <input type="number" min={1} value={maxPax} onChange={(e) => setMaxPax(Number(e.target.value))} />
            </Field>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
            <Field label="Preço mínimo (€)">
              <input type="number" min={0} step={10} value={priceMin} onChange={(e) => setPriceMin(e.target.value === "" ? "" : Number(e.target.value))} placeholder="600" />
            </Field>
            <Field label="Preço por pax (€)">
              <input type="number" min={0} step={0.5} value={priceMax} onChange={(e) => setPriceMax(e.target.value === "" ? "" : Number(e.target.value))} placeholder="12" />
            </Field>
          </div>
          <Field label="Tipo de catering">
            <div className="chips">
              {CATERING_TYPES.map((c) => (
                <button
                  type="button"
                  key={c.value}
                  className="chip"
                  data-active={cateringType === c.value}
                  onClick={() => setCateringType(c.value)}
                >
                  {c.label}
                </button>
              ))}
            </div>
          </Field>
        </div>
      )}

      {step === 2 && (
        <div style={{ display: "grid", gap: 20 }}>
          <section>
            <SectionTitle>Tipos de Cozinha</SectionTitle>
            <div className="chips">
              {CUISINES.map((c) => (
                <button
                  type="button"
                  key={c.slug}
                  className="chip"
                  data-active={cuisines.includes(c.slug)}
                  onClick={() => setCuisines((s) => toggle(s, c.slug))}
                >
                  <span style={{ fontSize: 16 }}>{c.flag}</span> {c.label}
                </button>
              ))}
            </div>
            <div style={{ marginTop: 10 }}>
              <input
                value={cuisineOther}
                onChange={(e) => setCuisineOther(e.target.value)}
                placeholder="Outra (ex: Fusão indo-portuguesa)"
                style={{ width: "100%", maxWidth: 360 }}
              />
            </div>
          </section>

          <section>
            <SectionTitle>Especialidades</SectionTitle>
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
            <SectionTitle>Dietas Especiais</SectionTitle>
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
                  {d.label}
                </button>
              ))}
            </div>
          </section>
        </div>
      )}

      {step === 3 && (
        <div style={{ display: "grid", gap: 14 }}>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
            <Field label="Tempo de Montagem (min)">
              <select value={setupMin} onChange={(e) => setSetupMin(Number(e.target.value))}>
                {SETUP_OPTIONS.map((m) => <option key={m} value={m}>{m} min</option>)}
              </select>
            </Field>
            <Field label="Tempo de Desmontagem (min)">
              <select value={teardownMin} onChange={(e) => setTeardownMin(Number(e.target.value))}>
                {SETUP_OPTIONS.map((m) => <option key={m} value={m}>{m} min</option>)}
              </select>
            </Field>
          </div>
          <Field label="Necessidade Energética">
            <select value={power} onChange={(e) => setPower(e.target.value as typeof POWER_OPTIONS[number])}>
              {POWER_OPTIONS.map((p) => <option key={p} value={p}>{POWER_LABEL[p]}</option>)}
            </select>
          </Field>
          <Field label="Saneamento Básico">
            <select value={sanitation} onChange={(e) => setSanitation(e.target.value)}>
              {SANITATION.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}
            </select>
          </Field>
        </div>
      )}

      {step === 4 && truckId && (
        <div style={{ display: "grid", gap: 20 }}>
          <section>
            <SectionTitle>Adicionar Fotografias</SectionTitle>
            <TruckPhotoUpload truckId={truckId} />
          </section>
          <section>
            <SectionTitle>Adicionar Documentação</SectionTitle>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(260px, 1fr))", gap: 12 }}>
              <TruckPdfUpload truckId={truckId} kind="asae"      label="Certificado ASAE" />
              <TruckPdfUpload truckId={truckId} kind="comercial" label="Certificado Comercial" />
              <TruckPdfUpload truckId={truckId} kind="financas"  label="Certificado Finanças" />
              <TruckPdfUpload truckId={truckId} kind="outros"    label="Outros Documentos" />
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
          Voltar
        </button>
        {step < 4 ? (
          <button
            type="button"
            className="btn-pill"
            onClick={step === 1 ? saveStep1AndAdvance : step === 2 ? saveStep2AndAdvance : saveStep3AndAdvance}
            disabled={busy}
          >
            {busy ? "A guardar…" : "Próximo"}
          </button>
        ) : (
          <button type="button" className="btn-pill" onClick={finish}>
            Finalizar
          </button>
        )}
      </div>
    </div>
  );
}

function Stepper({ step }: { step: number }) {
  const steps = ["Básico", "Cozinha", "Logística", "Mídia"];
  return (
    <ol style={{ display: "flex", gap: 12, padding: 0, margin: "0 0 22px", listStyle: "none", flexWrap: "wrap" }}>
      {steps.map((label, i) => {
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
            {n < steps.length && <span style={{ width: 24, height: 2, background: "#E5E5E5", marginLeft: 4 }} />}
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
