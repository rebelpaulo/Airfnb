"use client";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";

type Category = { id: number; slug: string; name_pt: string; icon: string | null };
type Props = {
  userId: string;
  defaultName: string;
  defaultEmail: string;
  defaultPhone: string;
  categories: Category[];
};

const EVENT_KINDS: Array<{ value: string; label: string }> = [
  { value: "wedding",    label: "Casamento" },
  { value: "birthday",   label: "Aniversário" },
  { value: "corporate",  label: "Corporativo" },
  { value: "festival",   label: "Festival" },
  { value: "conference", label: "Conferência" },
  { value: "private",    label: "Festa Privada" },
  { value: "other",      label: "Outro" },
];

const CATERING_RADIOS: Array<{ value: "food" | "drinks" | "food_and_drinks"; label: string }> = [
  { value: "food",            label: "Só Comida" },
  { value: "drinks",          label: "Só Bebida" },
  { value: "food_and_drinks", label: "Comida e Bebida" },
];

// Same 10 cuisine chips as the truck wizard (flag emoji + label)
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

const DIETARY: Array<{ value: "vegetarian" | "gluten_free" | "vegan"; label: string }> = [
  { value: "vegetarian",  label: "Vegetariano" },
  { value: "vegan",       label: "Vegan" },
  { value: "gluten_free", label: "Sem Glúten" },
];

const SETUP_OPTIONS = [
  { value: 0,   label: "0h" },
  { value: 60,  label: "1h" },
  { value: 120, label: "2h" },
  { value: 180, label: "3h" },
  { value: 240, label: "4h" },
  { value: 360, label: "6h" },
  { value: 480, label: "8h" },
];

const ENERGY = [
  { value: "nao_preciso", label: "Não preciso" },
  { value: "ate_3kw",     label: "Até 3 kW" },
  { value: "3_a_10kw",    label: "3 – 10 kW" },
  { value: "mais_10kw",   label: "Mais de 10 kW" },
] as const;

const SANITATION = [
  { value: "nao_necessario", label: "Não necessário" },
  { value: "wc_proximo",     label: "WC próximo do local" },
  { value: "wc_dedicado",    label: "WC dedicado para staff" },
] as const;

const EXTRA_SERVICES = [
  "Ticketing e Gestão de Convidados",
  "Segurança",
  "Fotografia e Vídeo",
  "Organização e Planeamento",
  "Animação",
  "Encontrar uma Venue",
  "Limpeza e Gestão de Resíduos",
  "Promoção do Evento",
];

const SELECTION_MODES: Array<{ value: "open_to_offers" | "pick_myself" | "assisted"; label: string; hint: string }> = [
  { value: "open_to_offers", label: "Estou aberto a ofertas",        hint: "Os trucks que dão match candidatam-se ao teu pedido." },
  { value: "pick_myself",    label: "Quero escolher/procurar trucks", hint: "Vais navegar no catálogo e convidar diretamente." },
  { value: "assisted",       label: "Preciso de ajuda especializada", hint: "A equipa Air F&B fala contigo e cura a shortlist." },
];

