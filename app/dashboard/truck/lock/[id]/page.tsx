import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { money } from "@/lib/money";

export default async function LockFeePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;       // application_id
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect(`/login?next=/dashboard/truck/lock/${id}`);

  const { data: app } = await supa
    .from("airfnb_applications")
    .select(`
      id, status, proposed_price, deal_type,
      airfnb_trucks ( id, name, owner_id ),
      airfnb_event_requests ( id, title, start_at, city ),
      airfnb_lock_fees ( id, amount, platform_fee, organizer_share, due_until, status )
    `)
    .eq("id", id)
    .maybeSingle();

  if (!app) notFound();
  // @ts-expect-error nested
  if (app.airfnb_trucks?.owner_id !== user.id) redirect("/dashboard/truck");

  // @ts-expect-error nested
  const lockFee = Array.isArray(app.airfnb_lock_fees) ? app.airfnb_lock_fees[0] : app.airfnb_lock_fees;
  if (!lockFee) notFound();
  if (lockFee.status === "paid") {
    return (
      <div className="dash">
        <h1>Já está confirmado 🎉</h1>
        <div className="empty">
          O lock-fee foi recebido. Vai à conversa com o organizer para combinarem os detalhes finais.
        </div>
      </div>
    );
  }

  async function checkout() {
    "use server";
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error("auth required");

    const res = await fetch(`${process.env.APP_URL}/api/stripe/checkout`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ application_id: id }),
      cache: "no-store",
    });
    const { url, error } = await res.json();
    if (error) throw new Error(error);
    redirect(url);
  }

  async function devPay() {
    "use server";
    const res = await fetch(`${process.env.APP_URL}/api/dev/mark-paid`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ application_id: id }),
      cache: "no-store",
    });
    const r = await res.json();
    if (!r.ok) throw new Error(r.error ?? "dev-pay failed");
    redirect(`/dashboard/truck?paid=${id}`);
  }

  const showDev = !process.env.STRIPE_SECRET_KEY;

  return (
    <div className="dash">
      <h1>Lock-fee para confirmar</h1>
      <div className="stat-strip">
        {/* @ts-expect-error nested */}
        <div className="stat"><div className="label">Evento</div><div className="value" style={{ fontSize: 18 }}>{app.airfnb_event_requests?.title}</div></div>
        {/* @ts-expect-error nested */}
        <div className="stat"><div className="label">Cidade</div><div className="value" style={{ fontSize: 22 }}>{app.airfnb_event_requests?.city}</div></div>
        <div className="stat"><div className="label">Total a pagar</div><div className="value">{money(lockFee.amount)}</div></div>
        <div className="stat"><div className="label">Prazo</div><div className="value" style={{ fontSize: 18 }}>
          {new Date(lockFee.due_until).toLocaleString("pt-PT", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" })}
        </div></div>
      </div>

      <div style={{ background: "#FFF6F2", padding: 22, borderRadius: 14, marginTop: 14, lineHeight: 1.7 }}>
        <p style={{ margin: 0 }}>
          <strong>{money(lockFee.platform_fee)}</strong> ficam connosco como margem da plataforma.<br />
          <strong>{money(lockFee.organizer_share)}</strong> são adiantados ao organizer — o que combinaste pagar-lhe ({app.deal_type}) será descontado em <strong>{money(lockFee.organizer_share)}</strong>.
        </p>
      </div>

      <div style={{ display: "flex", gap: 12, alignItems: "center", marginTop: 22, flexWrap: "wrap" }}>
        {!showDev && (
          <form action={checkout}>
            <button className="btn-pill" type="submit">Pagar {money(lockFee.amount)} via Stripe</button>
          </form>
        )}
        {showDev && (
          <form action={devPay}>
            <button className="btn-pill" type="submit" style={{ background: "var(--teal)" }}>
              ✓ Marcar como pago (dev)
            </button>
          </form>
        )}
        <Link href="/dashboard/truck" style={{ color: "var(--muted)" }}>Cancelar</Link>
        {showDev && (
          <small style={{ color: "var(--muted)", display: "block", flexBasis: "100%", marginTop: 6 }}>
            Stripe não configurado · a usar modo dev (precisa de <code>SUPABASE_SERVICE_ROLE_KEY</code> em .env.local)
          </small>
        )}
      </div>
    </div>
  );
}
