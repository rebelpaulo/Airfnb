"use client";
import { useRouter } from "next/navigation";
import { useState } from "react";

type Category = { id: number; slug: string; name_pt: string; icon: string | null };

type Props = {
  initial: {
    city?: string;
    pax?: number;
    priceMin?: number;
    priceMax?: number;
    cateringType?: string;
    cuisines?: string[];
    specialties?: string[];
    dietary?: string[];
    setupMax?: number;
    power?: string;
    sanitation?: string;
  };
  categories: Category[];
};

const CUISINES = [
  { slug: "portuguesa", label: "Portuguesa", flag: "🇵🇹" },
  { slug: "italiana",   label: "Italiana",   flag: "🇮🇹" },
  { slug: "japonesa",   label: "Japonesa",   flag: "🇯🇵" },
  { slug: "turca",      label: "Turca",      flag: "🇹🇷" },
  { slug: "espanhola",  label: "Espanhola",  flag: "🇪🇸" },
  { slug: "chinesa",    label: "Chinesa",    flag: "🇨🇳" },
  { slug: "mexicana",   label: "Mexicana",   flag: "🇲🇽" },
  { slug: "tailandesa", label: "Tailandesa", flag: "🇹🇭" },
  { slug: "marroquina", label: "Marroquina", flag: "🇲🇦" },
  { slug: "americana",  label: "Americana",  flag: "🇺🇸" },
];
const DIETARY = [
  { value: "vegetarian",  label: "Vegetariano" },
  { value: "vegan",       label: "Vegan" },
  { value: "gluten_free", label: "Sem Glúten" },
];
const SETUP = [
  { v: 30,  l: "Até 30 min" },
  { v: 60,  l: "Até 1h" },
  { v: 120, l: "Até 2h" },
  { v: 180, l: "Até 3h" },
];
const POWER = [
  { v: "nao_preciso", l: "Não preciso" },
  { v: "ate_3kw",     l: "Até 3 kW" },
  { v: "3_a_10kw",    l: "3 – 10 kW" },
  { v: "mais_10kw",   l: "Mais de 10 kW" },
];
const SANI = [
  { v: "none",        l: "Sem necessidade" },
  { v: "wc_proximo",  l: "WC próximo" },
  { v: "wc_dedicado", l: "WC dedicado" },
];

