"use client";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { useDict } from "@/components/DictProvider";

type Category = { id: number; slug: string; name_pt: string; icon: string | null };
type ServiceType = "food_truck" | "catering" | "bar";

type Props = {
  initial: {
    city?: string;
    pax?: number;
    priceMin?: number;
    priceMax?: number;
    serviceType?: ServiceType;
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

const CUISINE_SLUGS = [
  { slug: "portuguesa", key: "cuisine_pt", flag: "🇵🇹" },
  { slug: "italiana",   key: "cuisine_it", flag: "🇮🇹" },
  { slug: "japonesa",   key: "cuisine_jp", flag: "🇯🇵" },
  { slug: "turca",      key: "cuisine_tr", flag: "🇹🇷" },
  { slug: "espanhola",  key: "cuisine_es", flag: "🇪🇸" },
  { slug: "chinesa",    key: "cuisine_cn", flag: "🇨🇳" },
  { slug: "mexicana",   key: "cuisine_mx", flag: "🇲🇽" },
  { slug: "tailandesa", key: "cuisine_th", flag: "🇹🇭" },
  { slug: "marroquina", key: "cuisine_ma", flag: "🇲🇦" },
  { slug: "americana",  key: "cuisine_us", flag: "🇺🇸" },
] as const;
const DIETARY_VALUES = [
  { value: "vegetarian",  key: "dietary_vegetarian" },
  { value: "vegan",       key: "dietary_vegan" },
  { value: "gluten_free", key: "dietary_gluten_free" },
] as const;
const SETUP_VALUES = [
  { v: 30,  key: "setup_30" },
  { v: 60,  key: "setup_60" },
  { v: 120, key: "setup_120" },
  { v: 180, key: "setup_180" },
] as const;
const POWER_VALUES = [
  { v: "nao_preciso", key: "power_none" },
  { v: "ate_3kw",     key: "power_3" },
  { v: "3_a_10kw",    key: "power_3_10" },
  { v: "mais_10kw",   key: "power_10_plus" },
] as const;
const SANI_VALUES = [
  { v: "none",        key: "sani_none" },
  { v: "wc_proximo",  key: "sani_close" },
  { v: "wc_dedicado", key: "sani_dedicated" },
] as const;
const SERVICE_TYPES: ServiceType[] = ["food_truck", "catering", "bar"];

export function FilterModal({ initial, categories }: Props) {
  const dict = useDict();
  const t = dict.catalog.filter_modal;
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
  const [serviceType, setServiceType]   = useState<ServiceType | "">(initial.serviceType ?? "");
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
    if (serviceType)               sp.set("service_type", serviceType);
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
    setServiceType(""); setCateringType(""); setCuisines([]); setSpecialties([]); setDietary([]);
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
        {t.button_label}
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
                {t.title}
              </h2>
              <button type="button" onClick={() => setOpen(false)} aria-label={t.close_aria}
                style={{ background: "transparent", border: "none", cursor: "pointer", fontSize: 22, color: "var(--muted)" }}>
                ×
              </button>
            </div>

            <div style={{ display: "grid", gap: 18 }}>
              <Field label={t.loc_label}>
                <input value={city} onChange={(e) => setCity(e.target.value)} placeholder={t.loc_placeholder} />
              </Field>

              <div>
                <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 6 }}>
                  {t.capacity_label} — <span style={{ color: "var(--orange)" }}>{pax} {t.capacity_people}</span>
                </div>
                <input type="range" min={20} max={2000} step={10} value={pax} onChange={(e) => setPax(Number(e.target.value))} style={{ width: "100%" }} />
              </div>

              <div>
                <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 6 }}>{t.price_label}</div>
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
                  <input type="number" min={0} step={10} value={priceMin} onChange={(e) => setPriceMin(e.target.value === "" ? "" : Number(e.target.value))} placeholder={t.price_min} />
                  <input type="number" min={0} step={10} value={priceMax} onChange={(e) => setPriceMax(e.target.value === "" ? "" : Number(e.target.value))} placeholder={t.price_max} />
                </div>
              </div>

              <Field label={t.service_type_label}>
                <select
                  value={serviceType}
                  onChange={(e) => setServiceType(e.target.value as ServiceType | "")}
                >
                  <option value="">{t.service_type_any}</option>
                  {SERVICE_TYPES.map((value) => (
                    <option key={value} value={value}>{dict.vocab.service_type[value]}</option>
                  ))}
                </select>
              </Field>

              <Field label={t.catering_label}>
                <select value={cateringType} onChange={(e) => setCateringType(e.target.value)}>
                  <option value="">{t.catering_any}</option>
                  <option value="food">{t.catering_food}</option>
                  <option value="drinks">{t.catering_drinks}</option>
                  <option value="food_and_drinks">{t.catering_both}</option>
                </select>
              </Field>

              <Disclosure label={t.cuisine_label} open={!!openSect.cuisine} onToggle={() => toggleSect("cuisine")}>
                <div className="chips">
                  {CUISINE_SLUGS.map((c) => (
                    <button type="button" key={c.slug} className="chip"
                      data-active={cuisines.includes(c.slug)}
                      onClick={() => setCuisines((s) => toggle(s, c.slug))}>
                      <span style={{ fontSize: 16 }}>{c.flag}</span> {t[c.key]}
                    </button>
                  ))}
                </div>
              </Disclosure>

              <Disclosure label={t.specialties_label} open={!!openSect.spec} onToggle={() => toggleSect("spec")}>
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

              <Disclosure label={t.dietary_label} open={!!openSect.diet} onToggle={() => toggleSect("diet")}>
                <div className="chips">
                  {DIETARY_VALUES.map((d) => (
                    <button type="button" key={d.value} className="chip"
                      data-active={dietary.includes(d.value)}
                      onClick={() => setDietary((s) => toggle(s, d.value))}>
                      {t[d.key]}
                    </button>
                  ))}
                </div>
              </Disclosure>

              <Disclosure label={t.setup_label} open={!!openSect.setup} onToggle={() => toggleSect("setup")}>
                <select value={setupMax} onChange={(e) => setSetupMax(e.target.value === "" ? "" : Number(e.target.value))}>
                  <option value="">{t.setup_any}</option>
                  {SETUP_VALUES.map((s) => <option key={s.v} value={s.v}>{t[s.key]}</option>)}
                </select>
              </Disclosure>

              <Disclosure label={t.power_label} open={!!openSect.power} onToggle={() => toggleSect("power")}>
                <select value={power} onChange={(e) => setPower(e.target.value)}>
                  <option value="">{t.power_any}</option>
                  {POWER_VALUES.map((p) => <option key={p.v} value={p.v}>{t[p.key]}</option>)}
                </select>
              </Disclosure>

              <Disclosure label={t.sani_label} open={!!openSect.sani} onToggle={() => toggleSect("sani")}>
                <select value={sanitation} onChange={(e) => setSanitation(e.target.value)}>
                  <option value="">{t.sani_any}</option>
                  {SANI_VALUES.map((s) => <option key={s.v} value={s.v}>{t[s.key]}</option>)}
                </select>
              </Disclosure>
            </div>

            <div style={{ display: "flex", justifyContent: "space-between", marginTop: 22, gap: 10 }}>
              <button type="button" onClick={reset}
                style={{ background: "transparent", border: "1px solid var(--line)", padding: "10px 18px", borderRadius: 999, cursor: "pointer", color: "var(--muted)" }}>
                {t.reset_btn}
              </button>
              <button type="button" onClick={submit} className="btn-pill"
                style={{ padding: "12px 28px", background: "#1F7CFF" }}>
                {t.submit_btn}
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
