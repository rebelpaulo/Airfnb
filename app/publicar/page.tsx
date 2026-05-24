import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { recommendSlots } from "@/lib/recommend";

const KINDS: Array<{ value: string; label: string }> = [
  { value: "wedding",    label: "Casamento" },
  { value: "birthday",   label: "Aniversário" },
  { value: "corporate",  label: "Corporativo" },
  { value: "festival",   label: "Festival" },
  { value: "conference", label: "Conferência" },
  { value: "private",    label: "Festa Privada" },
  { value: "other",      label: "Outro" },
];

export default async function PublicarPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/publicar&as=organizer");

  const { data: categories } = await (supa as any)
    .from("airfnb_categories")
    .select("id, slug, name_pt, icon")
    .order("name_pt");

  async function submit(formData: FormData) {
    "use server";
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error("auth required");

    const title = String(formData.get("title") ?? "").trim();
    const kind = String(formData.get("kind") ?? "other") as any;
    const start = String(formData.get("start_at"));
    const expected = Number(formData.get("expected_pax"));
    const city = String(formData.get("city") ?? "").trim();
    const budgetMin = Number(formData.get("budget_min") ?? 0) || null;
    const budgetMax = Number(formData.get("budget_max") ?? 0) || null;
    const slots = Number(formData.get("slots_needed") ?? 0) || recommendSlots(kind, expected);
    const discovery = String(formData.get("discovery_mode") ?? "broadcast") as any;
    const deals = formData.getAll("accepted_deal_types").map(String);
    const notes = String(formData.get("notes") ?? "").trim();

    const { data: row, error } = await (supa as any)
      .from("airfnb_event_requests")
      .insert({
        organizer_id: user.id,
        title,
        kind,
        start_at: new Date(start).toISOString(),
        city,
        expected_pax: expected,
        slots_needed: slots,
        budget_min: budgetMin,
        budget_max: budgetMax,
        discovery_mode: discovery,
        accepted_deal_types: deals.length ? deals : ["fixed","percent","mixed"],
        notes,
        status: "open",
        visibility: "public",
        applications_deadline: addDaysISO(start, -3),
      })
      .select("id")
      .single();

    if (error) throw new Error(error.message);
    redirect(`/dashboard/organizer/pedidos/${row.id}`);
  }

  return (
    <form action={submit} className="wizard">
      <div className="steps-pills">
        <span className="on" /><span className="on" /><span className="on" /><span className="on" /><span className="on" />
      </div>
      <h1>Publicar pedido</h1>
      <p style={{ color: "var(--muted)", margin: 0 }}>
        Em 60 segundos. Os trucks que dão match recebem alerta automaticamente.
      </p>

      <label>Título do evento</label>
      <input name="title" required maxLength={120} placeholder="Ex: Casamento no Convento de Vilar" />

      <label>Tipo de evento</label>
      <select name="kind" defaultValue="wedding" required>
        {KINDS.map((k) => <option key={k.value} value={k.value}>{k.label}</option>)}
      </select>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
        <div>
          <label>Quando (data + hora início)</label>
          <input name="start_at" type="datetime-local" required />
        </div>
        <div>
          <label>Cidade</label>
          <input name="city" required placeholder="Ex: Sintra" />
        </div>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 14 }}>
        <div>
          <label>Nº convidados</label>
          <input name="expected_pax" type="number" required min={1} defaultValue={100} />
        </div>
        <div>
          <label>Trucks pretendidos</label>
          <input name="slots_needed" type="number" min={1} max={10} placeholder="auto" />
        </div>
        <div>
          <label>Modo descoberta</label>
          <select name="discovery_mode" defaultValue="broadcast">
            <option value="broadcast">Broadcast (todos matching)</option>
            <option value="curated">Curated (eu escolho)</option>
          </select>
        </div>
      </div>

      <div className="recommend-banner">
        💡 Para o teu nº de convidados sugerimos <strong>1 truck por cada 120-200 pax</strong> (depende do tipo de evento).
        Deixa em branco e calculamos por ti.
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
        <div><label>Orçamento mínimo (€)</label><input name="budget_min" type="number" step="50" min={0} /></div>
        <div><label>Orçamento máximo (€)</label><input name="budget_max" type="number" step="50" min={0} /></div>
      </div>

      <label>Modalidades de combinação aceites</label>
      <div className="chips">
        {[
          { v: "fixed",   l: "Truck paga fixo" },
          { v: "percent", l: "Truck paga % facturação" },
          { v: "mixed",   l: "Misto" },
        ].map((d) => (
          <label key={d.v} className="chip">
            <input type="checkbox" name="accepted_deal_types" value={d.v} defaultChecked style={{ marginRight: 6 }} />
            {d.l}
          </label>
        ))}
      </div>

      <label>Notas (opcional)</label>
      <textarea name="notes" placeholder="Algo específico que queres partilhar com os trucks? Restrições, infraestrutura, vibe..." />

      <div className="actions">
        <span />
        <button className="btn-pill" type="submit">Publicar pedido</button>
      </div>
    </form>
  );
}

function addDaysISO(date: string, days: number) {
  const d = new Date(date);
  d.setDate(d.getDate() + days);
  return d.toISOString();
}
