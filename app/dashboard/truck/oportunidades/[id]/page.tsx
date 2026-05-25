import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { money } from "@/lib/money";
import { getDictionary, getLocale } from "@/lib/i18n";

export const dynamic = "force-dynamic";

type Search = Promise<{ truck?: string }>;

/**
 * Apply (or view existing application) for a single open request.
 * Truck is passed via ?truck=<id>; if missing or invalid, default to the
 * owner's first eligible truck. The owner can switch trucks via the
 * dropdown — relevant for multi-truck companies.
 */
export default async function OportunidadeDetailPage({
  params, searchParams,
}: { params: Promise<{ id: string }>; searchParams: Search }) {
  const { id } = await params;
  const { truck: truckParam } = await searchParams;
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect(`/login?next=/dashboard/truck/oportunidades/${id}`);

  const dict = await getDictionary();
  const t = dict.dashboard.truck_opportunity_detail;
  const vocab = dict.vocab;
  const locale = await getLocale();
  const dateLocale = locale === "en" ? "en-US" : "pt-PT";

  const { data: req } = await (supa as any)
    .from("airfnb_event_requests")
    .select("*")
    .eq("id", id)
    .maybeSingle();
  if (!req) notFound();
  if (req.status !== "open") {
    // brief is closed — show read-only state on the candidaturas page instead
    redirect(`/dashboard/truck/aplicacoes`);
  }

  // Only active trucks can apply — paused/pending trucks would be rejected
  // server-side, so don't even offer them as selectable in the dropdown.
  const { data: myTrucks } = await (supa as any)
    .from("airfnb_trucks")
    .select("id, name, status")
    .eq("owner_id", user.id)
    .eq("status", "active");
  if (!myTrucks?.length) {
    // The owner has trucks but none are active — send them to the dashboard
    // so they can resume/finish-review one first.
    redirect("/dashboard/truck?notice=needs_active_truck");
  }

  const selectedTruckId =
    (truckParam && myTrucks.find((t: any) => t.id === truckParam)?.id) ??
    myTrucks[0].id;

  // Did this (truck, request) already produce an application?
  const { data: existingApp } = await (supa as any)
    .from("airfnb_applications")
    .select("id, status, proposed_price, cover_message, created_at")
    .eq("request_id", id)
    .eq("truck_id", selectedTruckId)
    .maybeSingle();

  async function apply(formData: FormData) {
    "use server";
    const dict = await getDictionary();
    const t = dict.dashboard.truck_opportunity_detail;

    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error(t.err_auth);

    const truckId = String(formData.get("truck_id") ?? "");

    // Parse + validate numerics strictly. Number("foo") is NaN and would
    // serialise as the empty string into the DB on some drivers; we'd rather
    // reject it here than let an invalid row land or rely on the check
    // constraint to surface a less-readable error.
    const priceRaw = String(formData.get("proposed_price") ?? "").trim();
    const proposedPrice = Number(priceRaw);
    const servingsRaw = String(formData.get("estimated_servings") ?? "").trim();
    const estimatedServings = servingsRaw === "" ? null : Number(servingsRaw);

    const coverMessage = String(formData.get("cover_message") ?? "").trim();

    if (!truckId)                                                       throw new Error(t.err_no_truck);
    if (!Number.isFinite(proposedPrice) || proposedPrice <= 0)          throw new Error(t.err_invalid_price);
    if (proposedPrice > 1_000_000)                                      throw new Error(t.err_price_too_high);
    if (estimatedServings !== null && (!Number.isInteger(estimatedServings) || estimatedServings < 0)) {
      throw new Error(t.err_invalid_servings);
    }
    if (coverMessage.length < 30) {
      throw new Error(t.err_message_too_short);
    }

    // Re-verify ownership server-side (the form `truck_id` is user-controlled)
    const { data: tr } = await (supa as any)
      .from("airfnb_trucks")
      .select("id, owner_id, status")
      .eq("id", truckId)
      .maybeSingle();
    if (!tr || tr.owner_id !== user.id) throw new Error(t.err_no_truck_perm);
    if (tr.status !== "active") {
      // A truck in 'paused' or 'pending_review' shouldn't be able to apply
      throw new Error(t.err_truck_not_active);
    }

    // Rate limit (50/truck/day) is enforced by a BEFORE INSERT trigger on
    // airfnb_applications. We don't precheck here because the precheck would
    // ALSO call the mutating RPC and double-charge the bucket (halving the
    // effective cap to 25). The trigger raises a Portuguese error we surface
    // verbatim in the catch below.

    // Re-check request eligibility deterministically. Without this we'd let
    // the user submit, see the row blocked by RLS, and get a cryptic error
    // instead of a clear "this brief closed / deadline passed" message.
    // PostgREST serialises timestamptz with an explicit offset, so string
    // comparison against an ISO "Z" string is fragile — parse to ms.
    const nowMs = Date.now();
    const { data: req } = await (supa as any)
      .from("airfnb_event_requests")
      .select("id, status, start_at, applications_deadline")
      .eq("id", id)
      .maybeSingle();
    if (!req) throw new Error(t.err_request_not_found);
    if (req.status !== "open")                            throw new Error(t.err_request_closed);
    if (Date.parse(req.start_at) <= nowMs)                throw new Error(t.err_event_past);
    // Use <= to match the RLS policy boundary (which allows applications_deadline > now()).
    // Otherwise we'd let the request through at the exact boundary and then surface
    // an RLS-rejected cryptic error instead of our friendly message.
    if (req.applications_deadline && Date.parse(req.applications_deadline) <= nowMs) {
      throw new Error(t.err_deadline_expired);
    }

    // Unique on (request_id, truck_id) — DB will reject duplicates. We
    // surface a friendly error instead of letting the constraint bubble.
    const { error } = await (supa as any).from("airfnb_applications").insert({
      request_id:        id,
      truck_id:          truckId,
      proposed_price:    proposedPrice,
      cover_message:     coverMessage,
      estimated_servings: estimatedServings,
      status:            "submitted",
    });
    if (error) {
      if (error.code === "23505") {
        throw new Error(t.err_duplicate);
      }
      throw new Error(error.message);
    }
    revalidatePath(`/dashboard/truck/oportunidades/${id}`);
    revalidatePath("/dashboard/truck/aplicacoes");
    redirect("/dashboard/truck/aplicacoes");
  }

  function fmtDate(iso: string): string {
    return new Date(iso).toLocaleDateString(dateLocale, { day: "2-digit", month: "short", year: "numeric" });
  }

  function labelEnergy(v: string): string {
    const m = vocab.power as Record<string, string>;
    return m[v] ?? v;
  }
  function labelSanitation(v: string): string {
    const m = vocab.sanitation as Record<string, string>;
    return m[v] ?? v;
  }

  return (
    <div className="dash" style={{ maxWidth: 820 }}>
      <nav className="breadcrumb">
        <Link href="/dashboard/truck">{t.breadcrumb_dashboard}</Link> &nbsp;/&nbsp;
        <Link href="/dashboard/truck/oportunidades">{t.breadcrumb_opportunities}</Link> &nbsp;/&nbsp;
        <span>{req.title}</span>
      </nav>

      <header style={{ marginTop: 14 }}>
        <h1 style={{ margin: 0 }}>{req.title}</h1>
        <div style={{ color: "var(--muted)", marginTop: 6 }}>
          {fmtDate(req.start_at)} · {req.city ?? req.locality ?? "—"} · {req.expected_pax} pax · {req.slots_needed ?? 1} {t.truck_plural_suffix}
          {req.budget_min || req.budget_max
            ? ` · ${t.budget_prefix} ${money(req.budget_min ?? 0)} – ${money(req.budget_max ?? 0)}`
            : ""}
        </div>
        {req.notes && (
          <p style={{ marginTop: 12, padding: 14, background: "#FFF8F4", borderRadius: 10, color: "var(--ink)", whiteSpace: "pre-wrap" }}>
            {req.notes}
          </p>
        )}
      </header>

      {(req.desired_cuisines?.length || req.dietary_requirements?.length || req.energy_need || req.sanitation_level || req.setup_minutes || req.address_line) && (
        <section style={{ marginTop: 18, padding: 18, background: "#fff", border: "1px solid var(--line)", borderRadius: 12 }}>
          <h2 style={{ margin: 0, fontSize: 15, color: "var(--muted)", textTransform: "uppercase", letterSpacing: 0.4, fontWeight: 700 }}>
            {t.briefing_title}
          </h2>
          <dl style={{ marginTop: 12, display: "grid", gridTemplateColumns: "180px 1fr", rowGap: 8, columnGap: 14, fontSize: 14 }}>
            {req.desired_cuisines?.length > 0 && (
              <>
                <dt style={{ color: "var(--muted)" }}>{t.label_cuisines}</dt>
                <dd style={{ margin: 0 }}>{req.desired_cuisines.join(", ")}</dd>
              </>
            )}
            {req.dietary_requirements?.length > 0 && (
              <>
                <dt style={{ color: "var(--muted)" }}>{t.label_dietary}</dt>
                <dd style={{ margin: 0 }}>{req.dietary_requirements.join(", ")}</dd>
              </>
            )}
            {req.energy_need && (
              <>
                <dt style={{ color: "var(--muted)" }}>{t.label_energy}</dt>
                <dd style={{ margin: 0 }}>
                  {labelEnergy(req.energy_need)}
                  {req.power_available ? ` · ${t.energy_available}` : ""}
                  {req.energy_assistance ? ` · ${t.energy_assistance}` : ""}
                </dd>
              </>
            )}
            {req.sanitation_level && (
              <>
                <dt style={{ color: "var(--muted)" }}>{t.label_sanitation}</dt>
                <dd style={{ margin: 0 }}>{labelSanitation(req.sanitation_level)}</dd>
              </>
            )}
            {req.setup_minutes && (
              <>
                <dt style={{ color: "var(--muted)" }}>{t.label_setup_time}</dt>
                <dd style={{ margin: 0 }}>{req.setup_minutes} {t.setup_min_suffix}</dd>
              </>
            )}
            {req.address_line && (
              <>
                <dt style={{ color: "var(--muted)" }}>{t.label_address}</dt>
                <dd style={{ margin: 0 }}>{req.address_line}</dd>
              </>
            )}
          </dl>
        </section>
      )}

      {existingApp ? (
        <section style={{ marginTop: 26, padding: 20, border: "1px solid var(--line)", borderRadius: 14, background: "#F8FFF9" }}>
          <h2 style={{ margin: 0, fontSize: 20 }}>{t.already_applied_title}</h2>
          <p style={{ color: "var(--muted)", marginTop: 6, fontSize: 14 }}>
            {t.already_applied_status} <strong style={{ color: "var(--ink)" }}>{existingApp.status}</strong> ·
            {" "}{t.already_applied_proposal} <strong style={{ color: "var(--ink)" }}>{money(existingApp.proposed_price)}</strong>
          </p>
          <p style={{ marginTop: 10, whiteSpace: "pre-wrap" }}>{existingApp.cover_message}</p>
          <Link href="/dashboard/truck/aplicacoes" className="btn-pill outline"
                style={{ marginTop: 12, borderColor: "var(--line)", color: "var(--ink)" }}>
            {t.already_applied_view_all}
          </Link>
        </section>
      ) : (
        <form action={apply} style={{ marginTop: 26, padding: 22, background: "#fff", border: "1px solid var(--line)", borderRadius: 14, display: "grid", gap: 14 }}>
          <h2 style={{ margin: 0, fontSize: 22 }}>{t.form_title}</h2>

          <label style={{ display: "grid", gap: 6 }}>
            <span style={{ fontSize: 13, fontWeight: 600 }}>{t.form_truck_label}</span>
            <select name="truck_id" defaultValue={selectedTruckId}>
              {myTrucks.map((tr: any) => (
                <option key={tr.id} value={tr.id}>{tr.name}{tr.status !== "active" ? ` (${tr.status})` : ""}</option>
              ))}
            </select>
          </label>

          <label style={{ display: "grid", gap: 6 }}>
            <span style={{ fontSize: 13, fontWeight: 600 }}>{t.form_price_label}</span>
            <input name="proposed_price" type="number" required min={1} step={10}
                   placeholder={req.budget_min ? String(req.budget_min) : t.form_price_default_placeholder} />
            <small style={{ color: "var(--muted)", fontSize: 12 }}>
              {t.form_price_hint}
            </small>
          </label>

          <label style={{ display: "grid", gap: 6 }}>
            <span style={{ fontSize: 13, fontWeight: 600 }}>{t.form_servings_label}</span>
            <input name="estimated_servings" type="number" min={0} placeholder={String(req.expected_pax ?? 100)} />
          </label>

          <label style={{ display: "grid", gap: 6 }}>
            <span style={{ fontSize: 13, fontWeight: 600 }}>{t.form_message_label}</span>
            <textarea name="cover_message" required minLength={30} rows={6}
                      placeholder={t.form_message_placeholder} />
            <small style={{ color: "var(--muted)", fontSize: 12 }}>
              {t.form_message_hint}
            </small>
          </label>

          <div style={{ display: "flex", justifyContent: "flex-end" }}>
            <button className="btn-pill" type="submit">{t.form_submit}</button>
          </div>
        </form>
      )}
    </div>
  );
}
