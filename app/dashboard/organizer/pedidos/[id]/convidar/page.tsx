import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import Image from "next/image";
import { supabaseServer } from "@/lib/supabase/server";
import { getDictionary } from "@/lib/i18n";
import { truckCover } from "@/lib/img";

// Where organizers with discovery_mode='curated' land after publishing.
// Lists compatible trucks (same city, at least one matching cuisine if
// the request expressed any, capacity ≥ guests) so the organiser can
// pick and invite. Server action batch-inserts invitations + fires the
// per-truck-owner notification.
//
// The detail page (/dashboard/organizer/pedidos/[id]) continues to be
// the home base after at least one invite is sent — this page exists
// purely to power the "Quero escolher os trucks" branch of the wizard.

export const dynamic = "force-dynamic";

export default async function InvitePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect(`/login?next=/dashboard/organizer/pedidos/${id}/convidar`);

  const dict = await getDictionary();
  const t = (dict as any).invite_trucks as Record<string, string>;

  const { data: req } = await (supa as any)
    .from("airfnb_event_requests")
    .select("id, organizer_id, title, city, locality, expected_pax, desired_cuisines, start_at, status, discovery_mode")
    .eq("id", id)
    .maybeSingle();
  if (!req) notFound();
  if (req.organizer_id !== user.id) redirect("/dashboard/organizer");

  const { data: candidateRows = [], error: candidateError } = await (supa as any)
    .rpc("airfnb_invitation_candidates", { p_request: id });
  if (candidateError) throw new Error(candidateError.message);
  const trucks = (candidateRows as any[]).map((row) => ({ ...row, id: row.truck_id }));

  // Show which trucks have already been invited so the UI can render a
  // muted "convidado" badge and skip them in the batch action.
  const { data: existingInvites = [] } = await (supa as any)
    .from("airfnb_request_invitations")
    .select("truck_id")
    .eq("request_id", id);
  const invitedIds = new Set<string>((existingInvites as any[]).map((r: any) => r.truck_id));

  async function inviteTrucks(formData: FormData) {
    "use server";
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error("auth required");

    const checked = formData.getAll("truck_id").map(String).filter(Boolean);
    if (checked.length === 0) return;

    const { error } = await (supa as any).rpc("airfnb_invite_request_services", {
      p_request: id,
      p_trucks: checked,
    });
    if (error) throw new Error(error.message);

    revalidatePath(`/dashboard/organizer/pedidos/${id}`);
    revalidatePath(`/dashboard/organizer/pedidos/${id}/convidar`);
    redirect(`/dashboard/organizer/pedidos/${id}`);
  }

  const newCandidates = (trucks as any[]).filter((tr: any) => !invitedIds.has(tr.id));

  return (
    <div className="container" style={{ paddingTop: 120, paddingBottom: 80, maxWidth: 1100 }}>
      <nav className="breadcrumb">
        <Link href="/dashboard/organizer">{t.breadcrumb_dash}</Link>
        &nbsp;/&nbsp;
        <Link href={`/dashboard/organizer/pedidos/${id}`}>{req.title || t.breadcrumb_request_fallback}</Link>
        &nbsp;/&nbsp;
        <span>{t.breadcrumb_self}</span>
      </nav>

      <h1 className="section-title" style={{ marginTop: 6 }}>{t.page_title}</h1>
      <p style={{ color: "var(--muted)", marginTop: 6 }}>{t.intro}</p>

      {invitedIds.size > 0 && (
        <div style={{
          marginTop: 16, padding: 12,
          background: "var(--soft-bg, #F6F7F9)",
          border: "1px solid var(--line)", borderRadius: 8, fontSize: 14,
        }}>
          {t.already_invited.replace("{n}", String(invitedIds.size))}
        </div>
      )}

      <form action={inviteTrucks} style={{ marginTop: 22 }}>
        {newCandidates.length === 0 ? (
          <div className="dash empty" style={{ padding: 32, textAlign: "center" }}>
            {invitedIds.size === 0 ? t.empty_no_matches : t.empty_all_invited}
          </div>
        ) : (
          <>
            <div style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))",
              gap: 14,
            }}>
              {newCandidates.map((tr: any) => (
                <label
                  key={tr.id}
                  style={{
                    display: "block",
                    border: "1px solid var(--line)",
                    borderRadius: 12,
                    overflow: "hidden",
                    background: "#fff",
                    cursor: "pointer",
                    position: "relative",
                  }}
                >
                  <input
                    type="checkbox"
                    name="truck_id"
                    value={tr.id}
                    style={{
                      position: "absolute", top: 10, right: 10,
                      width: 22, height: 22, accentColor: "var(--orange)",
                      cursor: "pointer", zIndex: 2,
                    }}
                  />
                  <div style={{ position: "relative", aspectRatio: "4/3" }}>
                    <Image
                      src={truckCover(tr.cover_url)}
                      alt={tr.name}
                      fill
                      sizes="(max-width: 768px) 100vw, (max-width: 1200px) 33vw, 25vw"
                      style={{ objectFit: "cover" }}
                    />
                  </div>
                  <div style={{ padding: 12 }}>
                    <div style={{ fontWeight: 700 }}>{tr.name}</div>
                    <div style={{ fontSize: 13, color: "var(--muted)", marginTop: 2 }}>
                      {(tr.category_slugs ?? []).slice(0, 3).join(" · ") || "—"}
                    </div>
                    <div style={{ display: "flex", justifyContent: "space-between", marginTop: 8, fontSize: 12, color: "var(--muted)" }}>
                      <span>{tr.base_city ?? "—"}</span>
                      <span>
                        {Number(tr.rating_count) > 0
                          ? `★ ${Number(tr.rating_avg).toFixed(1)} (${tr.rating_count})`
                          : t.new_truck_label}
                      </span>
                    </div>
                  </div>
                </label>
              ))}
            </div>

            <div style={{
              position: "sticky", bottom: 0,
              marginTop: 24, padding: 16,
              background: "rgba(255,255,255,0.95)",
              borderTop: "1px solid var(--line)",
              backdropFilter: "blur(6px)",
              display: "flex", justifyContent: "space-between", alignItems: "center",
              gap: 16, flexWrap: "wrap",
            }}>
              <div style={{ fontSize: 14, color: "var(--muted)" }}>{t.cta_hint}</div>
              <button type="submit" className="btn-pill" style={{ background: "var(--orange)", color: "#fff" }}>
                {t.cta_button}
              </button>
            </div>
          </>
        )}
      </form>

      <div style={{ marginTop: 24 }}>
        <Link
          href={`/dashboard/organizer/pedidos/${id}`}
          style={{ color: "var(--muted)", textDecoration: "underline", fontSize: 14 }}
        >
          {t.skip_link}
        </Link>
      </div>
    </div>
  );
}