export function OrganizerWizard({ userId, defaultName, defaultEmail, defaultPhone, categories }: Props) {
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
  const [locality, setLocality] = useState("");
  const [kind, setKind] = useState("wedding");
  const [guests, setGuests] = useState(200);
  const [trucksWanted, setTrucksWanted] = useState(1);
  const [cateringType, setCateringType] = useState<"food" | "drinks" | "food_and_drinks">("food_and_drinks");
  const [startAt, setStartAt] = useState("");
  const [endAt, setEndAt] = useState("");
  const [budget, setBudget] = useState(500);
  const [budgetFlex, setBudgetFlex] = useState(false);

  // ---- Step 2: cuisine + specialties + dietary + notes ----
  const [cuisines, setCuisines] = useState<string[]>([]);
  const [specialtyIds, setSpecialtyIds] = useState<number[]>([]);
  const [dietary, setDietary] = useState<string[]>([]);
  const [notes, setNotes] = useState("");

  // ---- Step 3: logistics ----
  const [setupMin, setSetupMin] = useState(60);
  const [teardownMin, setTeardownMin] = useState(60);
  const [energy, setEnergy] = useState<typeof ENERGY[number]["value"]>("ate_3kw");
  const [energyHelp, setEnergyHelp] = useState(false);
  const [sanitation, setSanitation] = useState<typeof SANITATION[number]["value"]>("nao_necessario");

  // ---- Step 4: extra services ----
  const [extras, setExtras] = useState<string[]>([]);

  // ---- Step 5: selection mode ----
  const [selectionMode, setSelectionMode] = useState<"open_to_offers" | "pick_myself" | "assisted">("open_to_offers");

  // Honeypot: hidden field invisible to humans but eagerly filled by naive
  // form-scraping bots. If non-empty at submit, abort the insert silently.
  const [honeypot, setHoneypot] = useState("");

  function toggle<T>(list: T[], value: T): T[] {
    return list.includes(value) ? list.filter((v) => v !== value) : [...list, value];
  }

  function validateStep1(): string | null {
    if (!name.trim())              return "Indica o teu nome.";
    if (!email.trim())             return "Indica o teu email.";
    if (!eventTitle.trim())        return "Indica o nome do evento.";
    if (!locality.trim())          return "Indica a localidade.";
    if (!startAt)                  return "Indica a data de início.";
    if (endAt && endAt < startAt)  return "A data de fim não pode ser anterior ao início.";
    return null;
  }

  async function submitAll() {
    setBusy(true);
    setErr(null);
    try {
      // Honeypot tripwire — silently no-op (don't reveal the trap exists).
      // The user goes back to the form thinking it submitted; we just don't
      // create the row.
      if (honeypot.trim() !== "") {
        setBusy(false);
        router.push("/dashboard/organizer");
        return;
      }

      const supa = supabaseBrowser();

      // Rate limit: cap event requests per organizer (10/day). Blocks
      // duplicate-spam without bothering legitimate organizers.
      const { data: rateOk } = await (supa as any).rpc("airfnb_check_rate_limit", {
        p_action:           "event_request_create",
        p_bucket:           userId,
        p_limit_per_window: 10,
        p_window_seconds:   86400,
      });
      if (rateOk === false) {
        throw new Error("Atingiste o limite diário de pedidos publicados (10). Tenta amanhã.");
      }

      // selection_mode → discovery_mode mapping for the marketplace match logic
      const discovery =
        selectionMode === "pick_myself" ? "curated" :
        "broadcast"; // open_to_offers + assisted both go broadcast; assisted just flags assistance_requested
      const { data, error } = await (supa as any).from("airfnb_event_requests").insert({
        organizer_id:          userId,
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
        sanitation_level:      sanitation,
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
      router.push(`/dashboard/organizer/pedidos/${data.id}`);
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
          tab into it; bots that auto-fill every input trip the no-op path. */}
      <input
        type="text"
        name="website"
        tabIndex={-1}
        autoComplete="off"
        aria-hidden="true"
        value={honeypot}
        onChange={(e) => setHoneypot(e.target.value)}
        style={{ position: "absolute", left: "-9999px", width: 1, height: 1, opacity: 0 }}
      />
      <DotStepper step={step} total={5} />
      {err && <div style={{ background: "#FFE6DF", color: "#8B1100", padding: "10px 14px", borderRadius: 10, margin: "0 0 16px", fontSize: 14 }}>{err}</div>}

      {step === 1 && (
        <div style={{ display: "grid", gap: 14 }}>
          <Field label="Seu Nome">
            <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Insira seu nome" />
          </Field>
          <Field label="E-mail">
            <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="seuemail@exemplo.com" />
          </Field>
          <Field label="Telefone">
            <input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="(+351) 912 345 678" />
          </Field>
          <Field label="Nome do Evento">
            <input value={eventTitle} onChange={(e) => setEventTitle(e.target.value)} maxLength={120} placeholder="Insira o nome do evento" />
          </Field>
          <Field label="Endereço">
            <input value={address} onChange={(e) => setAddress(e.target.value)} placeholder="Rua, número, complemento" />
          </Field>
          <Field label="Localidade">
            <input value={locality} onChange={(e) => setLocality(e.target.value)} placeholder="Cidade, região" />
          </Field>
          <Field label="Tipo de Evento">
            <select value={kind} onChange={(e) => setKind(e.target.value)}>
              {EVENT_KINDS.map((k) => <option key={k.value} value={k.value}>{k.label}</option>)}
            </select>
          </Field>
          <Field label={`Nº de Convidados — ${guests}`}>
            <input type="range" min={20} max={5000} step={10} value={guests} onChange={(e) => setGuests(Number(e.target.value))} />
          </Field>
          <Field label="Trucks Recomendados">
            <input type="number" min={1} max={10}
              value={trucksWanted}
              onChange={(e) => {
                // Clamp client-side so the user can't type 11+ and hit the
                // airfnb_event_requests.slots_needed check constraint (1..10).
                const v = Math.min(10, Math.max(1, Number(e.target.value) || 1));
                setTrucksWanted(v);
              }} />
            <small style={{ color: "var(--muted)", fontSize: 12 }}>
              💡 Sugestão: 1 truck por cada 120–200 pax (depende do tipo de evento).
            </small>
          </Field>
          <div>
            <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 6 }}>Tipo de Catering</div>
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
                  {c.label}
                </label>
              ))}
            </div>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
            <Field label="Data de Início">
              <input type="date" value={startAt} onChange={(e) => setStartAt(e.target.value)} />
            </Field>
            <Field label="Data de Fim">
              <input type="date" value={endAt} onChange={(e) => setEndAt(e.target.value)} />
            </Field>
          </div>
          <Field label={`Orçamento Estimado — € ${budget}`}>
            <input type="range" min={100} max={20000} step={50} value={budget} onChange={(e) => setBudget(Number(e.target.value))} />
          </Field>
          <label style={{ display: "inline-flex", alignItems: "center", gap: 6, cursor: "pointer", fontSize: 14 }}>
            <input type="checkbox" checked={budgetFlex} onChange={(e) => setBudgetFlex(e.target.checked)} />
            Orçamento flexível
          </label>
        </div>
      )}

      {step === 2 && (
        <div style={{ display: "grid", gap: 20 }}>
          <section>
            <SectionTitle>Tipos de cozinha</SectionTitle>
            <div className="chips">
              {CUISINES.map((c) => (
                <button type="button" key={c.slug} className="chip"
                  data-active={cuisines.includes(c.slug)}
                  onClick={() => setCuisines((s) => toggle(s, c.slug))}>
                  <span style={{ fontSize: 16 }}>{c.flag}</span> {c.label}
                </button>
              ))}
            </div>
          </section>
          <section>
            <SectionTitle>Especialidades</SectionTitle>
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
            <SectionTitle>Dietas especiais</SectionTitle>
            <div className="chips">
              {DIETARY.map((d) => (
                <button type="button" key={d.value} className="chip"
                  data-active={dietary.includes(d.value)}
                  onClick={() => setDietary((s) => toggle(s, d.value))}>
                  {d.label}
                </button>
              ))}
            </div>
          </section>
          <Field label="Notas para a Organização">
            <textarea
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder="Insira informações que considere necessárias sobre o evento"
              style={{ minHeight: 140, resize: "vertical" }}
            />
          </Field>
        </div>
      )}

      {step === 3 && (
        <div style={{ display: "grid", gap: 18 }}>
          <section>
            <SectionTitle>Horas de Montagem e Desmontagem</SectionTitle>
            <p style={{ color: "var(--muted)", margin: "0 0 12px", fontSize: 13 }}>
              Informe quanto tempo será disponibilizado para a montagem e desmontagem dos trucks.
            </p>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
              <Field label="Montagem">
                <select value={setupMin} onChange={(e) => setSetupMin(Number(e.target.value))}>
                  {SETUP_OPTIONS.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
                </select>
              </Field>
              <Field label="Desmontagem">
                <select value={teardownMin} onChange={(e) => setTeardownMin(Number(e.target.value))}>
                  {SETUP_OPTIONS.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
                </select>
              </Field>
            </div>
          </section>
          <section>
            <SectionTitle>Instalação Energética</SectionTitle>
            <p style={{ color: "var(--muted)", margin: "0 0 8px", fontSize: 13 }}>
              Informe que tipo de instalações elétricas estarão disponíveis no recinto.
            </p>
            <select value={energy} onChange={(e) => setEnergy(e.target.value as typeof ENERGY[number]["value"])}>
              {ENERGY.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
            </select>
            <label style={{ display: "inline-flex", alignItems: "center", gap: 6, marginTop: 10, fontSize: 14, cursor: "pointer" }}>
              <input type="checkbox" checked={energyHelp} onChange={(e) => setEnergyHelp(e.target.checked)} />
              Existe assistência para instalação elétrica
            </label>
          </section>
          <section>
            <SectionTitle>Saneamento Básico</SectionTitle>
            <p style={{ color: "var(--muted)", margin: "0 0 8px", fontSize: 13 }}>
              Informe qual o acesso a saneamento que estará acessível.
            </p>
            <select value={sanitation} onChange={(e) => setSanitation(e.target.value as typeof SANITATION[number]["value"])}>
              {SANITATION.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
            </select>
          </section>
        </div>
      )}

      {step === 4 && (
        <div>
          <SectionTitle>Outros Serviços</SectionTitle>
          <p style={{ color: "var(--muted)", margin: "0 0 14px", fontSize: 13 }}>
            Selecione serviços adicionais que possa precisar para o seu evento.
          </p>
          <div className="chips">
            {EXTRA_SERVICES.map((s) => (
              <button type="button" key={s} className="chip"
                data-active={extras.includes(s)}
                onClick={() => setExtras((list) => toggle(list, s))}>
                {s}
              </button>
            ))}
          </div>
        </div>
      )}

      {step === 5 && (
        <div>
          <h2 style={{ textAlign: "center", margin: "8px 0 6px", fontFamily: "Bebas Neue, sans-serif", color: "var(--ink)", fontSize: 26 }}>
            Como deseja selecionar seus trucks?
          </h2>
          <p style={{ textAlign: "center", color: "var(--muted)", margin: "0 0 20px", fontSize: 14 }}>
            Escolha como deseja prosseguir com a seleção.
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
                <div style={{ fontWeight: 700, color: "var(--ink)" }}>{m.label}</div>
                <div style={{ fontSize: 12, color: "var(--muted)", marginTop: 2 }}>{m.hint}</div>
              </button>
            ))}
          </div>
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
          Anterior
        </button>
        <button type="button" className="btn-pill" onClick={next} disabled={busy}>
          {busy ? "A submeter…" : step < 5 ? "Próximo" : "Finalizar"}
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