export function FilterModal({ initial, categories }: Props) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  // Section disclosure state — mirrors the original modal: pickers collapse by
  // default so the most-used fields (city / capacity / price / catering) sit
  // at the top.
  const [openSect, setOpenSect] = useState<Record<string, boolean>>({});
  const toggleSect = (k: string) => setOpenSect((s) => ({ ...s, [k]: !s[k] }));

  const [city, setCity]                 = useState(initial.city ?? "");
  const [pax, setPax]                   = useState(initial.pax ?? 100);
  const [priceMin, setPriceMin]         = useState<number | "">(initial.priceMin ?? "");
  const [priceMax, setPriceMax]         = useState<number | "">(initial.priceMax ?? "");
  const [cateringType, setCateringType] = useState(initial.cateringType ?? "");
  const [cuisines, setCuisines]         = useState<string[]>(initial.cuisines ?? []);
  const [specialties, setSpecialties]   = useState<string[]>(initial.specialties ?? []);
  const [dietary, setDietary]           = useState<string[]>(initial.dietary ?? []);
  const [setupMax, setSetupMax]         = useState<number | "">(initial.setupMax ?? "");
  const [power, setPower]               = useState(initial.power ?? "");
  const [sanitation, setSanitation]     = useState(initial.sanitation ?? "");

  function toggle<T>(list: T[], value: T) {
    return list.includes(value) ? list.filter((v) => v !== value) : [...list, value];
  }

  function submit() {
    const sp = new URLSearchParams();
    if (city.trim())               sp.set("city", city.trim());
    if (pax)                       sp.set("pax", String(pax));
    if (priceMin !== "")           sp.set("price_min", String(priceMin));
    if (priceMax !== "")           sp.set("price_max", String(priceMax));
    if (cateringType)              sp.set("catering", cateringType);
    if (cuisines.length)           sp.set("cuisines", cuisines.join(","));
    if (specialties.length)        sp.set("cats", specialties.join(","));
    if (dietary.length)            sp.set("dietary", dietary.join(","));
    if (setupMax !== "")           sp.set("setup_max", String(setupMax));
    if (power)                     sp.set("power", power);
    if (sanitation)                sp.set("sanitation", sanitation);
    router.push(`/catalogo?${sp.toString()}`);
    setOpen(false);
  }

  function reset() {
    setCity(""); setPax(100); setPriceMin(""); setPriceMax("");
    setCateringType(""); setCuisines([]); setSpecialties([]); setDietary([]);
    setSetupMax(""); setPower(""); setSanitation("");
  }

  return (
    <>
      <button
        type="button"
        className="btn-pill outline"
        onClick={() => setOpen(true)}
        style={{
          borderColor: "var(--line)", color: "var(--ink)",
          display: "inline-flex", alignItems: "center", gap: 8,
          padding: "12px 22px",
        }}
      >
        <span className="material-symbols-outlined" style={{ fontSize: 18 }}>tune</span>
        Filtros
      </button>

      {open && (
        <div
          role="dialog"
          aria-modal="true"
          onClick={() => setOpen(false)}
          style={{
            position: "fixed", inset: 0, background: "rgba(0,0,0,0.4)",
            display: "flex", justifyContent: "center", alignItems: "flex-start",
            paddingTop: 60, paddingBottom: 30, paddingLeft: 16, paddingRight: 16,
            zIndex: 100, overflowY: "auto",
          }}
        >
          <div
            onClick={(e) => e.stopPropagation()}
            style={{
              background: "#fff", borderRadius: 16, padding: 28,
              maxWidth: 760, width: "100%", boxShadow: "0 20px 60px rgba(0,0,0,0.25)",
            }}
          >
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 18 }}>
              <h2 style={{ margin: 0, fontFamily: "Bebas Neue, sans-serif", fontSize: 26, color: "var(--ink)" }}>
                Filtros
              </h2>
              <button type="button" onClick={() => setOpen(false)} aria-label="Fechar"
                style={{ background: "transparent", border: "none", cursor: "pointer", fontSize: 22, color: "var(--muted)" }}>
                ×
              </button>
            </div>

            <div style={{ display: "grid", gap: 18 }}>
              <Field label="Localização">
                <input value={city} onChange={(e) => setCity(e.target.value)} placeholder="Lisboa" />
              </Field>

              <div>
                <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 6 }}>
                  Capacidade — <span style={{ color: "var(--orange)" }}>{pax} pessoas</span>
                </div>
                <input type="range" min={20} max={2000} step={10} value={pax} onChange={(e) => setPax(Number(e.target.value))} style={{ width: "100%" }} />
              </div>

              <div>
                <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 6 }}>Intervalo de Preço (€)</div>
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
                  <input type="number" min={0} step={10} value={priceMin} onChange={(e) => setPriceMin(e.target.value === "" ? "" : Number(e.target.value))} placeholder="min" />
                  <input type="number" min={0} step={10} value={priceMax} onChange={(e) => setPriceMax(e.target.value === "" ? "" : Number(e.target.value))} placeholder="max" />
                </div>
              </div>

              <Field label="Tipo de Catering">
                <select value={cateringType} onChange={(e) => setCateringType(e.target.value)}>
                  <option value="">Indiferente</option>
                  <option value="food">Só Comida</option>
                  <option value="drinks">Só Bebida</option>
                  <option value="food_and_drinks">Comida e Bebida</option>
                </select>
              </Field>

              <Disclosure label="Tipo de Cozinha" open={!!openSect.cuisine} onToggle={() => toggleSect("cuisine")}>
                <div className="chips">
                  {CUISINES.map((c) => (
                    <button type="button" key={c.slug} className="chip"
                      data-active={cuisines.includes(c.slug)}
                      onClick={() => setCuisines((s) => toggle(s, c.slug))}>
                      <span style={{ fontSize: 16 }}>{c.flag}</span> {c.label}
                    </button>
                  ))}
                </div>
              </Disclosure>

              <Disclosure label="Especialidades" open={!!openSect.spec} onToggle={() => toggleSect("spec")}>
                <div className="chips">
                  {categories.map((c) => (
                    <button type="button" key={c.id} className="chip"
                      data-active={specialties.includes(c.slug)}
                      onClick={() => setSpecialties((s) => toggle(s, c.slug))}>
                      <span className="material-symbols-outlined" style={{ fontSize: 16 }}>{c.icon ?? "restaurant"}</span>
                      {c.name_pt}
                    </button>
                  ))}
                </div>
              </Disclosure>

              <Disclosure label="Dietas Especiais" open={!!openSect.diet} onToggle={() => toggleSect("diet")}>
                <div className="chips">
                  {DIETARY.map((d) => (
                    <button type="button" key={d.value} className="chip"
                      data-active={dietary.includes(d.value)}
                      onClick={() => setDietary((s) => toggle(s, d.value))}>
                      {d.label}
                    </button>
                  ))}
                </div>
              </Disclosure>

              <Disclosure label="Horas de Montagem/Desmontagem" open={!!openSect.setup} onToggle={() => toggleSect("setup")}>
                <select value={setupMax} onChange={(e) => setSetupMax(e.target.value === "" ? "" : Number(e.target.value))}>
                  <option value="">Indiferente</option>
                  {SETUP.map((s) => <option key={s.v} value={s.v}>{s.l}</option>)}
                </select>
              </Disclosure>

              <Disclosure label="Necessidade Energética" open={!!openSect.power} onToggle={() => toggleSect("power")}>
                <select value={power} onChange={(e) => setPower(e.target.value)}>
                  <option value="">Indiferente</option>
                  {POWER.map((p) => <option key={p.v} value={p.v}>{p.l}</option>)}
                </select>
              </Disclosure>

              <Disclosure label="Saneamento Básico" open={!!openSect.sani} onToggle={() => toggleSect("sani")}>
                <select value={sanitation} onChange={(e) => setSanitation(e.target.value)}>
                  <option value="">Indiferente</option>
                  {SANI.map((s) => <option key={s.v} value={s.v}>{s.l}</option>)}
                </select>
              </Disclosure>
            </div>

            <div style={{ display: "flex", justifyContent: "space-between", marginTop: 22, gap: 10 }}>
              <button type="button" onClick={reset}
                style={{ background: "transparent", border: "1px solid var(--line)", padding: "10px 18px", borderRadius: 999, cursor: "pointer", color: "var(--muted)" }}>
                Limpar
              </button>
              <button type="button" onClick={submit} className="btn-pill"
                style={{ padding: "12px 28px", background: "#1F7CFF" }}>
                Submeter Filtros
              </button>
            </div>
          </div>
        </div>
      )}
    </>
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

function Disclosure({ label, open, onToggle, children }: { label: string; open: boolean; onToggle: () => void; children: React.ReactNode }) {
  return (
    <div style={{ borderTop: "1px solid var(--line)", paddingTop: 14 }}>
      <button type="button" onClick={onToggle}
        style={{
          width: "100%", display: "flex", justifyContent: "space-between", alignItems: "center",
          background: "transparent", border: "none", cursor: "pointer", padding: 0,
          fontFamily: "inherit", fontSize: 14, fontWeight: 700, color: "var(--ink)",
        }}>
        <span>{label}</span>
        <span className="material-symbols-outlined" style={{ fontSize: 22, color: "var(--muted)", transform: open ? "rotate(180deg)" : "rotate(0)", transition: "transform .15s" }}>
          expand_more
        </span>
      </button>
      {open && <div style={{ marginTop: 12 }}>{children}</div>}
    </div>
  );
}
