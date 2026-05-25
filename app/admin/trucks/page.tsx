import Link from "next/link";
import Image from "next/image";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";
import { truckCover } from "@/lib/img";

export const dynamic = "force-dynamic";

export default async function AdminTrucksQueuePage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/admin/trucks");

  // Use metrics RPC as the admin gate — returns 0 rows for non-admins
  // because of the WHERE airfnb_is_admin() filter.
  const { data: gate } = await (supa as any).rpc("airfnb_admin_metrics");
  if (!(gate as any[])?.length) redirect("/dashboard/organizer");

  const { data: pendingTrucks } = await (supa as any)
    .rpc("airfnb_admin_pending_trucks", { p_limit: 100 });
  const trucks: any[] = (pendingTrucks as any[]) ?? [];

  async function approve(formData: FormData) {
    "use server";
    const id = String(formData.get("truck_id"));
    const supa = await supabaseServer();
    const { error } = await (supa as any).rpc("airfnb_admin_approve_truck", { p_truck: id });
    if (error) throw new Error(error.message);
    revalidatePath("/admin/trucks");
    revalidatePath("/admin");
  }
  async function reject(formData: FormData) {
    "use server";
    const id = String(formData.get("truck_id"));
    const reason = String(formData.get("reason") ?? "").trim();
    if (reason.length < 10) {
      throw new Error("Indica uma razão de pelo menos 10 caracteres — o dono vê isto.");
    }
    const supa = await supabaseServer();
    const { error } = await (supa as any).rpc("airfnb_admin_reject_truck", { p_truck: id, p_reason: reason });
    if (error) throw new Error(error.message);
    revalidatePath("/admin/trucks");
    revalidatePath("/admin");
  }

  return (
    <div className="dash" style={{ maxWidth: 1100 }}>
      <nav className="breadcrumb">
        <Link href="/admin">Admin</Link> &nbsp;/&nbsp; <span>Trucks pendentes</span>
      </nav>
      <h1 style={{ margin: 0 }}>Moderação — Trucks</h1>
      <p style={{ color: "var(--muted)", marginTop: 6 }}>
        {trucks.length === 0 ? "Sem trucks à espera." : `${trucks.length} truck${trucks.length === 1 ? "" : "s"} à espera de revisão.`}
      </p>

      <div style={{ display: "grid", gap: 16, marginTop: 22 }}>
        {trucks.map((t) => (
          <article id={t.id} key={t.id} style={{ background: "#fff", border: "1px solid var(--line)", borderRadius: 14, padding: 18, display: "grid", gridTemplateColumns: "180px 1fr", gap: 18, alignItems: "start" }}>
            <div className="thumb" style={{ aspectRatio: "4/3", borderRadius: 10, overflow: "hidden", position: "relative" }}>
              <Image
                src={truckCover(t.cover_url)}
                alt={t.name}
                fill
                sizes="180px"
                style={{ objectFit: "cover" }}
              />
            </div>
            <div style={{ display: "grid", gap: 10 }}>
              <div>
                <h2 style={{ margin: 0, fontSize: 20 }}>{t.name}</h2>
                <div style={{ color: "var(--muted)", fontSize: 13, marginTop: 2 }}>
                  {t.base_city ?? "—"} · {t.owner_name ?? "—"} · submetido {new Date(t.created_at).toLocaleDateString("pt-PT")}
                </div>
              </div>
              {t.description && (
                <p style={{ margin: 0, fontSize: 14, lineHeight: 1.5, whiteSpace: "pre-wrap" }}>
                  {t.description}
                </p>
              )}
              <div style={{ display: "flex", gap: 10, flexWrap: "wrap", marginTop: 6 }}>
                <Link href={`/catalogo/${t.slug}`} target="_blank" className="btn-pill outline"
                      style={{ padding: "8px 18px", borderColor: "var(--line)", color: "var(--ink)" }}>
                  Ver no catálogo
                </Link>
                <form action={approve}>
                  <input type="hidden" name="truck_id" value={t.id} />
                  <button type="submit" className="btn-pill" style={{ padding: "8px 18px", background: "#10A37F" }}>
                    Aprovar
                  </button>
                </form>
                <form action={reject} style={{ display: "flex", gap: 8 }}>
                  <input type="hidden" name="truck_id" value={t.id} />
                  <input
                    name="reason"
                    placeholder="Razão (vê o dono)"
                    minLength={10}
                    required
                    style={{ padding: "8px 12px", border: "1.5px solid var(--line)", borderRadius: 999, fontSize: 13, minWidth: 220 }}
                  />
                  <button type="submit" className="btn-pill" style={{ padding: "8px 18px", background: "#8B1100" }}>
                    Rejeitar
                  </button>
                </form>
              </div>
            </div>
          </article>
        ))}
      </div>
    </div>
  );
}
